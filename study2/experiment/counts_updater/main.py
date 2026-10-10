"""Vignette counts updater for Modeling Guilty Minds, Study 2.

Keeps global_data/global_counts.json in the Pavlovia (GitLab) repository in step
with the completed sessions in data/. It runs as a private Google Cloud Run
function. Cloud Scheduler calls it once a minute; only the project's own robot
account (and the project owner) is allowed to call it. setup.sh does all of this.

Each run does the same thing, so running it twice never double counts:
  1. List every CSV file in data/.
  2. Read any file it has not seen before and take the five vignette IDs from the
     row with study_completed = true (the vignette_order column). Files without
     that row (for example an incomplete session) are recorded as having no order.
  3. Rebuild the counts from scratch from all files still present in data/, so a
     deleted file (for example pilot data) drops out of the counts automatically.
  4. If anything changed, commit global_counts.json and the ledger
     (global_data/counted_files.json) together in one commit.

Settings come from environment variables (setup.sh fills them in):
  GITLAB_URL      default https://gitlab.pavlovia.org
  PROJECT_PATH    default modeling-mental-states/study-2
  BRANCH          default master
  DATA_DIR        default data
  COUNTS_PATH     default global_data/global_counts.json
  LEDGER_PATH     default global_data/counted_files.json
  GITLAB_TOKEN    GitLab access token with the api scope (kept in Secret Manager)
  WEBHOOK_SECRET  optional; only needed if the function is ever made public, in
                  which case callers must send it in the X-Gitlab-Token header
"""

import base64
import csv
import hmac
import io
import json
import logging
import os
import time
from urllib.parse import quote

import requests

try:
    import functions_framework
except ImportError:  # allows local tests without the framework installed
    functions_framework = None

log = logging.getLogger("counts_updater")
logging.basicConfig(level=logging.INFO)

GITLAB_URL = os.environ.get("GITLAB_URL", "https://gitlab.pavlovia.org").rstrip("/")
PROJECT_PATH = os.environ.get("PROJECT_PATH", "modeling-mental-states/study-2")
BRANCH = os.environ.get("BRANCH", "master")
DATA_DIR = os.environ.get("DATA_DIR", "data").strip("/")
COUNTS_PATH = os.environ.get("COUNTS_PATH", "global_data/global_counts.json")
LEDGER_PATH = os.environ.get("LEDGER_PATH", "global_data/counted_files.json")
NUM_POSITIONS = 5


class Conflict(Exception):
    """Raised when someone else changed a file between our read and our commit."""


class GitLab:
    def __init__(self, base_url, project_path, token, session=None):
        self.api = f"{base_url}/api/v4/projects/{quote(project_path, safe='')}"
        self.s = session or requests.Session()
        self.s.headers.update({"PRIVATE-TOKEN": token})

    def list_csv(self, directory, ref):
        files, page = [], 1
        while True:
            r = self.s.get(f"{self.api}/repository/tree",
                           params={"path": directory, "ref": ref, "per_page": 100, "page": page},
                           timeout=30)
            if r.status_code == 404:
                return []  # data/ does not exist yet
            r.raise_for_status()
            batch = r.json()
            files += [x["path"] for x in batch if x["type"] == "blob" and x["path"].lower().endswith(".csv")]
            if len(batch) < 100:
                return files
            page += 1

    def get_file(self, path, ref):
        """Return (text, last_commit_id), or (None, None) if the file does not exist."""
        r = self.s.get(f"{self.api}/repository/files/{quote(path, safe='')}",
                       params={"ref": ref}, timeout=30)
        if r.status_code == 404:
            return None, None
        r.raise_for_status()
        j = r.json()
        return base64.b64decode(j["content"]).decode("utf-8-sig"), j["last_commit_id"]

    def get_raw(self, path, ref):
        r = self.s.get(f"{self.api}/repository/files/{quote(path, safe='')}/raw",
                       params={"ref": ref}, timeout=60)
        r.raise_for_status()
        r.encoding = "utf-8"
        return r.text

    def commit(self, branch, message, actions):
        r = self.s.post(f"{self.api}/repository/commits",
                        json={"branch": branch, "commit_message": message, "actions": actions},
                        timeout=60)
        if r.status_code in (400, 409) and ("changed" in r.text.lower() or "conflict" in r.text.lower()
                                            or "already exists" in r.text.lower()
                                            or "doesn't exist" in r.text.lower()):
            raise Conflict(r.text)
        r.raise_for_status()
        return r.json()


def vignette_order_from_csv(text, valid_ids):
    """Return the list of five vignette IDs shown in a completed session, or None."""
    reader = csv.DictReader(io.StringIO(text))
    for row in reader:
        if str(row.get("study_completed", "")).strip().lower() == "true" and row.get("vignette_order"):
            try:
                order = json.loads(row["vignette_order"])
            except ValueError:
                return None
            if (isinstance(order, list) and len(order) == NUM_POSITIONS
                    and all(isinstance(v, str) and v in valid_ids for v in order)):
                return order
            return None
    return None


def build_counts(template, files, ledger):
    ids = list(template["overall_counts"].keys())
    overall = {i: 0 for i in ids}
    position = {i: [0] * NUM_POSITIONS for i in ids}
    for f in files:
        order = ledger.get(f)
        if order:
            for p, vid in enumerate(order):
                overall[vid] += 1
                position[vid][p] += 1
    return {"overall_counts": overall, "position_counts": position}


def dump(obj):
    return json.dumps(obj, indent=2) + "\n"


def sync(gl):
    """One pass. Returns a short summary dict."""
    counts_text, counts_commit = gl.get_file(COUNTS_PATH, BRANCH)
    if counts_text is None:
        raise RuntimeError(f"{COUNTS_PATH} not found on branch {BRANCH}")
    counts_now = json.loads(counts_text)
    valid_ids = set(counts_now["overall_counts"].keys())

    ledger_text, ledger_commit = gl.get_file(LEDGER_PATH, BRANCH)
    ledger = json.loads(ledger_text) if ledger_text else {}

    files = sorted(gl.list_csv(DATA_DIR, BRANCH))
    new_files = [f for f in files if f not in ledger]
    for f in new_files:
        ledger[f] = vignette_order_from_csv(gl.get_raw(f, BRANCH), valid_ids)
        log.info("read %s -> %s", f, ledger[f])
    removed = [f for f in list(ledger) if f not in set(files)]
    for f in removed:
        del ledger[f]

    counts_new = build_counts(counts_now, files, ledger)
    summary = {"files": len(files), "new": len(new_files), "removed": len(removed),
               "sessions_counted": sum(1 for f in files if ledger.get(f)),
               "total_assignments": sum(counts_new["overall_counts"].values())}

    counts_changed = counts_new != counts_now
    ledger_changed = bool(new_files or removed) or ledger_text is None
    if not (counts_changed or ledger_changed):
        summary["committed"] = False
        return summary

    actions = []
    if counts_changed:
        actions.append({"action": "update", "file_path": COUNTS_PATH, "content": dump(counts_new),
                        "last_commit_id": counts_commit})
    if ledger_text is None:
        actions.append({"action": "create", "file_path": LEDGER_PATH, "content": dump(ledger)})
    elif ledger_changed:
        actions.append({"action": "update", "file_path": LEDGER_PATH, "content": dump(ledger),
                        "last_commit_id": ledger_commit})
    msg = (f"Update vignette counts: {summary['sessions_counted']} completed sessions "
           f"({len(new_files)} new file(s), {len(removed)} removed) [counts-updater]")
    gl.commit(BRANCH, msg, actions)
    summary["committed"] = True
    return summary


def sync_with_retry(gl, attempts=4):
    for k in range(attempts):
        try:
            return sync(gl)
        except Conflict as e:
            log.warning("conflict on attempt %d: %s", k + 1, e)
            time.sleep(2 * (k + 1))
    raise RuntimeError("gave up after repeated conflicts")


def _authorized(request):
    # setup.sh deploys the function as private, so Google checks who is calling
    # before the request gets here. A shared secret is only needed if the
    # function is ever made public; then set WEBHOOK_SECRET.
    expected = os.environ.get("WEBHOOK_SECRET", "")
    if not expected:
        return True
    got = request.headers.get("X-Gitlab-Token", "")
    return hmac.compare_digest(expected, got)


def handle(request):
    """HTTP entry point for Cloud Run functions."""
    if not _authorized(request):
        return ("unauthorized", 401)
    try:
        gl = GitLab(GITLAB_URL, PROJECT_PATH, os.environ["GITLAB_TOKEN"])
        summary = sync_with_retry(gl)
    except Exception as e:  # report the reason to whoever called, and in the logs
        log.exception("update failed")
        return (json.dumps({"error": f"{type(e).__name__}: {e}"}), 500, {"Content-Type": "application/json"})
    log.info("summary %s", summary)
    return (json.dumps(summary), 200, {"Content-Type": "application/json"})


if functions_framework is not None:
    handle = functions_framework.http(handle)


if __name__ == "__main__":
    # Run once from the command line (handy for testing).
    summary = sync_with_retry(GitLab(GITLAB_URL, PROJECT_PATH, os.environ["GITLAB_TOKEN"]))
    print(json.dumps(summary))
