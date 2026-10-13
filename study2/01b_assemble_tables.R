# =============================================================================
# Modeling Guilty Minds, Study 2
# Stage 1b: the trial and participant tables
# -----------------------------------------------------------------------------
# Run from the analysis folder, after 01a:   Rscript 01b_assemble_tables.R
#
# Reads the list of people from 01a (data/processed/study2_exclusions.csv) and,
# for everyone in the full sample (all completers who pass the exclusions), the
# whole of their kept session file. People excluded in 01a are not read.
#
# Outputs (data/processed/)
#   study2_trials.csv        one row per case, five per person
#   study2_participants.csv  one row per person
# Both identify people by participant code (P001 = first to complete), not by
# Prolific ID. The full sample is the primary analysis sample; both tables
# also carry first_200, which marks the people among the first 200 completed
# sessions (the sample the registered stopping rule implies), for the
# robustness analysis.
#
# The console output is limited to structural checks. Nothing here summarises
# a category choice, slider rating, justification, probe answer, comprehension
# answer or ranking.
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
  library(jsonlite)
})

RAW_DIR   <- "data/raw"
OUT_DIR   <- "data/processed"
VIGNETTES <- "materials/mensReaVignettes_binary.json"
FEATURES  <- c("source", "package", "inquiry", "payment", "location", "contents")
NAMES     <- c("John", "David", "Andrew", "Robert", "Daniel")

stopifnot(file.exists(file.path(OUT_DIR, "study2_exclusions.csv")), file.exists(VIGNETTES))

people <- read_csv(file.path(OUT_DIR, "study2_exclusions.csv"),
                   col_types = cols(.default = col_character()), progress = FALSE) %>%
  mutate(across(c(included, included_first_200, eligibility_conflict), as.logical),
         across(c(completion_order, sessions_before, cases_seen_before), as.integer),
         across(c(duration_min, prolific_minutes), as.numeric)) %>%
  filter(included)

# -----------------------------------------------------------------------------
# 1. The vignettes: features from the ID, checked against the text
# -----------------------------------------------------------------------------
vign <- fromJSON(VIGNETTES) %>% as_tibble()
stopifnot(nrow(vign) == 64, n_distinct(vign$id) == 64)
id_bits <- function(ids) {
  b <- do.call(rbind, lapply(strsplit(ids, ""), as.integer))
  colnames(b) <- FEATURES
  as_tibble(b)
}
text_bits <- tibble(
  source   = as.integer(str_detect(vign$vignette, "biker")),
  package  = as.integer(str_detect(vign$vignette, "duffel")),
  inquiry  = as.integer(str_detect(vign$vignette, " tells ")),
  payment  = as.integer(str_detect(vign$vignette, fixed("$1000"))),
  location = as.integer(str_detect(vign$vignette, fixed("[MEXICO_LOC]"))),
  contents = as.integer(str_detect(vign$vignette, "fentanyl"))
)
stopifnot(all(id_bits(vign$id) == text_bits))   # ID read left to right = source ... contents

# -----------------------------------------------------------------------------
# 2. Read the kept session files of the full sample
# -----------------------------------------------------------------------------
r <- map_dfr(people$file, function(f) {
  read_csv(file.path(RAW_DIR, f), col_types = cols(.default = col_character()), progress = FALSE) %>%
    mutate(file = f)
}) %>%
  left_join(people %>% select(file, participant), by = "file") %>%
  mutate(task = coalesce(task, ""), trial_index = as.integer(trial_index),
         time_elapsed = as.numeric(time_elapsed)) %>%
  arrange(file, trial_index) %>%
  group_by(file) %>%
  # Time on each page, from the experiment's clock. The choice page ends through a
  # custom button, so jsPsych records no rt for it; its time on the page is the
  # gap since the previous row.
  mutate(page_ms = time_elapsed - lag(time_elapsed)) %>%
  ungroup()
stopifnot(!any(is.na(r$participant)))

per_case <- function(task_name) {
  r %>% filter(task == task_name) %>%
    mutate(vignette_position = as.integer(vignette_position),
           vignette_id = str_pad(vignette_id, 6, pad = "0"))
}

# The case as it was shown: the text inside the vignette box of the slider page.
# (The choice page shows the same text, but jsPsych does not save that page's HTML,
# because the page ends through a custom button.)
shown <- function(stimulus) {
  m <- str_match(stimulus, regex('<div class="vignette-title">Scenario (\\d+)</div>(.*?)</div>', dotall = TRUE))
  tibble(scenario_number = as.integer(m[, 2]), shown_text = str_squish(m[, 3]))
}

choice <- per_case("mental_state_judgment") %>%
  transmute(participant, vignette_position, vignette_id, choice = judgment, choice_page_ms = page_ms)

slider <- per_case("risk_magnitude")
slider <- bind_cols(slider, shown(slider$stimulus)) %>%
  mutate(defendant = str_match(shown_text, "^(\\w+) is an American citizen")[, 2],
         town      = str_match(shown_text, "regularly travels to ([^,]+), (Canada|Mexico),")[, 2],
         country   = str_match(shown_text, "regularly travels to ([^,]+), (Canada|Mexico),")[, 3]) %>%
  transmute(participant, vignette_position, slider_id = vignette_id, scenario_number, shown_text,
            defendant, town, country, slider = as.numeric(response), slider_rt = as.numeric(rt),
            slider_start = as.numeric(slider_start))

justification <- per_case("justification") %>%
  transmute(participant, vignette_position, justification_id = vignette_id,
            justification = map_chr(response, ~ fromJSON(.x)$justification),
            justification_rt = as.numeric(rt))

probe <- per_case("element_probe") %>%
  transmute(participant, vignette_position, probe_id = vignette_id,
            knew, aware, should, probe_rt = as.numeric(rt))

trials <- choice %>%
  left_join(slider,        by = c("participant", "vignette_position")) %>%
  left_join(justification, by = c("participant", "vignette_position")) %>%
  left_join(probe,         by = c("participant", "vignette_position")) %>%
  bind_cols(id_bits(.$vignette_id))

# -----------------------------------------------------------------------------
# 3. Structural checks
# -----------------------------------------------------------------------------
template_shown <- trials %>%
  mutate(t = str_replace_all(shown_text, fixed(paste0(town, ", ", country)), "[LOC]"),
         t = str_replace_all(t, paste0("\\b", defendant, "\\b"), "[NAME]")) %>%
  pull(t)
template_file <- vign$vignette[match(trials$vignette_id, vign$id)] %>%
  str_replace_all("\\[(CANADA|MEXICO)_LOC\\]", "[LOC]") %>%
  str_squish()

per_person <- trials %>% group_by(participant) %>%
  summarise(n = n(), positions = paste(sort(vignette_position), collapse = ""),
            vignettes = n_distinct(vignette_id), names = n_distinct(defendant),
            towns = n_distinct(town), .groups = "drop")

checks <- c(
  "Five cases per person, in positions 1 to 5"          = all(per_person$n == 5 & per_person$positions == "12345"),
  "Five different vignettes per person"                 = all(per_person$vignettes == 5),
  "Five different names and towns per person"           = all(per_person$names == 5 & per_person$towns == 5),
  "Names are the five used in the study"                = all(trials$defendant %in% NAMES),
  "Scenario number on the page equals the position"     = all(trials$scenario_number == trials$vignette_position),
  "Same vignette ID on the choice, slider, justification and probe pages" =
    all(trials$vignette_id == trials$slider_id & trials$vignette_id == trials$justification_id &
          trials$vignette_id == trials$probe_id),
  "Town's country matches the location feature"         = all((trials$country == "Mexico") == (trials$location == 1)),
  "Text shown matches the vignette file for every case" = all(template_shown == template_file),
  "No missing responses in the trial table"             =
    !any(is.na(trials %>% select(choice, slider, justification, knew, aware, should)))
)

trials <- trials %>%
  left_join(people %>% select(participant, first_200 = included_first_200), by = "participant") %>%
  select(participant, first_200, vignette_position, vignette_id, all_of(FEATURES),
         defendant, town, country, choice, choice_page_ms, slider, slider_start, slider_rt,
         justification, justification_rt, knew, aware, should, probe_rt) %>%
  arrange(participant, vignette_position)

# -----------------------------------------------------------------------------
# 4. Participant table
# -----------------------------------------------------------------------------
one_row <- function(task_name, ...) {
  d <- r %>% filter(task == task_name) %>% select(participant, ...)
  stopifnot(!any(duplicated(d$participant)), nrow(d) == nrow(people))
  d
}
demographics <- one_row("demographics", age, gender, gender_selfdescribe, race, race_selfdescribe,
                        education, jury_service, jury_case_type, legal_training, any_legal_training)
comprehension <- one_row("comprehension", comprehension_answer, comprehension_other, comprehension_option_order)
ranking <- one_row("mpc_ranking", ranking = response)
order_row <- r %>% filter(tolower(coalesce(study_completed, "")) == "true") %>%
  group_by(participant) %>% summarise(vignette_order = first(vignette_order), .groups = "drop")
rpm <- r %>% filter(task == "rpm") %>% group_by(participant) %>%
  summarise(rpm_items = n(), rpm_score = sum(tolower(correct) == "true"), .groups = "drop")

participants <- people %>%
  transmute(participant, first_200 = included_first_200, completion_order,
            duration_min, prolific_minutes, eligibility, comprehension_first = comprehension_first == "true",
            sessions_before, cases_seen_before, eligibility_conflict) %>%
  left_join(demographics,  by = "participant") %>%
  left_join(comprehension, by = "participant") %>%
  left_join(ranking,       by = "participant") %>%
  left_join(rpm,           by = "participant") %>%
  left_join(order_row,     by = "participant") %>%
  mutate(any_legal_training = any_legal_training == "true")

shown_order <- trials %>% group_by(participant) %>%
  summarise(ids = paste(vignette_id[order(vignette_position)], collapse = ","), .groups = "drop")
recorded_order <- participants %>%
  transmute(participant, ids = map_chr(vignette_order, ~ paste(fromJSON(.x), collapse = ",")))
checks <- c(checks,
  "Five Raven's items per person" = all(participants$rpm_items == 5),
  "Recorded vignette order matches the cases shown" =
    all(inner_join(shown_order, recorded_order, by = "participant") %>% with(ids.x == ids.y)),
  "Every participant has demographics, comprehension and ranking rows" =
    !any(is.na(participants$age)) & !any(is.na(participants$comprehension_answer)) & !any(is.na(participants$ranking))
)

# -----------------------------------------------------------------------------
# 5. Write and report
# -----------------------------------------------------------------------------
write_csv(trials,       file.path(OUT_DIR, "study2_trials.csv"))
write_csv(participants, file.path(OUT_DIR, "study2_participants.csv"))

cat(sprintf("\nPeople in the full sample (primary): %d; among the first 200 completions: %d\n",
            nrow(participants), sum(participants$first_200)))
cat(sprintf("Trials written: %d (first 200: %d)\n", nrow(trials), sum(trials$first_200)))
cat("\nChecks\n")
for (k in names(checks)) cat(sprintf("  %-75s %s\n", k, ifelse(checks[[k]], "pass", "FAIL")))
if (!all(checks)) stop("A structural check failed; see above.")
cat("\nDone. Nothing above summarises a response.\n")
