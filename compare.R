# Usage: Rscript compare.R [label ...]   (default: old unclustered fork)
# Summarises results_<label>.csv files per grid cell and writes output/summary.csv.

labels <- commandArgs(trailingOnly = TRUE)
if (length(labels) == 0) labels <- c("old", "unclustered", "fork")

files <- sprintf("output/results_%s.csv", labels)
files <- files[file.exists(files)]
results <- do.call(rbind, lapply(files, read.csv))

cell <- c("power", "rho", "total_sig_k", "av_sig_k_per_a")

# Coverage of the CIs that summary.zcurve() reports: the percentile interval
# widened by .03 (ERR) and .05 (EDR), bounded below by alpha/2 (ERR) and
# alpha (EDR) and above by 1.
results$ERR_covered_adj <- with(results,
  pmax(ERR_lower - .03, .025) <= true_ERR & pmin(ERR_upper + .03, 1) >= true_ERR)
results$EDR_covered_adj <- with(results,
  pmax(EDR_lower - .05, .05) <= true_EDR & pmin(EDR_upper + .05, 1) >= true_EDR)

summarise <- function(r) {
  data.frame(
    r[1, c("label", cell)],
    n = nrow(r),
    n_failed = sum(is.na(r$ERR)),
    ERR_bias = mean(r$ERR - r$true_ERR, na.rm = TRUE),
    ERR_rmse = sqrt(mean((r$ERR - r$true_ERR)^2, na.rm = TRUE)),
    ERR_coverage = mean(r$ERR_covered, na.rm = TRUE),
    ERR_coverage_adj = mean(r$ERR_covered_adj, na.rm = TRUE),
    ERR_width = mean(r$ERR_width, na.rm = TRUE),
    EDR_bias = mean(r$EDR - r$true_EDR, na.rm = TRUE),
    EDR_rmse = sqrt(mean((r$EDR - r$true_EDR)^2, na.rm = TRUE)),
    EDR_coverage = mean(r$EDR_covered, na.rm = TRUE),
    EDR_coverage_adj = mean(r$EDR_covered_adj, na.rm = TRUE),
    EDR_width = mean(r$EDR_width, na.rm = TRUE)
  )
}

groups <- split(results, results[c("label", cell)], drop = TRUE)
summary <- do.call(rbind, lapply(groups, summarise))
summary <- summary[order(summary$power, summary$rho, summary$total_sig_k,
                         summary$av_sig_k_per_a, match(summary$label, labels)), ]
rownames(summary) <- NULL

write.csv(summary, "output/summary.csv", row.names = FALSE)

# Overall picture, one row per label.
overall <- do.call(rbind, lapply(split(results, results$label), function(r) {
  s <- summarise(r)
  s[cell] <- NULL
  s
}))
print(overall[match(labels, overall$label), ], digits = 3, row.names = FALSE)
