#!/usr/bin/env bash
# Pauses the Study 2 counts updater (for example, when data collection is over).
# Run it in Google Cloud Shell:   bash counts_updater/stop.sh
# To start it again, run setup.sh. To remove everything, delete the Google Cloud project.

set -u -o pipefail
export CLOUDSDK_CORE_DISABLE_PROMPTS=1
REGION="us-central1"
JOB="study2-counts-every-minute"

echo
if gcloud scheduler jobs pause "$JOB" --location="$REGION" >/dev/null 2>&1; then
  echo "Paused. The updater will not run again until you run setup.sh."
  echo "The counts file in GitLab keeps its last values."
else
  STATE="$(gcloud scheduler jobs describe "$JOB" --location="$REGION" --format='value(state)' 2>/dev/null)"
  if [ "$STATE" = "PAUSED" ]; then
    echo "The updater was already paused."
  else
    echo "Could not find the updater's schedule in this project ($(gcloud config get-value project 2>/dev/null))."
  fi
fi
echo
