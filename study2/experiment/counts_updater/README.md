# Study 2 setup guide: GitLab and the counts updater

This guide puts the Study 2 files into GitLab and sets up the counts updater. You do it once, in about 30 minutes, most of it waiting. After that, Google runs the updater every minute on its own computers, so yours can be off.

## What the updater does

Study 2 picks each person's five vignettes from a tally file in GitLab, `global_data/global_counts.json`. The tally records how often each vignette has been shown, so the study can favor the ones that are behind. It has to be updated after every finished session, and the updater does that job:

1. A participant finishes. Pavlovia saves the session as a file in the `data` folder in GitLab.
2. Every minute, Google starts the updater.
3. The updater reads the session files and rewrites the tally.
4. The next participant's vignettes are chosen from the new tally.

It recounts from all the files each time, so it never counts a session twice.

## Before you start

- **The files `study-2.zip` and `counts_updater.zip`.** Both are in our conversation. Download them to your computer.
- **Your login for gitlab.pavlovia.org.** If the project `modeling-mental-states/study-2` already exists, your account must be a **Maintainer** of it. If it doesn't exist yet, Step 3 creates it.
- **A Google account.** A personal one is simplest, because university accounts sometimes block Google Cloud.
- **A credit or debit card.** Google asks for one before it runs anything. At this size the updater stays inside Google's free monthly allowance, so it should cost nothing.
- **Pavlovia credits or your lab's Pavlovia licence.** A study can only be set to Running when one of them covers it. The test session in Step 5 uses one credit unless you have a licence.

## Step 1: Make a GitLab key (5 minutes)

The uploader and the updater need permission to read and save files in GitLab. You give them that permission with a key, which GitLab calls a "personal access token."

1. Go to **gitlab.pavlovia.org** and sign in.
2. Click your profile picture in the top right corner, then **Edit profile**.
3. In the menu on the left, click **Access**, then **Personal access tokens**.
4. Click **Generate token**. A short list opens. Choose **Legacy token**.
5. Fill in the form:
   - Token name: `study2-counts`
   - Expiration date: a date after data collection will end
   - Scopes: tick **api**, and only that one
6. Click **Generate token** at the bottom of the form.
7. The key appears at the top of the page. It starts with `glpat-`. Copy it and paste it into a note for now.

Do not use the other choice, **Fine-grained token**. Its form shows a long list of resources such as "CI/CD" and "Repository" and has no **api** box. If you see that form, click **Cancel** and choose **Legacy token** instead.

GitLab shows the key only once. Treat it like a password.

## Step 2: Get Google Cloud ready (5 minutes)

A Google Cloud "project" is a container that will hold the updater.

1. Go to **console.cloud.google.com** and sign in with your Google account.
2. If this is your first time, accept the terms. If it offers a free trial, start it. This is where it asks for your card.
3. Click the project picker at the top of the page. It may say **Select a project** or show a project name.
4. Click **New project**, name it `study2-counts`, and click **Create**.
5. Wait a few seconds. Make sure the top of the page now shows **study2-counts**. If it doesn't, open the project picker and choose it.

## Step 3: Put the Study 2 files in GitLab (5 minutes)

Study 2 has 164 files. A small program in the Study 2 folder puts them all into GitLab at once, so you never upload files one by one. You run it in Cloud Shell, a command window inside your browser.

1. **Open Cloud Shell.** Near the top right of the Google Cloud page, click the **>_** icon ("Activate Cloud Shell"). A dark panel opens at the bottom. Wait until a line ending in `$` appears. If Cloud Shell opens as an editor with a list of files on the left, click **Open Terminal** at the top right. The commands below only work in the terminal.
2. **Upload both zips.** In that panel, click the **three dots (⋮)**, then **Upload**. Pick `study-2.zip` and `counts_updater.zip` (you can pick both at once) and click **Upload**.
3. **Paste this line** into the dark panel and press Enter:

```
unzip -o study-2.zip && python3 study-2/upload_to_gitlab.py
```

If your Mac had already unzipped the download into a folder, upload the `study-2` folder instead. Then paste `python3 study-2/upload_to_gitlab.py`.

If a box asks you to **Authorize Cloud Shell**, click **Authorize**. Then the uploader asks you two things:

1. It asks for your GitLab key. Paste it (Cmd+V on a Mac) and press **Enter**. Nothing appears on screen while you paste. That is on purpose, to keep the key hidden.
2. If the project `modeling-mental-states/study-2` does not exist yet, it offers to create it as a private project. Press **Enter**. If you already made a project for Study 2, paste its link instead. Copy the link from your browser's address bar while the project is open.

It ends with **Done** and three links: the files in GitLab, the study's page on Pavlovia, and the study link for Prolific.

**What the uploader does.** If the project is public, it offers to make it private, because the data files will hold Prolific IDs. Participants can still take part; private only hides the files. It then sends all the files in one go and checks that each one arrived. Running it again is safe. It sends only new or changed files, never deletes anything, and never touches the `data` folder. Once the tally file is in GitLab, it never replaces it. If a file was changed in GitLab after you uploaded it, it asks before replacing that file.

**If there is no `modeling-mental-states` group.** If your account has no group by that name on Pavlovia's GitLab, the uploader offers to create the project in your own account instead, as `your-username/study-2`. The counts updater then uses that project automatically. The study's web address changes with it, so update the address in the preregistration and in the Study 2 README.

## Step 4: Set up the counts updater (10 minutes, mostly waiting)

You paste one more line into the same Cloud Shell panel, and the setup does the rest. If you closed Cloud Shell, open it again as in Step 3. The files you uploaded are still there.

**Paste this line** into the dark panel and press Enter:

```
unzip -o counts_updater.zip && bash counts_updater/setup.sh
```

If your Mac had already unzipped the download into a folder, upload the `counts_updater` folder instead. Then paste `bash counts_updater/setup.sh`.

If a box asks you to **Authorize Cloud Shell**, click **Authorize**. Then the setup asks you two things:

1. It shows your project's ID, which may have numbers added to the name. Press **Enter**.
2. It asks for your GitLab key. Paste it (Cmd+V on a Mac) and press **Enter**. Nothing appears on screen while you paste. That is on purpose, to keep the key hidden.

Then wait about five minutes while it works through eight steps. It ends with **All set**. You can close Cloud Shell after that, and the updater keeps running.

**What the eight steps on screen mean:**

1. Confirm the Google Cloud project.
2. Ask GitLab whether the key works, whether it can open and save to the study-2 project, and whether the tally file is there.
3. Turn on the Google services the updater uses.
4. Create a "robot account" (a Google account for programs) with only the permissions the updater needs.
5. Store your key in Google's password safe, called Secret Manager.
6. Put the updater online. It is private, so only your project can start it.
7. Run it once as a test.
8. Set a timer that runs it every minute.

## Step 5: Turn on the study in Pavlovia and test it

1. Go to **pavlovia.org** and sign in. Open **Dashboard**, then **Experiments**, and click **study-2**. The uploader also printed a direct link to this page.
2. Set **Saving format** to **CSV**. Pavlovia then saves each finished session as a file in the `data` folder in GitLab, which is what the updater reads. With Database, the updater sees nothing.
3. **Pilot.** Set the status to **Piloting** and click **Pilot**. In pilot mode Pavlovia saves nothing: the data file downloads to the computer you piloted on. Pilot sessions therefore never reach GitLab or the tally, and there is nothing to delete afterwards.
4. **Test the updater once.** Set the status to **Running**. This needs credits or a licence. Open the study link the uploader printed and finish one session yourself. Within about a minute, the latest change on `global_data/global_counts.json` in GitLab should read "Update vignette counts: 1 completed sessions".
5. **Remove the test session.** In GitLab, open the `data` folder, click your test file, and click **Delete** (it may be under the **⋮** menu). Within a minute, the updater sets the tally back to zero. Then set the status back to **Inactive** until launch.

You can check the updater at any time. Paste this into Cloud Shell:

```
bash counts_updater/status.sh
```

It says whether the timer is running, how many session files it sees, and how many completed sessions it has counted. After you remove the test session, it should say 0 completed sessions.

## Step 6: Stop it when data collection is over

Open Cloud Shell and paste:

```
bash counts_updater/stop.sh
```

This stops the timer. The tally file in GitLab keeps its final values.

To remove everything from Google as well, delete the project. In the Google Cloud console, go to **IAM & Admin**, then **Settings**, and click **Shut down**. Then delete the GitLab key: in GitLab, go back to **Access tokens** and click **Revoke** next to `study2-counts`.

## If something goes wrong

The uploader and the setup never break anything. If one can't go on, it prints **STOPPED:** and says what to do. Do that, then paste the same line again. Running either one again is always safe.

| What it says | What to do |
|---|---|
| "GitLab did not accept this key" | The key was copied only in part, or it has expired. Make a new key (Step 1) and run it again. |
| "made without the 'api' box ticked" | Make a new Legacy token with **api** ticked. |
| A message about the Reporter, Developer or Maintainer role | Ask the project owner to make your GitLab account a Maintainer, or make the key while signed in to a Maintainer's account. |
| "did not allow this account to create a project" | Ask the owner of the `modeling-mental-states` group to create `study-2` as a private project and make you a Maintainer. Then run the uploader again. |
| "This key cannot open the project" | Do Step 3 first. If Study 2 is already in GitLab, make the key while signed in to an account that is a member of the project. |
| "does not have the file global_data/global_counts.json" | Do Step 3 first. |
| "Could not give the robot account the permission" | Google was still finishing changes from Step 3. Run the setup again. The setup now waits and retries on its own, so this should be rare. |
| "Billing is not turned on" | Open the link it prints, link a billing account, and run the setup again. |
| "The first try did not work ... trying again" | This is normal for a new project. Just wait. |

If you get stuck, copy what Cloud Shell shows and send it to me. For the counts setup, this line shows more detail:

```
tail -30 ~/study2-counts-setup.log
```

The key stops working on the expiration date you picked. To replace it, make a new key and run the setup again.

## What is in this folder

- `setup.sh` does the whole setup.
- `status.sh` shows what the updater sees.
- `stop.sh` pauses it.
- `main.py` is the updater itself. It is the only file, with `requirements.txt`, that goes to Google.
- `check_gitlab.py` does the key check and turns the updater's replies into plain sentences.
- `tests/` holds the tests. They show that the updater reproduces the Study 1 tally file exactly from the Study 1 session files, ignores incomplete sessions, never double counts, and drops deleted files.

The Study 2 uploader, `upload_to_gitlab.py`, is in the Study 2 folder. It remembers which GitLab project it used (in `~/.study2_project` in Cloud Shell), and `setup.sh` uses the same project.
