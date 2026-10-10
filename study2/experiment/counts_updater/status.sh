#!/usr/bin/env bash
# Shows whether the Study 2 counts updater is scheduled, and what it sees right now.
# Run it in Google Cloud Shell:   bash counts_updater/status.sh

set -u -o pipefail
export CLOUDSDK_CORE_DISABLE_PROMPTS=1
REGION="us-central1"
FUNCTION="study2-counts"
JOB="study2-counts-every-minute"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

URL="$(gcloud run services describe "$FUNCTION" --region="$REGION" --format='value(status.url)' 2>/dev/null)"
if [ -z "$URL" ]; then
  echo
  echo "The updater is not set up in this project ($(gcloud config get-value project 2>/dev/null))."
  echo "Run:  bash ${HERE/#"$HOME"/\~}/setup.sh"
  echo
  exit 1
fi

STATE="$(gcloud scheduler jobs describe "$JOB" --location="$REGION" --format='value(state)' 2>/dev/null)"
echo
case "$STATE" in
  ENABLED) echo "Schedule: running every minute." ;;
  PAUSED)  echo "Schedule: paused (stop.sh was run). Run setup.sh to start it again." ;;
  *)       echo "Schedule: not found. Run setup.sh to create it." ;;
esac

RESPONSE="$(curl -sS -X POST --max-time 150 \
  -H "Authorization: Bearer $(gcloud auth print-identity-token 2>/dev/null)" \
  -w '\n%{http_code}' "$URL" 2>&1)"
CODE="$(printf '%s\n' "$RESPONSE" | tail -n 1)"
BODY="$(printf '%s\n' "$RESPONSE" | sed '$d')"
echo "Running the updater once now:"
if [ "$CODE" = "200" ] || [ "$CODE" = "500" ]; then
  printf '%s' "$BODY" | python3 "$HERE/check_gitlab.py" explain
else
  echo "  Could not start the updater from Cloud Shell (code $CODE). The schedule is not affected."
fi
echo
