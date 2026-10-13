# =============================================================================
# Modeling Guilty Minds, Study 2
# Stage 4: freeze the analysis script before the one run on the real data
# -----------------------------------------------------------------------------
# Run from the analysis folder, once, when the script is final:
#   Rscript 04_freeze.R
#
# It records an MD5 checksum of the analysis script and its functions file in
# protocol/analysis_freeze.txt, with the time. MPC_Study2_Analysis.Rmd reads the
# real data only when both files still match these checksums, so any later edit
# stops the real run until it is refrozen, and a refreeze is visible in this
# file's history. The checksum ignores the data_source line in the Rmd header, so
# setting data_source: "real" there is allowed. The freeze also requires the
# justification codes and the check-set results, because the script runs once,
# after the coding is done. Post the two files and this record (OSF, or a dated commit)
# before running:
#
#   Rscript -e "rmarkdown::render('MPC_Study2_Analysis.Rmd',
#               params = list(data_source = 'real'),
#               output_file = 'output/MPC_Study2_Analysis_real.html')"
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

files  <- c("MPC_Study2_Analysis.Rmd", "R/study2_functions.R")
record <- "protocol/analysis_freeze.txt"
stopifnot(all(file.exists(files)))
dir.create("protocol", showWarnings = FALSE)
if (file.exists(record))
  stop("The script is already frozen. Refreezing after the real run would have to be reported as a deviation; ",
       "delete ", record, " by hand only if that is what you mean to do.")
source("R/study2_functions.R")   # for freeze_md5(), which ignores the data_source line
stopifnot(file.exists("data/processed/justification_codes.csv"), file.exists("protocol/check_set_results.csv"))
out <- data.frame(file = files, md5 = vapply(files, freeze_md5, character(1), USE.NAMES = FALSE),
                  frozen_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S %Z"))
write.csv(out, record, row.names = FALSE)
print(out, row.names = FALSE)
cat("\nFrozen. The real run is now allowed for these exact files.\n")
