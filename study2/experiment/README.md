# Study 2 experiment

This folder holds the Study 2 task as it ran on Pavlovia, built with jsPsych 7.1.2, and the small cloud function that kept the vignette counts up to date while data were collected.

## How this copy was checked

On October 10, 2026, after data collection had ended, every file of the task was compared with the files the study's Pavlovia project serves. All of them are byte-identical, with two exceptions. In `experiment.js` the three Prolific completion codes are replaced by `REDACTED`. `global_data/global_counts.json` is the file as it was at launch, with every count at zero as the preregistration requires; the project's copy now holds the final counts. The participant-facing text that the data files record (the consent page, the eligibility item, the introduction to the element questions, and the seriousness item) is the same in every session and matches `experiment.js`.

## Files

`index.html` loads jsPsych 7.1.2 and its plugins from jsDelivr, Pavlovia's jsPsych plugin (`lib/jspsych-7-pavlovia-2022.1.1.js`, which Pavlovia supplies to every experiment and which is therefore not included), the styles, and `experiment.js`, which defines the whole session. `trialMinimisation.js` chooses each participant's five vignettes from the counts in `global_data/global_counts.json`, and `mensReaVignettes_binary.json` holds the 64 vignettes; both are unchanged from Study 1. `rpm/` holds the Raven's matrices items and images, also unchanged; they are the same files Study 1 used. `style.css` is the Study 1 style sheet with additions for the new forms. `counts_updater/` holds the function that rebuilt the counts after each completed session (see below).

## Session flow

Consent (the Study 1 page, with the stated duration changed to 10 to 12 minutes and one added sentence asking former participants not to take part), then the jury-eligibility item (Yes, No, Not sure; No ends the session with Prolific's screen-out path), the instructions, and five cases. Each case has the category choice, the slider, the justification and one Raven's item, as in Study 1. The ranking of the four definitions follows the fifth case. Then come the comprehension item and the element questions, in an order assigned once per participant by simple randomization with equal probability (`comprehension_first`), followed by the seriousness item, the demographics with the embedded attention item, the save to Pavlovia, and the debriefing (the Study 1 text plus one sentence) with the link back to Prolific.

The element questions show each case again in its original position with the same name and town, and ask the KNEW, AWARE and SHOULD questions, always in that order; the participant's earlier choice and slider rating are not shown. The comprehension item's answers (a) to (d) are shuffled, and (e), "Something else", is always last. The wording of every new item is taken from the preregistration ("Items added in Study 2" and "Demographics (revised)").

## Data the task writes

jsPsych 7 overwrites the `trial_type` column with the plugin's name (as in the Study 1 files), so each trial's own label is copied into a `task` column: `consent`, `eligibility`, `mental_state_judgment`, `risk_magnitude`, `justification`, `rpm`, `mpc_ranking`, `comprehension`, `probe_intro`, `element_probe`, `seriousness` and `demographics`. Every row also carries `study` (`study2`), the three Prolific IDs taken from the study link, `comprehension_first`, and, after the eligibility item, `eligibility`. The `element_probe` rows add `knew`, `aware` and `should` (Yes or No) with `vignette_id` and `vignette_position`; the `comprehension` row adds `comprehension_answer` (a to e, coded as in the preregistration), `comprehension_other` and `comprehension_option_order`; the `seriousness` row adds `seriousness`; and the `demographics` row adds `age`, `gender`, `gender_selfdescribe`, `race`, `race_selfdescribe`, `education`, `attention_response`, `attention_pass`, `jury_service`, `jury_case_type`, `legal_training` and `any_legal_training`. The raw files carry Prolific IDs and are not posted; `../01a_exclusions.R` and `../01b_assemble_tables.R` turned them into the tables in `../data/processed`.

## Changes from the Study 1 code

Apart from the additions above, the main task is the Study 1 code. In `experiment.js`, the block from `createTrialTimeline` through the ranking task, and `makeRpmTrial`, are the Study 1 code except for one change to the ranking task: clicking a definition that already has a number now removes the number and moves any later numbers up by one, where in Study 1 only the Clear Selections button could undo a choice. The wording, the shuffled order of the definitions and the saved ranking are unchanged. The counts file is fetched with `cache: 'no-store'` so that a browser never reuses a stale copy. The awareness item that was present but unused in Study 1 is still present and still unused.

## The counts updater

The minimisation script needs counts of how often each vignette has been shown, and a Pavlovia experiment cannot write to its own repository. `counts_updater/main.py` is a Google Cloud Run function that Cloud Scheduler called once a minute during data collection. Each run lists the session files in the project's `data` folder, reads the five vignette IDs from each completed session, rebuilds the counts from scratch from all files present, and commits the counts file when anything changed, so a run never double counts and a deleted pilot file drops out by itself. Its access key was held in Google Secret Manager and appears nowhere in these files. `setup.sh`, `status.sh`, `stop.sh` and `check_gitlab.py` set it up, report on it and stop it, `tests/test_main.py` tests it, and its README is the setup guide.

## Testing before launch

The flow was tested end to end in headless Chromium with jsPsych 7.1.2 and the same plugin versions, a stand-in for the Pavlovia plugin and a stand-in for Prolific: declined consent, eligibility No, eligibility Not sure, and full completions in both orders, including the self-describe and "Something else" text boxes, the jury follow-up question, the exclusive "None" and "Prefer not to say" options, and the refusal to submit empty forms. In every completed run the element questions showed the five cases in the order of the main task with the same names and towns, and every recorded value matched what was entered.
