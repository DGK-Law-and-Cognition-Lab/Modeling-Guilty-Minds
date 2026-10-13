# =============================================================================
# Modeling Guilty Minds, Study 2: functions used by MPC_Study2_Analysis.Rmd
# -----------------------------------------------------------------------------
# Each function implements one registered rule. The comments quote or
# paraphrase the preregistration ("Confirmatory analyses", "Replication
# analyses", "Secondary and exploratory analyses").
# =============================================================================

# ---- Formatting (carried over from the Study 1 script) ----------------------
fmt_p <- function(p) {
  ifelse(is.na(p), NA_character_,
    ifelse(p < .001, "< .001",
           paste0("= ", sub("^0", "", formatC(p, format = "f", digits = 3)))))
}
fmt_num <- function(x, digits = 2) ifelse(is.na(x), NA_character_, formatC(round(x, digits), format = "f", digits = digits))
fmt_ci  <- function(lo, hi, digits = 2) paste0("[", fmt_num(lo, digits), ", ", fmt_num(hi, digits), "]")
# Odds ratios: very large or very small bootstrap limits (from resamples with
# complete separation) are shown as bounds rather than as long numbers.
fmt_or1 <- function(x) ifelse(is.na(x), NA_character_, ifelse(x > 1000, "> 1000", ifelse(x < 0.001, "< 0.001", fmt_num(x, 2))))
fmt_or_ci <- function(lo, hi) paste0("[", fmt_or1(lo), ", ", fmt_or1(hi), "]")
fmt_pct <- function(x, digits = 1) fmt_num(100 * x, digits)

compute_deff <- function(icc, k = 5) 1 + (k - 1) * icc
compute_icc <- function(outcome, cluster_id) {
  fit <- aov(outcome ~ factor(cluster_id))
  ms <- summary(fit)[[1]][["Mean Sq"]]
  k <- mean(table(cluster_id))
  max((ms[1] - ms[2]) / (ms[1] + (k - 1) * ms[2]), 0)
}

# ---- Participant-cluster bootstrap ------------------------------------------
# "participant-cluster bootstrap CIs (5,000 resamples of participants,
# percentile intervals)". Each replicate draws participants with replacement.
# For statistics that are ratios of sums (rates, means, differences of these),
# a replicate is a vector of resampling counts per participant, which gives the
# same answer as rebuilding the data set and is much faster.
boot_counts <- function(n_clusters, B = 5000, seed) {
  set.seed(seed)
  t(vapply(seq_len(B), function(b) tabulate(sample.int(n_clusters, n_clusters, replace = TRUE), n_clusters),
           integer(n_clusters)))
}

# Registered bootstrap p value: 2 * (1 + k) / (B + 1), capped at 1, where k is
# the smaller of the number of bootstrap estimates at or below zero and the
# number at or above zero. B counts the valid replicates (5,000 when none is
# undefined).
boot_p <- function(bs) {
  bs <- bs[is.finite(bs)]
  k <- min(sum(bs <= 0), sum(bs >= 0))
  min(1, 2 * (1 + k) / (length(bs) + 1))
}
pct_ci <- function(bs) unname(quantile(bs[is.finite(bs)], c(.025, .975)))

# Per-participant sums of a numerator and a denominator, in a fixed participant order.
cluster_sums <- function(data, value, include, pids) {
  v <- tapply(ifelse(include, value, 0), factor(data$pid, levels = pids), sum)
  v[is.na(v)] <- 0
  as.numeric(v)
}

# Rate (or mean) within a subset, with its bootstrap distribution.
# value: numeric per row (0/1 for a rate, the slider for a mean); include: logical per row.
boot_ratio <- function(data, value, include, W, pids) {
  num <- cluster_sums(data, value, include, pids)
  den <- cluster_sums(data, rep(1, nrow(data)), include, pids)
  list(est = sum(num) / sum(den), boot = as.numeric((W %*% num) / (W %*% den)), n = sum(den))
}

# ---- Logistic mixed model with the registered fallback rule -----------------
# "Logistic mixed models use lme4::glmer (binomial, logit link, bobyqa
# optimizer)." "A model fails if it returns an error or a convergence warning
# under bobyqa and again under Nelder-Mead. A singular fit ... is not a
# failure, and we will report it." As in the registered power simulation, any
# warning raised by glmer counts as a convergence warning; the singular-fit
# notice is a message in lme4, not a warning, and is recorded separately.
fit_glmer_rule <- function(formula, data) {
  attempt <- function(opt) {
    warns <- character(0)
    m <- tryCatch(
      withCallingHandlers(
        suppressMessages(lme4::glmer(formula, data = data, family = binomial,
                                     control = lme4::glmerControl(optimizer = opt))),
        warning = function(w) { warns <<- c(warns, conditionMessage(w)); invokeRestart("muffleWarning") }),
      error = function(e) e)
    if (inherits(m, "error")) return(list(model = NULL, ok = FALSE, optimizer = opt, problem = conditionMessage(m)))
    list(model = m, ok = length(warns) == 0, optimizer = opt,
         problem = if (length(warns)) paste(unique(warns), collapse = "; ") else NA_character_)
  }
  a <- attempt("bobyqa")
  if (a$ok) return(c(a, list(status = "converged (bobyqa)", singular = lme4::isSingular(a$model))))
  b <- attempt("Nelder_Mead")
  if (b$ok) return(c(b, list(status = paste0("converged (Nelder-Mead; bobyqa: ", a$problem, ")"),
                             singular = lme4::isSingular(b$model))))
  list(model = NULL, ok = FALSE, optimizer = NA, singular = NA,
       status = paste0("failed (bobyqa: ", a$problem, "; Nelder-Mead: ", b$problem, ")"))
}

wald_row <- function(model, term) {
  cf <- summary(model)$coefficients
  b <- cf[term, "Estimate"]; se <- cf[term, "Std. Error"]
  list(b = b, se = se, z = cf[term, "z value"], p = cf[term, "Pr(>|z|)"],
       or = exp(b), or_lo = exp(b - qnorm(.975) * se), or_hi = exp(b + qnorm(.975) * se))
}

cells_ok <- function(y, x) {
  tab <- table(factor(y, levels = c(0, 1)), factor(x, levels = c(0, 1)))
  list(ok = all(tab >= 5), table = tab)
}

# ---- H1 ----------------------------------------------------------------------
# Data: all Knowledge trials. glmer(unendorsed ~ low_slider + comprehension_first
# + (1 | pid)). Fallback: participant-cluster bootstrap of the difference in raw
# rates. Effect sizes: odds ratio and the raw unendorsement rate in each group,
# with participant-cluster bootstrap CIs.
run_h1 <- function(k, B = 5000, seed = 101, extra_re = NULL, covariate = TRUE, boot_or = FALSE) {
  pids <- sort(unique(as.character(k$pid)))
  W <- boot_counts(length(pids), B, seed)
  low  <- boot_ratio(k, k$unendorsed, k$low_slider == 1, W, pids)
  high <- boot_ratio(k, k$unendorsed, k$low_slider == 0, W, pids)
  all  <- boot_ratio(k, k$unendorsed, rep(TRUE, nrow(k)), W, pids)
  diff_bs <- low$boot - high$boot
  rhs <- c("low_slider", if (covariate) "comprehension_first", "(1 | pid)", extra_re)
  f <- as.formula(paste("unendorsed ~", paste(rhs, collapse = " + ")))
  cc <- cells_ok(k$unendorsed, k$low_slider)
  fit <- if (cc$ok) fit_glmer_rule(f, k) else list(model = NULL, ok = FALSE, singular = NA,
                                                   status = "not fitted: a cell has fewer than five trials")
  use_fallback <- is.null(fit$model)
  w <- if (!use_fallback) wald_row(fit$model, "low_slider") else NULL
  or_boot <- if (!use_fallback && boot_or) boot_glmer_or(f, k, "low_slider", W, pids) else NULL
  list(or_boot_ci = or_boot$ci, or_boot_failed = or_boot$failed,
    n_trials = nrow(k), n_people = length(pids), cells = cc$table, fallback = use_fallback,
    model_status = fit$status, singular = fit$singular, formula = deparse(f),
    or = w$or, or_lo = w$or_lo, or_hi = w$or_hi, b = w$b, z = w$z, p_model = w$p,
    rate_low = low$est, rate_low_ci = pct_ci(low$boot), n_low = low$n,
    rate_high = high$est, rate_high_ci = pct_ci(high$boot), n_high = high$n,
    rate_all = all$est, rate_all_ci = pct_ci(all$boot),
    diff = low$est - high$est, diff_ci = pct_ci(diff_bs), p_boot = boot_p(diff_bs),
    p = if (use_fallback) boot_p(diff_bs) else w$p,
    estimate_positive = if (use_fallback) (low$est - high$est) > 0 else w$b > 0
  )
}

# ---- H2 ----------------------------------------------------------------------
# Data: Knowledge trials with slider below 50 and a codable justification.
# glmer(unendorsed ~ knowledge_stated + slider_c + comprehension_first + (1 | pid)),
# slider_c = (slider - 25) / 10. Fallback: ordinary logistic regression with the
# same fixed effects, focal coefficient bootstrapped by participant.
run_h2 <- function(k2, B = 5000, seed = 202, extra_re = NULL, covariate = TRUE, boot_or = FALSE) {
  pids <- sort(unique(as.character(k2$pid)))
  W <- boot_counts(length(pids), B, seed)
  stated   <- boot_ratio(k2, k2$unendorsed, k2$knowledge_stated == 1, W, pids)
  unstated <- boot_ratio(k2, k2$unendorsed, k2$knowledge_stated == 0, W, pids)
  fixed <- c("knowledge_stated", "slider_c", if (covariate) "comprehension_first")
  f <- as.formula(paste("unendorsed ~", paste(c(fixed, "(1 | pid)", extra_re), collapse = " + ")))
  cc <- cells_ok(k2$unendorsed, k2$knowledge_stated)
  fit <- if (cc$ok) fit_glmer_rule(f, k2) else list(model = NULL, ok = FALSE, singular = NA,
                                                    status = "not fitted: a cell has fewer than five trials")
  use_fallback <- is.null(fit$model)
  out <- list(n_trials = nrow(k2), n_people = length(pids), cells = cc$table, fallback = use_fallback,
              model_status = fit$status, singular = fit$singular, formula = deparse(f),
              rate_stated = stated$est, rate_stated_ci = pct_ci(stated$boot), n_stated = stated$n,
              rate_unstated = unstated$est, rate_unstated_ci = pct_ci(unstated$boot), n_unstated = unstated$n)
  if (!use_fallback) {
    w <- wald_row(fit$model, "knowledge_stated")
    or_boot <- if (boot_or) boot_glmer_or(f, k2, "knowledge_stated", W, pids) else NULL
    return(c(out, list(or = w$or, or_lo = w$or_lo, or_hi = w$or_hi, b = w$b, z = w$z, p = w$p,
                       estimate_negative = w$b < 0, or_boot_ci = or_boot$ci, or_boot_failed = or_boot$failed)))
  }
  # Fallback: glm, focal coefficient bootstrapped by participant (rows rebuilt per replicate).
  gf <- as.formula(paste("unendorsed ~", paste(fixed, collapse = " + ")))
  coef_of <- function(d) {
    if (length(unique(d$knowledge_stated)) < 2 || length(unique(d$unendorsed)) < 2) return(NA_real_)
    unname(coef(suppressWarnings(glm(gf, data = d, family = binomial)))["knowledge_stated"])
  }
  idx <- split(seq_len(nrow(k2)), factor(as.character(k2$pid), levels = pids))
  est <- coef_of(k2)
  bs <- apply(W, 1, function(w) coef_of(k2[unlist(rep(idx, w), use.names = FALSE), , drop = FALSE]))
  c(out, list(or = exp(est), or_lo = exp(pct_ci(bs)[1]), or_hi = exp(pct_ci(bs)[2]), b = est, z = NA,
              p = boot_p(bs), estimate_negative = est < 0, boot_valid = sum(is.finite(bs))))
}

# ---- V1 ----------------------------------------------------------------------
# Data: original choice Recklessness or Negligence, probe-defined category
# Knowledge or Recklessness. lmer(slider ~ probe_knowledge + (1 | pid)),
# Satterthwaite df; d = coefficient / SD of slider in the trials analysed.
run_v1 <- function(v, extra_re = NULL) {
  f <- as.formula(paste("slider ~ probe_knowledge + (1 | pid)", if (!is.null(extra_re)) paste("+", extra_re)))
  m <- suppressMessages(lmerTest::lmer(f, data = v))
  cf <- summary(m)$coefficients["probe_knowledge", ]
  crit <- qt(.975, df = cf["df"])
  list(n_trials = nrow(v), n_people = length(unique(v$pid)), n_probe_k = sum(v$probe_knowledge == 1),
       b = unname(cf["Estimate"]), se = unname(cf["Std. Error"]), df = unname(cf["df"]),
       t = unname(cf["t value"]), p = unname(cf["Pr(>|t|)"]),
       ci = unname(c(cf["Estimate"] - crit * cf["Std. Error"], cf["Estimate"] + crit * cf["Std. Error"])),
       d = unname(cf["Estimate"]) / sd(v$slider), singular = lme4::isSingular(m), formula = deparse(f))
}

# ---- GEE versions (sensitivity analysis 5) -----------------------------------
# "replace the mixed models with generalized estimating equations (exchangeable
# working correlation, clustered by participant)".
run_gee <- function(formula, data, family, term) {
  d <- data[order(data$pid), , drop = FALSE]
  d$pid_id <- as.integer(factor(d$pid))
  m <- geepack::geeglm(formula, id = pid_id, data = d, family = family, corstr = "exchangeable")
  cf <- summary(m)$coefficients
  b <- cf[term, "Estimate"]; se <- cf[term, "Std.err"]
  list(b = b, se = se, p = cf[term, "Pr(>|W|)"], lo = b - qnorm(.975) * se, hi = b + qnorm(.975) * se,
       n_trials = nrow(d), n_people = length(unique(d$pid)))
}

# ---- Ranking: Kendall's tau against the MPC order ----------------------------
MPC_ORDER <- c("Knowledge", "Recklessness", "Negligence", "Blamelessness")
ranking_tau <- function(json) {
  vapply(json, function(j) {
    r <- tryCatch(jsonlite::fromJSON(j), error = function(e) NULL)
    if (is.null(r) || length(r) != 4 || !setequal(r, MPC_ORDER)) return(NA_real_)
    suppressWarnings(cor(match(MPC_ORDER, r), 1:4, method = "kendall"))
  }, numeric(1), USE.NAMES = FALSE)
}

# ---- Agreement statistics -----------------------------------------------------
cohen_kappa <- function(a, b) {
  lv <- union(unique(a), unique(b))
  tab <- table(factor(a, lv), factor(b, lv))
  n <- sum(tab); po <- sum(diag(tab)) / n
  pe <- sum(rowSums(tab) * colSums(tab)) / n^2
  (po - pe) / (1 - pe)
}
weighted_kappa_quadratic <- function(a, b, levels) {
  tab <- table(factor(a, levels), factor(b, levels)); k <- length(levels)
  w <- 1 - outer(seq_len(k), seq_len(k), function(i, j) (i - j)^2) / (k - 1)^2
  p <- tab / sum(tab)
  po <- sum(w * p); pe <- sum(w * outer(rowSums(p), colSums(p)))
  (po - pe) / (1 - pe)
}
binary_agreement <- function(code_flag, probe_flag) {
  tp <- sum(code_flag & probe_flag); fn <- sum(!code_flag & probe_flag)
  tn <- sum(!code_flag & !probe_flag); fp <- sum(code_flag & !probe_flag)
  tibble::tibble(n = length(code_flag), sensitivity = tp / (tp + fn), specificity = tn / (tn + fp),
                 kappa = cohen_kappa(code_flag, probe_flag))
}

# ---- Probe-defined category ----------------------------------------------------
# Knowledge: KNEW Yes. Recklessness: KNEW No, AWARE Yes. Negligence: KNEW No,
# AWARE No, SHOULD Yes. Blamelessness: all three No.
probe_category <- function(knew, aware, should) {
  dplyr::case_when(knew == "Yes" ~ "Knowledge",
                   aware == "Yes" ~ "Recklessness",
                   should == "Yes" ~ "Negligence",
                   TRUE ~ "Blamelessness")
}

# ---- Cumulative link mixed models --------------------------------------------
# ordinal::clmm as registered. If the fit returns standard errors that are not
# numbers (which happens when the participant variance sits at its boundary of
# zero), it is refitted once with the nlminb optimizer; the model is unchanged.
# Every refit or remaining problem is recorded in model_notes and listed at the
# end of the report.
model_notes <- new.env()
model_notes$rows <- list()
note_model <- function(label, note) {
  model_notes$rows[[length(model_notes$rows) + 1]] <- tibble::tibble(Model = label, Note = note)
}
fit_clmm <- function(formula, data, label = deparse(formula)) {
  bad <- function(m) any(!is.finite(summary(m)$coefficients[, "Std. Error"]))
  m <- ordinal::clmm(formula, data = data)
  if (!bad(m)) return(m)
  m2 <- tryCatch(ordinal::clmm(formula, data = data, control = ordinal::clmm.control(method = "nlminb")),
                 error = function(e) NULL)
  if (!is.null(m2) && !bad(m2)) { note_model(label, "refitted with nlminb after non-finite standard errors"); return(m2) }
  note_model(label, "standard errors not available: participant variance at its boundary")
  m
}

# ---- Participant-cluster bootstrap CI for a mixed-model odds ratio -----------
# "For H1 and H2, these are the model's odds ratio and the raw unendorsement
# rate in each group, with participant-cluster bootstrap CIs (5,000 resamples of
# participants, percentile intervals)." Each replicate refits the same model to
# the resampled participants; a participant drawn twice enters as two clusters.
# Refits that fail under both optimizers are dropped and counted.
boot_glmer_or <- function(formula, data, term, W, pids) {
  idx <- split(seq_len(nrow(data)), factor(as.character(data$pid), levels = pids))
  one <- function(w) {
    sel <- which(w > 0)
    rows <- unlist(lapply(sel, function(i) rep(list(idx[[i]]), w[i])), recursive = FALSE)
    dd <- data[unlist(rows), , drop = FALSE]
    dd$pid <- factor(rep(seq_along(rows), lengths(rows)))
    if (length(unique(dd[[term]])) < 2 || length(unique(dd$unendorsed)) < 2) return(NA_real_)
    f <- fit_glmer_rule(formula, dd)
    if (is.null(f$model)) NA_real_ else unname(lme4::fixef(f$model)[term])
  }
  bs <- apply(W, 1, one)
  list(ci = exp(pct_ci(bs)), failed = sum(!is.finite(bs)), B = length(bs))
}

# ---- Freeze checksum ------------------------------------------------------------
# The freeze records a checksum of each analysis file. The one line that chooses
# the data (data_source in the Rmd header) is left out, so switching it to "real"
# does not count as an edit. Line endings are normalised, so the checksum is the
# same on a Mac, Windows or Linux copy of the same file.
freeze_md5 <- function(path) {
  x <- readLines(path, warn = FALSE)
  x <- x[!grepl("^\\s*data_source\\s*:", x)]
  tmp <- tempfile(); on.exit(unlink(tmp))
  writeLines(x, tmp)
  unname(tools::md5sum(tmp))
}
