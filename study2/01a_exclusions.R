# =============================================================================
# Modeling Guilty Minds, Study 2
# Stage 1a: the registered exclusions, from the exclusion variables only
# -----------------------------------------------------------------------------
# Run from the analysis folder:   Rscript 01a_exclusions.R
#
# The preregistration says the exclusions are applied once, after data
# collection stops, "with a script that reads only the exclusion variables. It
# never reads the category choices, slider ratings, justifications, or probe
# answers." This is that script. From each session file it reads only the
# columns listed in EXCLUSION_COLUMNS. The one exception is the response
# column, which holds many different answers: the script keeps its value on the
# consent row and discards the rest as each file is read. From Prolific's
# export it reads only the status and time columns, not the demographics.
#
# Inputs
#   data/raw/*.csv            the Pavlovia session files (results download)
#   data/prolific_export.csv  Prolific's export of the study's submissions
#
# Outputs
#   data/processed/study2_sessions.csv    one row per session file: how far it got
#   data/processed/study2_exclusions.csv  one row per person who completed the
#                                         study: completion order, exclusion
#                                         flags, sample membership
#   data/processed/prolific_followup.csv  people whose Prolific status does not
#                                         match what they did (holds Prolific
#                                         IDs; keep private)
#   output/stage1_flow.csv                the participant flow table
#
# Registered rules (preregistration, "Sample, recruitment, and stopping rule"
# and "Exclusion criteria") and how they are applied:
#   * Collection was to stop at 200 completed sessions, and 271 were
#     completed. The primary analysis uses every completed session (the full
#     sample), a deviation reported in the manuscript. The first 200 completed
#     sessions in order of completion, the sample the stopping rule implies,
#     are flagged for a robustness analysis.
#   * A session is complete when it has all five cases and the full probe
#     block. People are excluded if they failed the attention item (any answer
#     other than "Somewhat disagree"), chose "I did not take it seriously", or
#     finished in less than one third of the median completion time of the
#     first 40 completed sessions. The threshold is computed once, from
#     completion times alone.
#   * When a Prolific ID appears more than once, only the first complete
#     session is kept.
#
# Timing
#   Completion time is the session's length on the experiment's own clock
#   (jsPsych's time_elapsed). jsPsych restarts that clock when the main part of
#   the study loads, so the length is the sum of the two parts.
#   Order of completion is on Prolific's clock. Pavlovia names each file with
#   the time it was saved, on the participant's computer, in their time zone.
#   Each session therefore ends at the person's Prolific start time plus the
#   time that passed on their own computer from the start of their first
#   session to the end of this one. For a person with one session, that is
#   simply the Prolific start time plus the session's length.
# =============================================================================

# Work from the study2_analysis folder. Opening study2_analysis.Rproj in RStudio does that; so do the
# lines below when the script is run with RStudio's Source button. Use Source, not Run: Run keeps going
# after an error, which produces confusing follow-on errors.
if (!file.exists("MPC_Study2_Analysis.Rmd")) {
  here <- tryCatch(dirname(sys.frame(1)$ofile), error = function(e) "")
  if (!nzchar(here) || !file.exists(file.path(here, "MPC_Study2_Analysis.Rmd")))
    here <- tryCatch(dirname(rstudioapi::getSourceEditorContext()$path), error = function(e) "")
  if (nzchar(here) && file.exists(file.path(here, "MPC_Study2_Analysis.Rmd"))) setwd(here)
}
if (!file.exists("MPC_Study2_Analysis.Rmd"))
  stop("Run this script from the study2_analysis folder: open study2_analysis.Rproj in RStudio, ",
       "or use Session > Set Working Directory > To Source File Location, then press Source.", call. = FALSE)

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(tidyr)
  library(purrr)
  library(stringr)
})

RAW_DIR       <- "data/raw"
PROLIFIC      <- "data/prolific_export.csv"
OUT_DIR       <- "data/processed"
FIRST_N       <- 200   # the registered stopping rule, kept for the robustness analysis
SPEED_FIRST_N <- 40    # the speed rule uses the median of the first 40 completed sessions

EXCLUSION_COLUMNS <- c("prolific_pid", "trial_index", "trial_type", "task", "time_elapsed",
                       "eligibility", "study_completed", "attention_pass", "seriousness",
                       "comprehension_first")

dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)
dir.create("output", showWarnings = FALSE)
stopifnot(dir.exists(RAW_DIR), file.exists(PROLIFIC))

first_value <- function(v) { v <- v[!is.na(v) & v != ""]; if (length(v)) v[1] else NA_character_ }

# -----------------------------------------------------------------------------
# 1. Read the exclusion columns from every session file
# -----------------------------------------------------------------------------
read_exclusion_columns <- function(path) {
  d <- read_csv(path, col_types = cols(.default = col_character()),
                col_select = any_of(c(EXCLUSION_COLUMNS, "response")), progress = FALSE)
  for (col in setdiff(c(EXCLUSION_COLUMNS, "response"), names(d))) d[[col]] <- NA_character_
  d %>%
    mutate(consent_response = if_else(coalesce(task, "") == "consent", response, NA_character_),
           file = basename(path)) %>%
    select(-response)
}

files <- list.files(RAW_DIR, pattern = "\\.csv$", full.names = TRUE)
x <- map_dfr(files, read_exclusion_columns) %>%
  mutate(trial_index  = as.integer(trial_index),
         time_elapsed = as.numeric(time_elapsed),
         task         = coalesce(task, ""))
stopifnot(!any(is.na(x$time_elapsed)), !any(is.na(x$trial_index)))

# Pavlovia's file name gives the time the file was saved, on the participant's clock.
file_saved_local <- function(f) {
  m <- str_match(f, "(\\d{4}-\\d{2}-\\d{2})_(\\d{2})h(\\d{2})\\.(\\d{2})\\.(\\d{1,3})\\.csv$")
  stopifnot(!any(is.na(m[, 1])))
  as.POSIXct(paste0(m[, 2], " ", m[, 3], ":", m[, 4], ":", m[, 5]), tz = "UTC") + as.numeric(m[, 6]) / 1000
}

# -----------------------------------------------------------------------------
# 2. One row per session file
# -----------------------------------------------------------------------------
STAGES <- c("Closed the page before answering the consent question",
            "Declined consent",
            "Left at the eligibility question",
            "Screened out (answered No to the eligibility question)",
            "Left before the first case",
            "Left during the five cases",
            "Left during the ranking, comprehension item or probe",
            "Completed")

sessions <- x %>%
  arrange(file, trial_index) %>%
  group_by(file) %>%
  mutate(clock_part = cumsum(c(TRUE, diff(time_elapsed) < 0))) %>%
  summarise(
    pid                 = first_value(prolific_pid),
    consent             = first_value(consent_response),
    eligibility         = first_value(eligibility),
    completed           = any(tolower(coalesce(study_completed, "")) == "true"),
    n_cases             = sum(task == "mental_state_judgment"),
    n_probe             = sum(task == "element_probe"),
    reached_ranking     = any(task == "mpc_ranking"),
    clock_parts         = max(clock_part),
    duration_min        = sum(tapply(time_elapsed, clock_part, max)) / 60000,
    attention_pass      = first_value(attention_pass),
    seriousness         = first_value(seriousness),
    comprehension_first = first_value(comprehension_first),
    .groups = "drop"
  ) %>%
  mutate(
    file_saved_local = file_saved_local(file),
    stage = case_when(
      completed                       ~ "Completed",
      is.na(consent)                  ~ STAGES[1],
      consent == "1"                  ~ STAGES[2],
      is.na(eligibility)              ~ STAGES[3],
      eligibility == "No"             ~ STAGES[4],
      n_cases == 0                    ~ STAGES[5],
      n_cases < 5 | !reached_ranking  ~ STAGES[6],
      TRUE                            ~ STAGES[7]),
    stage_rank = match(stage, STAGES)
  )

# A completed session has all five cases and the full probe block, because the
# completion flag is written after the probe and the comprehension item.
stopifnot(all(with(sessions, !completed | (n_cases == 5 & n_probe == 5))),
          !any(is.na(sessions$pid)), !any(sessions$pid == ""))

# -----------------------------------------------------------------------------
# 3. Prolific: status and times (UTC). Demographic columns are not read.
# -----------------------------------------------------------------------------
prolific <- read_csv(PROLIFIC, col_types = cols(.default = col_character()),
                     col_select = c(`Participant id`, Status, `Started at`, `Completed at`,
                                    `Time taken`, `Completion code`),
                     progress = FALSE) %>%
  transmute(pid                = `Participant id`,
            prolific_status    = Status,
            prolific_started   = as.POSIXct(`Started at`,   format = "%Y-%m-%dT%H:%M:%OS", tz = "UTC"),
            prolific_completed = as.POSIXct(`Completed at`, format = "%Y-%m-%dT%H:%M:%OS", tz = "UTC"),
            prolific_minutes   = as.numeric(`Time taken`) / 60,
            prolific_code      = `Completion code`)
stopifnot(!any(duplicated(prolific$pid)), all(sessions$pid %in% prolific$pid))

# End of each session on Prolific's clock (see Timing at the top).
sessions <- sessions %>%
  left_join(prolific %>% select(pid, prolific_started), by = "pid") %>%
  group_by(pid) %>%
  mutate(first_start_local = (file_saved_local - duration_min * 60)[which.min(file_saved_local)],
         end_utc = prolific_started +
           as.numeric(difftime(file_saved_local, first_start_local, units = "secs"))) %>%
  ungroup() %>%
  select(-first_start_local, -prolific_started)

# -----------------------------------------------------------------------------
# 4. Completed sessions: the duplicate rule and the order of completion
# -----------------------------------------------------------------------------
complete <- sessions %>% filter(stage == "Completed") %>% arrange(end_utc)
stopifnot(!any(is.na(complete$end_utc)))
complete <- complete %>% group_by(pid) %>% mutate(later_duplicate = row_number() > 1) %>% ungroup()

people <- complete %>%
  filter(!later_duplicate) %>%
  arrange(end_utc) %>%
  mutate(completion_order = row_number(),
         participant      = sprintf("P%03d", completion_order),
         in_first_200     = completion_order <= FIRST_N)

# Speed rule: one third of the median completion time of the first 40 completed sessions.
speed_median    <- median(people$duration_min[people$completion_order <= SPEED_FIRST_N])
speed_threshold <- speed_median / 3

people <- people %>%
  mutate(
    excl_attention      = is.na(attention_pass) | attention_pass != "true",
    excl_serious        = coalesce(seriousness == "not_serious", FALSE),
    excl_speed          = duration_min < speed_threshold,
    excluded            = excl_attention | excl_serious | excl_speed,
    included            = !excluded,                  # primary: the full sample
    included_first_200  = in_first_200 & !excluded    # robustness: the first 200
  )

# Other sessions of the same people. Not exclusions; recorded so they can be reported.
others <- sessions %>%
  filter(pid %in% people$pid, !file %in% people$file) %>%
  left_join(people %>% select(pid, kept_saved = file_saved_local), by = "pid") %>%
  group_by(pid) %>%
  summarise(sessions_before   = sum(file_saved_local < kept_saved),
            cases_seen_before = sum(n_cases[file_saved_local < kept_saved]),
            sessions_after    = sum(file_saved_local > kept_saved),
            other_eligibility = paste(sort(unique(na.omit(eligibility))), collapse = "; "),
            .groups = "drop")
people <- people %>%
  left_join(others, by = "pid") %>%
  mutate(across(c(sessions_before, cases_seen_before, sessions_after), ~ coalesce(.x, 0L)),
         eligibility_conflict = coalesce(str_detect(other_eligibility, "\\bNo\\b"), FALSE)) %>%
  left_join(prolific %>% select(pid, prolific_status, prolific_completed, prolific_minutes), by = "pid")

sessions <- sessions %>% mutate(kept = file %in% people$file)

# -----------------------------------------------------------------------------
# 5. Prolific follow-up: status that does not match what the person did
# -----------------------------------------------------------------------------
paid_ok <- c("AWAITING REVIEW", "APPROVED")
followup <- bind_rows(
  people %>% filter(!prolific_status %in% paid_ok) %>%
    transmute(pid, prolific_status, what_happened = "Completed the study",
              action = "Pay in full: the session is complete"),
  prolific %>% filter(prolific_status %in% paid_ok, !pid %in% people$pid) %>%
    transmute(pid, prolific_status, what_happened = "No completed session file",
              action = "Check before approving")
)

# -----------------------------------------------------------------------------
# 6. Write the outputs
# -----------------------------------------------------------------------------
write_csv(sessions %>%
            mutate(consent = case_when(consent == "0" ~ "Yes", consent == "1" ~ "No")) %>%
            select(file, pid, stage, consent, eligibility, completed, n_cases, n_probe,
                   duration_min, file_saved_local, end_utc, kept),
          file.path(OUT_DIR, "study2_sessions.csv"))

write_csv(people %>%
            select(participant, pid, file, completion_order, end_utc, duration_min,
                   prolific_status, prolific_minutes, eligibility, comprehension_first,
                   attention_pass, seriousness, starts_with("excl_"), excluded,
                   included, in_first_200, included_first_200,
                   sessions_before, cases_seen_before, sessions_after, eligibility_conflict),
          file.path(OUT_DIR, "study2_exclusions.csv"))

write_csv(followup, file.path(OUT_DIR, "prolific_followup.csv"))

# -----------------------------------------------------------------------------
# 7. Flow table (people, not files). A person who completed counts as completed.
#    A person who never completed counts at the point where their last session
#    stopped (one person answered Not sure, left, came back and answered No).
# -----------------------------------------------------------------------------
furthest <- sessions %>%
  group_by(pid) %>%
  summarise(stage_rank = if (any(stage == "Completed")) length(STAGES)
                         else stage_rank[which.max(file_saved_local)],
            .groups = "drop")
reasons <- function(d, label) {
  tibble(step = c(label,
                  "  failed the attention item",
                  "  chose \"I did not take it seriously\"",
                  sprintf("  finished in under %.2f minutes", speed_threshold),
                  "  excluded for any reason",
                  "  analysed"),
         n = c(nrow(d), sum(d$excl_attention), sum(d$excl_serious), sum(d$excl_speed),
               sum(d$excluded), sum(!d$excluded)))
}
flow <- bind_rows(
  tibble(step = "Prolific submissions in the export", n = nrow(prolific)),
  tibble(step = "Prolific IDs with at least one session file", n = n_distinct(sessions$pid)),
  tibble(step = STAGES[-length(STAGES)], n = map_int(seq_along(STAGES)[-length(STAGES)], ~ sum(furthest$stage_rank == .x))) %>%
    mutate(step = paste0("  ", step)),
  tibble(step = "  Completed the study", n = nrow(people)),
  reasons(people, "Full sample (primary): everyone who completed"),
  reasons(people %>% filter(in_first_200), sprintf("Robustness sample: the first %d to complete", FIRST_N))
)
write_csv(flow, "output/stage1_flow.csv")

# -----------------------------------------------------------------------------
# 8. Report (exclusion and timing variables only)
# -----------------------------------------------------------------------------
cat("\nParticipant flow\n")
print(as.data.frame(flow), row.names = FALSE, right = FALSE)

cat(sprintf("\nSpeed rule: the first %d completers' median length was %.2f minutes, so the threshold is %.2f minutes.\n",
            SPEED_FIRST_N, speed_median, speed_threshold))
cat(sprintf("Session length for everyone who completed: median %.1f minutes on the experiment's clock; Prolific's median time taken was %.1f minutes.\n",
            median(people$duration_min), median(people$prolific_minutes, na.rm = TRUE)))

cat("\nProlific status of the people who completed the study\n")
print(as.data.frame(count(people, prolific_status)), row.names = FALSE)
cat(sprintf("Prolific follow-up list: %d people (see data/processed/prolific_followup.csv)\n", nrow(followup)))
print(as.data.frame(count(followup, what_happened, prolific_status)), row.names = FALSE)

cat("\nRepeated Prolific IDs\n")
cat(sprintf("  Session files: %d; Prolific IDs: %d; IDs with more than one file: %d\n",
            nrow(sessions), n_distinct(sessions$pid), sum(table(sessions$pid) > 1)))
cat(sprintf("  Later complete sessions dropped by the duplicate rule: %d\n", sum(complete$later_duplicate)))
cat(sprintf("  Completers whose kept session followed an earlier, unfinished one: %d (cases seen before: %s)\n",
            sum(people$sessions_before > 0), paste(people$cases_seen_before[people$sessions_before > 0], collapse = ", ")))
cat(sprintf("  Completers who answered No to the eligibility question in another session: %d (in the first 200: %d)\n",
            sum(people$eligibility_conflict), sum(people$eligibility_conflict & people$in_first_200)))

cat("\nOrder of completion\n")
chk <- people %>% filter(prolific_status %in% paid_ok, !is.na(prolific_completed))
gap <- as.numeric(difftime(chk$prolific_completed, chk$end_utc, units = "secs"))
cat(sprintf("  For the %d people who submitted their completion code, Prolific recorded the submission a median of %.0f seconds after the estimated end (middle 90%%: %.0f to %.0f seconds).\n",
            nrow(chk), median(gap), quantile(gap, .05), quantile(gap, .95)))
alt <- people %>%
  mutate(alt_end = if_else(prolific_status %in% paid_ok & !is.na(prolific_completed),
                           prolific_completed - median(gap), end_utc)) %>%
  arrange(alt_end) %>% mutate(alt_first_200 = row_number() <= FIRST_N)
cat(sprintf("  Ordering by Prolific's submission time where it exists changes the first %d by %d people.\n",
            FIRST_N, sum(alt$in_first_200 != alt$alt_first_200) / 2))
ends <- sort(people$end_utc)
cat(sprintf("  The %dth and the next completion are %.1f minutes apart; %d other completions fall within 5 minutes of the %dth.\n",
            FIRST_N, as.numeric(difftime(ends[FIRST_N + 1], ends[FIRST_N], units = "mins")),
            sum(abs(as.numeric(difftime(ends, ends[FIRST_N], units = "mins"))) <= 5) - 1, FIRST_N))
cat(sprintf("  Completions ran from %s to %s UTC; the first %d ended by %s UTC.\n",
            format(min(ends), "%b %d %H:%M"), format(max(ends), "%b %d %H:%M"),
            FIRST_N, format(ends[FIRST_N], "%b %d %H:%M")))

cat("\nDone. This script read no category choice, slider rating, justification, probe answer or comprehension answer.\n")
