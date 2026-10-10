"""Tests for the counts updater against an in-memory stand-in for the GitLab API.

Run with:  python3 tests/test_main.py <path to Study 1 repo> <dir with Study 2 test CSVs>
"""
import base64
import glob
import json
import os
import sys
import types
from urllib.parse import unquote

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import main

API = "https://gitlab.test/api/v4/projects/" + main.quote("modeling-mental-states/study-2", safe="")


class Resp:
    def __init__(self, status, payload=None, text=None):
        self.status_code = status
        self._payload = payload
        self.text = text if text is not None else json.dumps(payload)
        self.encoding = "utf-8"

    def json(self):
        return self._payload

    def raise_for_status(self):
        if self.status_code >= 400:
            raise RuntimeError(f"HTTP {self.status_code}: {self.text}")


class FakeGitLab:
    """Files live in self.files as path -> (text, last_commit_id)."""

    def __init__(self):
        self.files = {}
        self.n = 0
        self.headers = {}
        self.commits = []
        self.interfere = None  # function called just before a commit is applied

    def put(self, path, text):
        self.n += 1
        self.files[path] = (text, f"c{self.n}")

    def get(self, url, params=None, timeout=None):
        assert url.startswith(API), url
        rest = url[len(API):]
        if rest == "/repository/tree":
            d = params["path"].strip("/") + "/"
            items = sorted(p for p in self.files if p.startswith(d) and "/" not in p[len(d):])
            if not items:
                return Resp(404, {"message": "404 Tree Not Found"})
            page, per = params["page"], params["per_page"]
            chunk = items[(page - 1) * per: page * per]
            return Resp(200, [{"path": p, "type": "blob", "name": p.split("/")[-1]} for p in chunk])
        if rest.startswith("/repository/files/"):
            tail = rest[len("/repository/files/"):]
            raw = tail.endswith("/raw")
            path = unquote(tail[:-4] if raw else tail)
            if path not in self.files:
                return Resp(404, {"message": "404 File Not Found"})
            text, cid = self.files[path]
            if raw:
                return Resp(200, None, text)
            return Resp(200, {"content": base64.b64encode(text.encode()).decode(), "last_commit_id": cid})
        raise AssertionError(rest)

    def post(self, url, json=None, timeout=None):
        assert url == API + "/repository/commits"
        if self.interfere:
            f, self.interfere = self.interfere, None
            f(self)
        for a in json["actions"]:
            p = a["file_path"]
            if a["action"] == "create" and p in self.files:
                return Resp(400, {"message": "A file with this name already exists"})
            if a["action"] == "update":
                if p not in self.files:
                    return Resp(400, {"message": "A file with this name doesn't exist"})
                if a.get("last_commit_id") and a["last_commit_id"] != self.files[p][1]:
                    return Resp(400, {"message": "You are attempting to update a file that has changed since you started editing it."})
        self.n += 1
        for a in json["actions"]:
            self.files[a["file_path"]] = (a["content"], f"c{self.n}")
        self.commits.append(json["commit_message"])
        return Resp(201, {"id": f"c{self.n}"})


def gl_for(fake):
    return main.GitLab("https://gitlab.test", "modeling-mental-states/study-2", "token", session=fake)


def zero_counts(ids):
    return {"overall_counts": {i: 0 for i in ids}, "position_counts": {i: [0] * 5 for i in ids}}


def check(cond, msg):
    print(("PASS " if cond else "FAIL ") + msg)
    if not cond:
        check.failed = True


check.failed = False


def main_tests(study1_dir, study2_csv_dir):
    s1_counts = json.load(open(os.path.join(study1_dir, "global_data/global_counts.json")))
    ids = list(s1_counts["overall_counts"].keys())

    # 1. Study 1 data: the updater should reproduce Study 1's own counts file for the same sessions.
    fake = FakeGitLab()
    fake.put(main.COUNTS_PATH, main.dump(zero_counts(ids)))
    s1_files = sorted(glob.glob(os.path.join(study1_dir, "data/*.csv")))
    for f in s1_files:
        fake.put("data/" + os.path.basename(f), open(f, encoding="utf-8").read())
    summary = main.sync_with_retry(gl_for(fake))
    print("   study 1 summary:", summary)
    ledger = json.loads(fake.files[main.LEDGER_PATH][0])
    # Study 1's counts file covers the 2026 sessions except three (see README).
    skip = {"modeling_mental_states_PARTICIPANT_SESSION_2026-01-19_21h13.01.910.csv",
            "modeling_mental_states_PARTICIPANT_SESSION_2026-02-24_13h03.47.708.csv",
            "modeling_mental_states_PARTICIPANT_SESSION_2026-02-24_15h45.45.935.csv"}
    subset = [p for p in ledger if "_2026-" in p and os.path.basename(p) not in skip]
    rebuilt = main.build_counts(s1_counts, subset, ledger)
    check(rebuilt == s1_counts, "parsing reproduces the Study 1 counts file exactly (overall and by position)")
    check(summary["sessions_counted"] == 249, "249 completed Study 1 sessions found")

    # 2. Study 2 flow on a fresh repository.
    fake = FakeGitLab()
    fake.put(main.COUNTS_PATH, main.dump(zero_counts(ids)))
    gl = gl_for(fake)
    s = main.sync_with_retry(gl)
    check(s["committed"] and main.LEDGER_PATH in fake.files, "first run with no data creates the ledger")
    s = main.sync_with_retry(gl)
    check(not s["committed"], "second run with nothing new makes no commit")

    s2 = sorted(glob.glob(os.path.join(study2_csv_dir, "*/data.csv")))
    for k, f in enumerate(s2):
        fake.put(f"data/study-2_PARTICIPANT_SESSION_2026-10-0{k+1}_12h00.00.000.csv", open(f, encoding="utf-8").read())
    fake.put("data/study-2_PARTICIPANT_SESSION_2026-10-09_12h00.00.000.csv",
             "\"trial_type\",\"trial_index\"\n\"pavlovia\",\"0\"\n")  # incomplete session
    s = main.sync_with_retry(gl)
    counts = json.loads(fake.files[main.COUNTS_PATH][0])
    check(s["sessions_counted"] == len(s2) and sum(counts["overall_counts"].values()) == 5 * len(s2),
          f"{len(s2)} completed Study 2 test sessions counted, incomplete file ignored")
    exp = zero_counts(ids)
    for f in s2:
        for r in __import__("csv").DictReader(open(f, encoding="utf-8")):
            if r.get("study_completed") == "true":
                for p, v in enumerate(json.loads(r["vignette_order"])):
                    exp["overall_counts"][v] += 1
                    exp["position_counts"][v][p] += 1
    check(counts == exp, "Study 2 counts match the orders in the files, by position")
    before = len(fake.commits)
    main.sync_with_retry(gl)
    check(len(fake.commits) == before, "re-running does not double count or commit")

    # 3. Deleting a file (pilot data) removes it from the counts.
    victim = sorted(p for p in fake.files if p.startswith("data/"))[0]
    del fake.files[victim]
    s = main.sync_with_retry(gl)
    counts = json.loads(fake.files[main.COUNTS_PATH][0])
    check(s["removed"] == 1 and sum(counts["overall_counts"].values()) == 5 * (len(s2) - 1),
          "a deleted data file drops out of the counts")

    # 4. A concurrent change to the counts file between read and commit is detected and retried.
    fake.put("data/study-2_PARTICIPANT_SESSION_2026-10-10_12h00.00.000.csv", open(s2[0], encoding="utf-8").read())
    fake.interfere = lambda fk: fk.put(main.COUNTS_PATH, fk.files[main.COUNTS_PATH][0])
    s = main.sync_with_retry(gl)
    counts = json.loads(fake.files[main.COUNTS_PATH][0])
    check(s["committed"] and sum(counts["overall_counts"].values()) == 5 * len(s2),
          "conflict is retried and the final counts are correct")

    # 5. With no shared secret set (the normal, private setup), Google's access control is relied on.
    os.environ.pop("WEBHOOK_SECRET", None)
    check(main._authorized(types.SimpleNamespace(headers={})) is True, "no secret set: request is allowed")

    # 6. A failure is reported back in plain form instead of crashing.
    os.environ["GITLAB_TOKEN"] = "x"
    saved = main.GITLAB_URL
    main.GITLAB_URL = "http://127.0.0.1:9"
    body, code, _ = main.handle(types.SimpleNamespace(headers={}))
    main.GITLAB_URL = saved
    check(code == 500 and "error" in json.loads(body), "an unreachable GitLab gives a 500 reply with the reason")

    # 7. If a shared secret is ever set, it is enforced.
    os.environ["WEBHOOK_SECRET"] = "s3cret"
    req = types.SimpleNamespace(headers={"X-Gitlab-Token": "wrong"})
    check(main._authorized(req) is False, "wrong secret is rejected")
    req = types.SimpleNamespace(headers={"X-Gitlab-Token": "s3cret"})
    check(main._authorized(req) is True, "right secret is accepted")

    print("ALL PASSED" if not check.failed else "SOME TESTS FAILED")


if __name__ == "__main__":
    main.time.sleep = lambda s: None
    main_tests(sys.argv[1], sys.argv[2])
