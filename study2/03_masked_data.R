# =============================================================================
# Modeling Guilty Minds, Study 2
# Stage 3: masked data for building and testing the analysis script
# -----------------------------------------------------------------------------
# Run from the analysis folder, after Stage 1:   Rscript 03_masked_data.R
#
# The analysis script is written and debugged on two masked data sets, frozen,
# and only then run once on the real data. Neither masked set carries any
# information about a Study 2 outcome.
#
#   data/masked/simulated/  Study 1 participants resampled with replacement
#       (all five of each person's trials, with their choices and slider
#       ratings), with probe answers, justification codes, comprehension
#       answers, rankings and Raven's scores generated under known
#       assumptions: the registered misreading scenario with q = .60. The
#       script should recover these effects (see truth.csv).
#
#   data/masked/structure/  The real Study 2 design and covariates: the 262
#       people in the full sample, their first-200 flag, completion order,
#       order condition, eligibility answer, demographics, and the vignettes,
#       positions, names and towns they saw. Every outcome is replaced: each
#       person's choices and slider ratings are a randomly drawn Study 1
#       participant's five, in random order, and the other outcomes are
#       generated with no misreading (q = 0). This
#       set checks that the script runs on the real design and formats, and
#       it exercises the branch of the plan for an unsupported H1.
#
# Both sets also get simulated justification codes for Study 1 and Study 2
# (justification_codes.csv) and placeholder check-set kappas
# (check_set_results.csv), because the coding protocol has not run yet. The
# real files will have the same columns.
#
# The structure set reads the Stage 1 trial table only for its design columns
# (participant, position, vignette, features, name, town); the outcome columns
# are dropped as the file is read.
# =============================================================================

suppressPackageStartupMessages({
  library(dplyr)
  library(readr)
  library(tidyr)
  library(purrr)
  library(stringr)
  library(jsonlite)
})

set.seed(20261008)
OUT <- "data/masked"
FEATURES <- c("source", "package", "inquiry", "payment", "location", "contents")
CATS <- c("Blamelessness", "Negligence", "Recklessness", "Knowledge")
CODES <- c("Knew", "Suspected", "Unaware, at fault", "Unaware, no fault",
           "Act or situation only", "Evidentiary", "Uncodable")
NAMES <- c("John", "David", "Andrew", "Robert", "Daniel")
CANADA <- c("Richmond", "Winnipeg", "Thunder Bay", "Windsor", "Kingston")
MEXICO <- c("Nogales", "Reynosa", "Agua Prieta", "Nuevo Laredo", "Mexicali")
Q_SIMULATED <- 0.60   # registered misreading scenario used for the simulated set

# -----------------------------------------------------------------------------
# Study 1 trials (the analysed 1,060)
# -----------------------------------------------------------------------------
s1 <- read_csv("data/study1_trials.csv", col_types = cols(.default = col_character()), progress = FALSE)
keep <- s1 %>% count(session_id) %>% filter(n == 5) %>% pull(session_id)
s1 <- s1 %>%
  filter(session_id %in% keep) %>%
  transmute(session_id,
            vignette_position = as.integer(vignette_position),
            vignette_id = str_pad(vignette_id, 6, pad = "0"),
            choice = judgment,
            slider = as.numeric(slider_value))
stopifnot(nrow(s1) == 1060, all(s1$choice %in% CATS))

bits <- function(ids) {
  b <- do.call(rbind, lapply(strsplit(ids, ""), as.integer))
  colnames(b) <- FEATURES
  as_tibble(b)
}

# -----------------------------------------------------------------------------
# Generators for everything Study 2 adds
# -----------------------------------------------------------------------------
yn <- function(p) ifelse(runif(length(p)) < p, "Yes", "No")

probe_answers <- function(choice, slider, misread) {
  s <- slider
  p_knew <- case_when(
    choice == "Knowledge"     ~ ifelse(misread, 0.05, 0.90),
    choice == "Recklessness"  ~ plogis(-3.5 + 0.035 * s),
    choice == "Negligence"    ~ plogis(-4.5 + 0.030 * s),
    TRUE                      ~ 0.02)
  knew  <- yn(p_knew)
  aware <- ifelse(knew == "Yes", yn(rep(0.95, length(s))), yn(plogis(-2 + 0.06 * s)))
  should <- ifelse(aware == "Yes", yn(rep(0.90, length(s))), yn(plogis(-1 + 0.04 * s)))
  tibble(knew, aware, should)
}

code_probs <- list(
  Knowledge_misread = c(.15, .12, .07, .13, .35, .10, .08),
  Knowledge         = c(.55, .12, .05, .03, .10, .07, .08),
  Recklessness      = c(.08, .45, .12, .10, .10, .07, .08),
  Negligence        = c(.03, .12, .45, .17, .08, .07, .08),
  Blamelessness     = c(.02, .05, .10, .55, .05, .15, .08)
)
stopifnot(all(abs(sapply(code_probs, sum) - 1) < 1e-9))
draw_codes <- function(choice, misread) {
  key <- ifelse(choice == "Knowledge" & misread, "Knowledge_misread", choice)
  vapply(key, function(k) sample(CODES, 1, prob = code_probs[[k]]), character(1), USE.NAMES = FALSE)
}
nli_from_code <- function(code) {
  denied <- code %in% c("Unaware, at fault", "Unaware, no fault")
  as.integer(ifelse(runif(length(code)) < 0.85, denied, !denied))
}

person_extras <- function(n, any_misread) {
  comp <- vapply(any_misread, function(m) sample(c("a", "b", "c", "d", "e"), 1,
                 prob = if (m) c(.55, .25, .08, .07, .05) else c(.25, .45, .12, .12, .06)), character(1))
  ranking <- vapply(seq_len(n), function(i) {
    r <- if (runif(1) < 0.45) rev(CATS) else sample(CATS)
    as.character(toJSON(r))
  }, character(1))
  tibble(
    comprehension_answer = comp,
    comprehension_other = ifelse(comp == "e", "Simulated text", NA_character_),
    comprehension_option_order = vapply(seq_len(n), function(i) paste(sample(c("a", "b", "c", "d")), collapse = ""), character(1)),
    ranking = ranking,
    rpm_items = 5L,
    rpm_score = rbinom(n, 5, 0.55)
  )
}

fake_demographics <- function(n) {
  jury <- sample(c("Yes", "No"), n, replace = TRUE, prob = c(.25, .75))
  legal <- sample(c("None", "Law courses in college or elsewhere", "Work as a paralegal or in another legal setting"),
                  n, replace = TRUE, prob = c(.85, .11, .04))
  tibble(
    age = sample(18:80, n, replace = TRUE),
    gender = sample(c("Woman", "Man", "Non-binary", "Prefer not to say"), n, replace = TRUE, prob = c(.49, .48, .02, .01)),
    gender_selfdescribe = NA_character_,
    race = sample(c("White", "Black or African American", "Asian", "Hispanic or Latino", "White; Hispanic or Latino"),
                  n, replace = TRUE, prob = c(.6, .13, .07, .12, .08)),
    race_selfdescribe = NA_character_,
    education = sample(c("High school diploma or equivalent", "Some college, no degree", "Associate degree",
                         "Bachelor's degree", "Master's degree"), n, replace = TRUE),
    jury_service = jury,
    jury_case_type = ifelse(jury == "Yes", sample(c("Criminal", "Civil", "Both", "Not sure"), n, replace = TRUE), NA_character_),
    legal_training = legal,
    any_legal_training = legal != "None"
  )
}

add_trial_extras <- function(d) {
  d %>% mutate(
    choice_page_ms   = round(rlnorm(n(), log(40000), 0.5)),
    slider_start     = 50,
    slider_rt        = round(rlnorm(n(), log(9000), 0.5)),
    justification    = "Simulated justification text.",
    justification_rt = round(rlnorm(n(), log(45000), 0.6)),
    probe_rt         = round(rlnorm(n(), log(25000), 0.5))
  )
}

# Study 1 codes (simulated for now; the coding protocol supplies the real ones)
s1_codes <- function() {
  misread <- s1$choice == "Knowledge" & s1$slider < 50 & runif(nrow(s1)) < Q_SIMULATED
  code <- draw_codes(s1$choice, misread)
  tibble(study = 1L, participant = s1$session_id, vignette_position = s1$vignette_position,
         code = code, nli_denied = nli_from_code(code))
}

check_set_placeholder <- tibble(
  measure = c("knowledge_stated", "awareness_denied", "seven_codes"),
  scope   = c("60 Knowledge items", "all 100 items", "all 100 items"),
  n_items = c(60L, 100L, 100L),
  kappa   = c(0.78, 0.74, 0.66),
  note    = "Placeholder for testing; the real values come from the coding protocol"
)

trial_columns <- c("participant", "first_200", "vignette_position", "vignette_id", FEATURES,
                   "defendant", "town", "country", "choice", "choice_page_ms", "slider", "slider_start",
                   "slider_rt", "justification", "justification_rt", "knew", "aware", "should", "probe_rt")

write_set <- function(dir, trials, participants, codes, flow) {
  dir.create(dir, recursive = TRUE, showWarnings = FALSE)
  write_csv(trials %>% select(all_of(trial_columns)), file.path(dir, "study2_trials.csv"))
  write_csv(participants, file.path(dir, "study2_participants.csv"))
  write_csv(codes, file.path(dir, "justification_codes.csv"))
  write_csv(check_set_placeholder, file.path(dir, "check_set_results.csv"))
  write_csv(flow, file.path(dir, "stage1_flow.csv"))
}

# =============================================================================
# A. Simulated set: Study 1 participants resampled, known effects
# =============================================================================
N <- 262; N_FIRST <- 193
pick <- sample(unique(s1$session_id), N, replace = TRUE)
simA <- map_dfr(seq_len(N), function(i) {
  s1 %>% filter(session_id == pick[i]) %>% mutate(participant = sprintf("P%03d", i))
}) %>%
  arrange(participant, vignette_position) %>%
  group_by(participant) %>%
  mutate(defendant = sample(NAMES),
         country = ifelse(substr(vignette_id, 5, 5) == "1", "Mexico", "Canada"),
         town = ifelse(country == "Mexico", sample(MEXICO)[row_number()], sample(CANADA)[row_number()])) %>%
  ungroup() %>%
  mutate(misread = choice == "Knowledge" & slider < 50 & runif(n()) < Q_SIMULATED)
simA <- bind_cols(simA, bits(simA$vignette_id), probe_answers(simA$choice, simA$slider, simA$misread)) %>%
  add_trial_extras() %>%
  mutate(first_200 = as.integer(sub("P", "", participant)) <= N_FIRST)

peopleA <- simA %>% group_by(participant) %>%
  summarise(any_misread = any(misread),
            vignette_order = as.character(toJSON(vignette_id[order(vignette_position)])), .groups = "drop")
partA <- tibble(
  participant = peopleA$participant,
  first_200 = as.integer(sub("P", "", peopleA$participant)) <= N_FIRST,
  completion_order = as.integer(sub("P", "", peopleA$participant)),
  duration_min = round(rlnorm(N, log(16), 0.35), 2),
  prolific_minutes = round(rlnorm(N, log(16.5), 0.35), 2),
  eligibility = sample(c("Yes", "Not sure"), N, replace = TRUE, prob = c(.985, .015)),
  comprehension_first = runif(N) < 0.5,
  sessions_before = 0L, cases_seen_before = 0L, eligibility_conflict = FALSE
) %>%
  bind_cols(fake_demographics(N)) %>%
  bind_cols(person_extras(N, peopleA$any_misread)) %>%
  mutate(vignette_order = peopleA$vignette_order)

codesA <- bind_rows(
  s1_codes(),
  tibble(study = 2L, participant = simA$participant, vignette_position = simA$vignette_position,
         code = draw_codes(simA$choice, simA$misread)) %>% mutate(nli_denied = nli_from_code(code))
)

flowA <- tibble(step = c("Simulated data: no real flow", "Full sample (primary): everyone who completed", "  analysed",
                         "Robustness sample: the first 200 to complete", "  analysed"),
                n = c(NA, N, N, 200, N_FIRST))
write_set(file.path(OUT, "simulated"), simA, partA, codesA, flowA)

truth <- simA %>% filter(choice == "Knowledge") %>%
  mutate(low = slider < 50, unendorsed = knew == "No") %>%
  group_by(low) %>% summarise(trials = n(), unendorsed_rate = mean(unendorsed), .groups = "drop")
write_csv(truth, file.path(OUT, "simulated", "truth.csv"))
writeLines(c(
  "Simulated set: Study 1 participants resampled (N = 262), probe answers and codes generated as in the registered power analysis.",
  sprintf("Misreading scenario q = %.2f: a low-slider Knowledge choice is misread with probability q.", Q_SIMULATED),
  "KNEW Yes: .05 for misread Knowledge choices, .90 for other Knowledge choices; non-Knowledge trials as in the V1 power script.",
  "Expected: H1 positive and significant; H2 negative (Knew code .15 when misread, .55 otherwise); V1 positive (about 11 points).",
  "Comprehension answer (a) is more likely for people with a misread trial, so S3 should show an effect."
), file.path(OUT, "simulated", "README.txt"))

# =============================================================================
# B. Structure set: the real Study 2 design, outcomes replaced
# =============================================================================
design_cols <- c("participant", "first_200", "vignette_position", "vignette_id", FEATURES,
                 "defendant", "town", "country")
real_design <- read_csv("data/processed/study2_trials.csv",
                        col_types = cols(.default = col_character()),
                        col_select = all_of(design_cols), progress = FALSE) %>%
  mutate(vignette_position = as.integer(vignette_position),
         first_200 = as.logical(first_200),
         across(all_of(FEATURES), as.integer))
real_people <- read_csv("data/processed/study2_participants.csv",
                        col_types = cols(.default = col_character()),
                        col_select = c(participant, first_200, completion_order, duration_min, prolific_minutes,
                                       eligibility, comprehension_first, sessions_before, cases_seen_before,
                                       eligibility_conflict, age, gender, gender_selfdescribe, race,
                                       race_selfdescribe, education, jury_service, jury_case_type,
                                       legal_training, any_legal_training, vignette_order),
                        progress = FALSE)

# Each Study 2 participant gets a randomly drawn Study 1 participant's five (choice,
# slider) pairs, in random order, so the outcomes keep a realistic amount of
# between-person variation but carry nothing from Study 2.
s1_people <- split(s1[, c("choice", "slider")], s1$session_id)
donor <- sample(names(s1_people), n_distinct(real_design$participant), replace = TRUE)
names(donor) <- sort(unique(real_design$participant))
simB <- real_design %>%
  arrange(participant, vignette_position) %>%
  group_by(participant) %>%
  group_modify(~ bind_cols(.x, s1_people[[donor[[.y$participant]]]][sample(5), ])) %>%
  ungroup() %>%
  mutate(misread = FALSE)
simB <- bind_cols(simB, probe_answers(simB$choice, simB$slider, simB$misread)) %>%
  add_trial_extras()

partB <- real_people %>%
  bind_cols(person_extras(nrow(real_people), rep(FALSE, nrow(real_people))))
codesB <- bind_rows(
  s1_codes(),
  tibble(study = 2L, participant = simB$participant, vignette_position = simB$vignette_position,
         code = draw_codes(simB$choice, simB$misread)) %>% mutate(nli_denied = nli_from_code(code))
)
flowB <- read_csv("output/stage1_flow.csv", show_col_types = FALSE)
write_set(file.path(OUT, "structure"), simB, partB, codesB, flowB)
writeLines(c(
  "Structure set: the real Study 2 design and covariates (262 people), every outcome replaced.",
  "Choice and slider: a random Study 1 participant's five trials for each Study 2 participant, in random order. Probe answers and codes: no misreading (q = 0).",
  "Expected: H1 not significant; the 15-point rule for an unsupported H1 is exercised."
), file.path(OUT, "structure", "README.txt"))

cat(sprintf("Simulated set: %d people, %d trials; structure set: %d people, %d trials\n",
            nrow(partA), nrow(simA), nrow(partB), nrow(simB)))
cat("Simulated truth (Knowledge trials):\n"); print(as.data.frame(truth), row.names = FALSE)
