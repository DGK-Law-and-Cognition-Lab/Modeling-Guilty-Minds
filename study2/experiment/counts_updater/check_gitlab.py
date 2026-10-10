"""Plain-language helpers for setup.sh and status.sh.

  python3 check_gitlab.py check BRANCH_FILE
      Checks the GitLab key in the GITLAB_TOKEN environment variable: that GitLab
      accepts it, that it can see the study-2 project, that it can save files
      there, and that the counts file exists. Writes the name of the project's
      main branch to BRANCH_FILE. Exits with 1 and a plain message if anything
      is wrong.

  python3 check_gitlab.py explain
      Reads the updater's reply (JSON) from standard input and describes it.

Uses only the Python standard library, so it runs in Cloud Shell as is.
"""

import base64
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

GITLAB_URL = os.environ.get("GITLAB_URL", "https://gitlab.pavlovia.org").rstrip("/")
PROJECT_PATH = os.environ.get("PROJECT_PATH", "modeling-mental-states/study-2")
COUNTS_PATH = "global_data/global_counts.json"
LEVELS = {10: "Guest", 20: "Reporter", 30: "Developer", 40: "Maintainer", 50: "Owner"}


class Unreachable(Exception):
    pass


def ok(msg):
    print(f"  OK  {msg}")


def note(msg):
    print(f"  --  {msg}")


def stop(msg):
    print(f"\nSTOPPED: {msg}\n")
    sys.exit(1)


def call(path, token):
    req = urllib.request.Request(f"{GITLAB_URL}/api/v4{path}", headers={"PRIVATE-TOKEN": token})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            body = r.read().decode("utf-8")
            return r.status, (json.loads(body) if body else None)
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "replace")
        try:
            return e.code, json.loads(body)
        except ValueError:
            return e.code, body
    except (urllib.error.URLError, OSError) as e:
        raise Unreachable(str(e))


def check(branch_file):
    token = os.environ.get("GITLAB_TOKEN", "").strip()
    if not token:
        stop("No GitLab key was given.")
    project = urllib.parse.quote(PROJECT_PATH, safe="")

    try:
        # 1. Does GitLab accept the key?
        status, user = call("/user", token)
        if status == 401:
            stop("GitLab did not accept this key. It may have been copied only in part, or it "
                 "may have expired. Make a new key (Step 1 of the guide) and run the setup again.")
        if status == 403:
            # A valid key that may not read the profile (for example a fine-grained key).
            ok("GitLab accepts the key.")
        elif status != 200:
            stop(f"GitLab gave an unexpected answer when checking the key (code {status}).")
        else:
            ok(f"GitLab accepts the key. It belongs to the account '{user.get('username', '?')}'.")

        # 2. Does the key have the "api" permission? (Older GitLab versions cannot say; then skip.)
        status, info = call("/personal_access_tokens/self", token)
        if status == 200 and isinstance(info, dict):
            scopes = info.get("scopes") or []
            if info.get("granular_scopes"):
                note("This is a fine-grained key. The test run at the end will show whether its "
                     "permissions are enough. A 'Legacy token' with 'api' ticked is the simpler choice.")
            elif "api" not in scopes:
                stop("The key was made without the 'api' box ticked. Make a new key: choose "
                     "'Legacy token' and tick 'api' (Step 1 of the guide), then run the setup again.")
            else:
                ok("The key has the 'api' permission.")
            if info.get("expires_at"):
                note(f"The key expires on {info['expires_at']}. It must last until data collection ends.")

        # 3. Can the key see the study-2 project?
        status, proj = call(f"/projects/{project}", token)
        if status == 404:
            stop(f"This key cannot open the project {PROJECT_PATH}. If Study 2 is not in GitLab yet, "
                 "put it there first (Step 3 of the guide), then run the setup again. Otherwise, make "
                 "the key while signed in to an account that is a member of that project, as a "
                 "'Legacy token' with 'api' ticked (Step 1 of the guide).")
        if status == 403:
            stop(f"This key is not allowed to open the project {PROJECT_PATH}. Make a 'Legacy token' "
                 "with 'api' ticked (Step 1 of the guide) and run the setup again.")
        if status != 200:
            stop(f"GitLab gave an unexpected answer when opening the project (code {status}).")
        branch = proj.get("default_branch") or "master"
        ok(f"The key can open the project {PROJECT_PATH}. Its main branch is called '{branch}'.")

        # 4. Can the account save files to the main branch?
        perms = proj.get("permissions") or {}
        level = max((perms.get("project_access") or {}).get("access_level") or 0,
                    (perms.get("group_access") or {}).get("access_level") or 0)
        role = LEVELS.get(level, "unknown")
        if level >= 40:
            ok(f"The account is {'an' if role[0] in 'AEIOU' else 'a'} {role} of the project, so the updater can save the counts file.")
        elif level == 30:
            status, prot = call(f"/projects/{project}/protected_branches/{urllib.parse.quote(branch, safe='')}", token)
            if status == 404:
                ok("The account is a Developer and the main branch is not protected, so the updater can save files.")
            elif status == 200 and any(0 < (a.get("access_level") or 0) <= 30
                                       for a in prot.get("push_access_levels", [])):
                ok("The account is a Developer and Developers may save to the main branch.")
            elif status == 200:
                stop("This account is a Developer of the project, but only Maintainers may save to "
                     f"its main branch ('{branch}'). Ask the project owner to make the account a "
                     "Maintainer, or make the key from a Maintainer's account, then run the setup again.")
            else:
                note("Could not confirm that the account may save files. The test run at the end will show it.")
        elif level in (10, 20):
            stop(f"This account is only a {role} of the project, so it cannot save files. Ask the "
                 "project owner to make it a Maintainer, then run the setup again.")
        else:
            note("Could not confirm the account's role in the project. The test run at the end will show it.")

        # 5. Is the counts file there?
        status, f = call(f"/projects/{project}/repository/files/{urllib.parse.quote(COUNTS_PATH, safe='')}"
                         f"?ref={urllib.parse.quote(branch, safe='')}", token)
        if status == 404:
            stop(f"The project does not have the file {COUNTS_PATH} on its main branch yet. Put the "
                 "Study 2 files in GitLab first (Step 3 of the guide), then run the setup again.")
        if status != 200:
            stop(f"GitLab gave an unexpected answer when opening the counts file (code {status}).")
        try:
            counts = json.loads(base64.b64decode(f["content"]).decode("utf-8-sig"))
            n_vignettes = len(counts["overall_counts"])
            total = sum(counts["overall_counts"].values())
        except (KeyError, ValueError, TypeError):
            stop(f"The file {COUNTS_PATH} is not a valid counts file.")
        ok(f"The counts file is there: {n_vignettes} vignettes, {total // 5} completed session(s) counted so far.")

        # 6. How many session files are there? (Information only.)
        status, tree = call(f"/projects/{project}/repository/tree?path=data&ref={urllib.parse.quote(branch, safe='')}"
                            "&per_page=100", token)
        if status == 200 and isinstance(tree, list):
            n = sum(1 for x in tree if x.get("type") == "blob" and x.get("path", "").lower().endswith(".csv"))
            note(f"The data folder has {n}{'+' if len(tree) >= 100 else ''} session file(s).")
        else:
            note("There is no data folder yet. That is normal before the first session.")
    except Unreachable as e:
        stop(f"Could not reach {GITLAB_URL} ({e}). Check that the site is up, then run the setup again.")

    with open(branch_file, "w") as fh:
        fh.write(branch)


def explain():
    raw = sys.stdin.read()
    try:
        s = json.loads(raw)
        if isinstance(s, dict) and "error" in s:
            err = str(s["error"])
            print(f"  The updater could not finish. The reason it gave: {err}")
            if "401" in err:
                print("  This means GitLab did not accept the key. Make a new key and run the setup again.")
            elif "403" in err:
                print("  This means GitLab refused permission. The account that made the key must be a "
                      "Maintainer of the project.")
            elif "global_counts.json" in err and "404" in err:
                print("  This means the counts file is missing from the repository.")
            elif "Connection" in err or "Timeout" in err:
                print("  This means GitLab could not be reached just now. The updater will try again in a minute.")
            return
        files, counted = s["files"], s["sessions_counted"]
    except (ValueError, KeyError, TypeError):
        print(raw.strip())
        return
    print(f"  The updater found {files} session file(s) in the data folder and counted "
          f"{counted} completed session(s).")
    if s.get("committed"):
        print("  It saved updated counts to GitLab just now.")
    else:
        print("  The counts in GitLab were already up to date, so nothing needed saving.")


if __name__ == "__main__":
    if len(sys.argv) >= 3 and sys.argv[1] == "check":
        check(sys.argv[2])
    elif len(sys.argv) >= 2 and sys.argv[1] == "explain":
        explain()
    else:
        print(__doc__)
        sys.exit(2)
