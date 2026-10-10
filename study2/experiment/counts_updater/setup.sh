#!/usr/bin/env bash
# Sets up the Study 2 vignette counts updater on Google Cloud.
#
# Run it in Google Cloud Shell:   bash counts_updater/setup.sh
#
# It asks for one thing (your GitLab key), then does everything else.
# It is safe to run again, for example to replace an expired key or to restart
# the updater after stop.sh.

set -u -o pipefail
export CLOUDSDK_CORE_DISABLE_PROMPTS=1   # gcloud never stops to ask questions

REGION="us-central1"
FUNCTION="study2-counts"                 # the updater
JOB="study2-counts-every-minute"         # the timer that starts it
ROBOT="study2-counts"                    # the robot account it runs as
SECRET="study2-gitlab-key"               # where the GitLab key is kept
GITLAB_URL="${GITLAB_URL:-https://gitlab.pavlovia.org}"
# The Study 2 project in GitLab. The Study 2 uploader (study-2/upload_to_gitlab.py)
# remembers the project it used in ~/.study2_project; otherwise the default is used.
SAVED_PROJECT=""
if [ -f "$HOME/.study2_project" ]; then SAVED_PROJECT="$(tr -d '[:space:]' < "$HOME/.study2_project")"; fi
PROJECT_PATH="${PROJECT_PATH:-${SAVED_PROJECT:-modeling-mental-states/study-2}}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHOWN="${HERE/#"$HOME"/\~}"
LOG="$HOME/study2-counts-setup.log"
LAST="$HOME/.study2-counts-last-command.log"   # output of the most recent command only
: > "$LOG"
: > "$LAST"

step() { printf '\n[Step %s of 8] %s\n' "$1" "$2"; }
stop() {
  printf '\nSTOPPED: %s\n' "$1"
  local said
  said="$(grep -E '^ERROR:' "$LAST" 2>/dev/null | tail -n 1 | cut -c 1-400)"
  [ -n "$said" ] && printf "Google's message: %s\n" "$said"
  printf 'Details are saved in %s. Nothing is broken; fix the problem above and run the setup again.\n\n' "${LOG/#"$HOME"/\~}"
  exit 1
}
# Run a command quietly. Its output goes to the log (and to $LAST, for the STOPPED message).
quiet() {
  printf '\n$ %s\n' "$*" >>"$LOG"
  "$@" >"$LAST" 2>&1
  local rc=$?
  cat "$LAST" >>"$LOG"
  return $rc
}
# Permission changes can collide with changes Google is still making in the background
# (for example right after Step 3 turns services on). Try up to five times, waiting longer each time.
retry() {
  local i
  for i in 1 2 3 4 5; do
    "$@" && return 0
    if [ "$i" -lt 5 ]; then
      echo "  Google is still busy with an earlier change. Trying again in $((i * 15)) seconds..."
      sleep $((i * 15))
    fi
  done
  return 1
}

cd "$HERE" || exit 1
echo
echo "This sets up the Study 2 counts updater. It takes about 5 minutes."

# -----------------------------------------------------------------------------
step 1 "Checking your Google Cloud project"
PROJECT="$(gcloud config get-value project 2>/dev/null)"
if [ -z "$PROJECT" ]; then
  echo "  No project is selected."
  read -r -p "  Type your project ID (shown on the Google Cloud welcome page) and press Enter: " PROJECT
  PROJECT="$(printf '%s' "$PROJECT" | tr -d '[:space:]')"
  [ -n "$PROJECT" ] || stop "No project ID was typed."
  quiet gcloud config set project "$PROJECT" || stop "Cloud Shell could not switch to the project '$PROJECT'."
fi
quiet gcloud projects describe "$PROJECT" \
  || stop "Google Cloud cannot find a project with the ID '$PROJECT', or your account cannot open it."
echo "  Project: $PROJECT"
read -r -p "  Press Enter to set up the updater in this project (or press Ctrl+C to cancel): " _

# -----------------------------------------------------------------------------
step 2 "Checking your GitLab key"
echo "  The Study 2 project in GitLab: $PROJECT_PATH"
echo "  Paste your GitLab key and press Enter. For safety, it will not appear on screen."
read -r -s -p "  GitLab key: " TOKEN
echo
TOKEN="$(printf '%s' "$TOKEN" | tr -d '[:space:]')"
[ -n "$TOKEN" ] || stop "No key was pasted. Run the setup again and paste the key when asked."
[ "${#TOKEN}" -ge 8 ] || stop "That key is too short. Copy the whole key and run the setup again."
echo "  Got a key ending in ...${TOKEN: -4}. Asking GitLab about it:"
GITLAB_TOKEN="$TOKEN" GITLAB_URL="$GITLAB_URL" PROJECT_PATH="$PROJECT_PATH" \
  python3 "$HERE/check_gitlab.py" check "$HERE/.branch" || exit 1
BRANCH="$(cat "$HERE/.branch")"
rm -f "$HERE/.branch"

# -----------------------------------------------------------------------------
step 3 "Turning on the Google Cloud services the updater uses (1 to 2 minutes)"
quiet gcloud services enable cloudbilling.googleapis.com cloudresourcemanager.googleapis.com \
  || stop "Google Cloud would not turn on its basic services for this project."
BILLING="$(gcloud billing projects describe "$PROJECT" --format='value(billingEnabled)' 2>>"$LOG" | tr '[:upper:]' '[:lower:]')"
if [ "$BILLING" = "false" ]; then
  stop "Billing is not turned on for this project. Open
  https://console.cloud.google.com/billing/linkedaccount?project=$PROJECT
  link a billing account, and run the setup again."
fi
quiet gcloud services enable cloudfunctions.googleapis.com run.googleapis.com cloudbuild.googleapis.com \
  artifactregistry.googleapis.com logging.googleapis.com secretmanager.googleapis.com \
  cloudscheduler.googleapis.com iam.googleapis.com \
  || stop "Google Cloud would not turn on the services. This usually means billing is not set up. Open
  https://console.cloud.google.com/billing/linkedaccount?project=$PROJECT
  link a billing account, and run the setup again."
echo "  Done."

# -----------------------------------------------------------------------------
step 4 "Creating the updater's robot account and giving it permissions"
ROBOT_EMAIL="$ROBOT@$PROJECT.iam.gserviceaccount.com"
NEW_ROBOT=0
if ! quiet gcloud iam service-accounts describe "$ROBOT_EMAIL"; then
  quiet gcloud iam service-accounts create "$ROBOT" --display-name="Study 2 counts updater" \
    || stop "Could not create the robot account."
  NEW_ROBOT=1
  for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
    quiet gcloud iam service-accounts describe "$ROBOT_EMAIL" && break
    sleep 5
  done
fi
# The three permissions Google lists for building and running a function under its own account.
for ROLE in roles/logging.logWriter roles/artifactregistry.writer roles/storage.objectViewer; do
  retry quiet gcloud projects add-iam-policy-binding "$PROJECT" --member="serviceAccount:$ROBOT_EMAIL" \
    --role="$ROLE" --condition=None \
    || stop "Could not give the robot account the permission $ROLE."
done
echo "  Done."

# -----------------------------------------------------------------------------
step 5 "Storing your GitLab key in Google's password safe (Secret Manager)"
if quiet gcloud secrets describe "$SECRET"; then
  printf '%s' "$TOKEN" | quiet gcloud secrets versions add "$SECRET" --data-file=- \
    || stop "Could not store the new key."
else
  printf '%s' "$TOKEN" | quiet gcloud secrets create "$SECRET" --replication-policy=automatic --data-file=- \
    || stop "Could not store the key."
fi
retry quiet gcloud secrets add-iam-policy-binding "$SECRET" --member="serviceAccount:$ROBOT_EMAIL" \
  --role=roles/secretmanager.secretAccessor \
  || stop "Could not let the robot account read the key."
unset TOKEN
echo "  Done."

# -----------------------------------------------------------------------------
step 6 "Putting the updater on Google Cloud (2 to 4 minutes)"
if [ "$NEW_ROBOT" = 1 ]; then
  echo "  Waiting one minute for the new permissions to take effect..."
  sleep 60
fi
deploy() {
  quiet gcloud functions deploy "$FUNCTION" --gen2 --region="$REGION" --runtime=python312 \
    --source="$HERE" --entry-point=handle --trigger-http --no-allow-unauthenticated \
    --service-account="$ROBOT_EMAIL" \
    --build-service-account="projects/$PROJECT/serviceAccounts/$ROBOT_EMAIL" \
    --memory=256Mi --timeout=120s --max-instances=1 \
    --set-env-vars="GITLAB_URL=$GITLAB_URL,PROJECT_PATH=$PROJECT_PATH,BRANCH=$BRANCH" \
    --set-secrets="GITLAB_TOKEN=$SECRET:latest"
}
if ! deploy; then
  echo "  The first try did not work. This often happens while new permissions are still taking effect."
  echo "  Waiting two minutes, then trying again..."
  sleep 120
  deploy || stop "Google Cloud could not put the updater online."
fi
URL="$(gcloud run services describe "$FUNCTION" --region="$REGION" --format='value(status.url)' 2>>"$LOG")"
[ -n "$URL" ] || stop "The updater went online, but its address could not be found."
retry quiet gcloud run services add-iam-policy-binding "$FUNCTION" --region="$REGION" \
  --member="serviceAccount:$ROBOT_EMAIL" --role=roles/run.invoker \
  || stop "Could not let the robot account start the updater."
echo "  Done. The updater is online. It is private: only this project can start it."

# -----------------------------------------------------------------------------
step 7 "Running the updater once as a test"
sleep 5
RESPONSE="$(curl -sS -X POST --max-time 150 \
  -H "Authorization: Bearer $(gcloud auth print-identity-token 2>>"$LOG")" \
  -w '\n%{http_code}' "$URL" 2>>"$LOG")"
CODE="$(printf '%s\n' "$RESPONSE" | tail -n 1)"
BODY="$(printf '%s\n' "$RESPONSE" | sed '$d')"
printf '\n$ test run -> HTTP %s\n%s\n' "$CODE" "$BODY" >>"$LOG"
case "$CODE" in
  200)
    printf '%s' "$BODY" | python3 "$HERE/check_gitlab.py" explain ;;
  401|403)
    echo "  Google did not let Cloud Shell start the updater for a test (code $CODE)."
    echo "  That does not affect the schedule. Check the counts file in GitLab after a minute." ;;
  *)
    printf '%s' "$BODY" | python3 "$HERE/check_gitlab.py" explain
    stop "The test run did not work (code $CODE). See the reason above." ;;
esac

# -----------------------------------------------------------------------------
step 8 "Scheduling the updater to run every minute"
SCHED=(--location="$REGION" --schedule="* * * * *" --uri="$URL" --http-method=POST
       --oidc-service-account-email="$ROBOT_EMAIL" --oidc-token-audience="$URL"
       --attempt-deadline=120s --description="Study 2: update the vignette counts in GitLab")
if quiet gcloud scheduler jobs describe "$JOB" --location="$REGION"; then
  quiet gcloud scheduler jobs update http "$JOB" "${SCHED[@]}" || stop "Could not update the schedule."
  quiet gcloud scheduler jobs resume "$JOB" --location="$REGION" || true   # in case stop.sh paused it
else
  quiet gcloud scheduler jobs create http "$JOB" "${SCHED[@]}" || stop "Could not create the schedule."
fi
echo "  Done."

cat <<EOF

=====================================================================
 All set. The updater now runs every minute, on its own.
=====================================================================
 It reads the session files Pavlovia saves in GitLab and keeps
 global_data/global_counts.json up to date.

 To check on it later, open Cloud Shell and type:
     bash $SHOWN/status.sh

 To stop it when data collection is over, type:
     bash $SHOWN/stop.sh

EOF
