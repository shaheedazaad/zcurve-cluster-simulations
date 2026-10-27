# Usage: Rscript fit.R <lib> <method> <label> [n_datasets]
#   lib:        library folder holding the zcurve build to test (e.g. ../lib/old)
#   method:     "clustered" (zcurve_clustered) or "unclustered" (zcurve, ignoring ids)
#   label:      name used for the output files
#   n_datasets: optional, fit only the first n datasets (for quick checks)

args <- commandArgs(trailingOnly = TRUE)
stopifnot(length(args) >= 3)
n_boot <- 200

lib <- normalizePath(args[1], mustWork = TRUE)
method <- match.arg(args[2], c("clustered", "unclustered"))
label <- args[3]

# Must come before any zcurve:: call so the requested build is loaded.
.libPaths(c(lib, .libPaths()))
# Parallel workers are fresh R sessions; R_LIBS makes them load the same build.
Sys.setenv(R_LIBS = paste(.libPaths(), collapse = .Platform$path.sep))
zcurve_version <- as.character(packageVersion("zcurve"))
message("Using zcurve ", zcurve_version, " from ", find.package("zcurve"))

sim <- readRDS("output/sim_data.rds")
sim_grid <- sim$sim_grid
simulated_data <- sim$simulated_data

if (length(args) >= 4) {
  simulated_data <- simulated_data[seq_len(as.integer(args[4]))]
}

progress_file <- sprintf("output/progress_%s.rds", label)


results <- vector("list", length(simulated_data))

for (i in seq_along(simulated_data)) {

  d <- simulated_data[[i]]

  scenario_id <- unique(d$scenario_id)
  settings <- sim_grid[
    sim_grid$scenario_id == scenario_id,
    ,
    drop = FALSE
  ]

  # Calculate population truth over all attempted tests, averaging over the
  # power mixture (article size does not depend on power).
  mu <- zcurve::power_to_z(sim$power_mixtures[[as.character(settings$power)]])
  critical_z <- qnorm(0.975)

  p_positive <- pnorm(critical_z, mean = mu, lower.tail = FALSE)
  p_negative <- pnorm(-critical_z, mean = mu)

  true_EDR <- mean(p_positive + p_negative)
  true_ERR <- mean(p_positive^2 + p_negative^2) / true_EDR

  # Start a results row; failed fits will retain NA estimates.
  row <- data.frame(
    settings,
    label = label,
    method = method,
    zcurve_version = zcurve_version,
    dataset = i,
    simulation = unique(d$simulation),
    actual_sig_k = nrow(d),
    n_articles = length(unique(d$article_id)),
    actual_av_sig_k_per_a = mean(as.numeric(table(d$article_id))),
    true_ERR = true_ERR,
    true_EDR = true_EDR,
    ERR = NA_real_,
    ERR_lower = NA_real_,
    ERR_upper = NA_real_,
    EDR = NA_real_,
    EDR_lower = NA_real_,
    EDR_upper = NA_real_,
    converged = NA,
    error = NA_character_
  )

  # Same seed per dataset across labels, so versions get identical bootstrap draws.
  set.seed(100000 + i)

  # Catch errors so one failed fit does not stop the whole loop.
  fit <- tryCatch({

    if (method == "clustered") {

      z_data <- zcurve::zcurve_data(
        data = sprintf("z=%.12f", d$z),
        id = d$article_id,
        rounded = FALSE
      )

      zcurve::zcurve_clustered(
        data = z_data,
        method = "b",
        bootstrap = n_boot,
        parallel = TRUE
      )

    } else {

      zcurve::zcurve(
        z = d$z,
        method = "EM",
        bootstrap = n_boot,
        parallel = TRUE
      )
    }

  }, error = function(e) e)

  if (inherits(fit, "error")) {

    row$error <- conditionMessage(fit)

  } else {

    row$converged <- fit$converged
    row$ERR <- unname(fit$coefficients["ERR"])
    row$EDR <- unname(fit$coefficients["EDR"])

    # Raw 95% percentile bootstrap intervals.
    err_ci <- quantile(
      fit$coefficients_boot$ERR,
      probs = c(0.025, 0.975)
    )

    edr_ci <- quantile(
      fit$coefficients_boot$EDR,
      probs = c(0.025, 0.975)
    )

    row$ERR_lower <- unname(err_ci[1])
    row$ERR_upper <- unname(err_ci[2])
    row$EDR_lower <- unname(edr_ci[1])
    row$EDR_upper <- unname(edr_ci[2])
  }

  results[[i]] <- row

  # Save progress after each dataset.
  saveRDS(results, progress_file)

  message("[", label, "] Finished dataset ", i, " of ", length(simulated_data))
}

results <- do.call(rbind, results)

# Useful columns for evaluating CI width and coverage.
results$ERR_width <- results$ERR_upper - results$ERR_lower
results$EDR_width <- results$EDR_upper - results$EDR_lower

results$ERR_covered <- with(
  results,
  ERR_lower <= true_ERR & ERR_upper >= true_ERR
)

results$EDR_covered <- with(
  results,
  EDR_lower <= true_EDR & EDR_upper >= true_EDR
)

write.csv(results, sprintf("output/results_%s.csv", label), row.names = FALSE)
