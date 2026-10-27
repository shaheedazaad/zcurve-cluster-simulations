n_sims <- 150

# Each article draws its power from one of these mixtures; `power` in the grid is the mixture mean.
power_mixtures <- list(`0.3` = c(.10, .30, .50),
                       `0.5` = c(.20, .50, .80))
powers <- as.numeric(names(power_mixtures))
rhos <- c(.20, .30) 
total_sig_k <- c(50, 100) 
av_sig_k_per_a <- c(1.5, 2)

sim_grid <- expand.grid(
  power = powers,
  rho = rhos,
  total_sig_k = total_sig_k,
  av_sig_k_per_a = av_sig_k_per_a
)

sim_grid$scenario_id <- seq_len(nrow(sim_grid))

set.seed(123)
z_critical <- qnorm(0.975)

# Generate one article and return its significant z-scores.
# The article's mean z is drawn from `mus`, so all its tests share one power.
simulate_article <- function(mus, rho, mean_tests) {

  mu <- sample(mus, 1)

  # Article sizes: at least one attempted test, plus a Poisson number of extra tests.
  k <- 1 + rpois(1, mean_tests - 1)

  shared_error <- rnorm(1)
  individual_errors <- rnorm(k)

  z <- mu +
    sqrt(rho) * shared_error +
    sqrt(1 - rho) * individual_errors

  abs(z[abs(z) > z_critical])
}

# Each element will hold one simulated dataset.
simulated_data <- list()
dataset_id <- 0

for (s in seq_len(nrow(sim_grid))) {

  power <- sim_grid$power[s]
  rho <- sim_grid$rho[s]
  target_total <- sim_grid$total_sig_k[s]
  target_average <- sim_grid$av_sig_k_per_a[s]

  mus <- zcurve::power_to_z(power_mixtures[[as.character(power)]])

  # Starting guess for the mean number of attempted tests.
  mean_tests <- target_average / power

  # Calibration: adjust this guess using small pilot simulations.
  for (step in 1:10) {

    pilot_counts <- numeric(1000)

    for (a in seq_along(pilot_counts)) {
      pilot_z <- simulate_article(mus, rho, mean_tests)
      pilot_counts[a] <- length(pilot_z)
    }

    # Only articles with significant results enter the dataset.
    observed_average <- mean(pilot_counts[pilot_counts > 0])

    mean_tests <- mean_tests * target_average / observed_average
    mean_tests <- max(1, mean_tests)
  }

  sim_grid$mean_attempted_tests[s] <- mean_tests

  for (sim in seq_len(n_sims)) {

    articles <- list()
    n_significant <- 0
    article_id <- 0

    while (n_significant < target_total) {

      article_id <- article_id + 1
      significant_z <- simulate_article(mus, rho, mean_tests)

      if (length(significant_z) > 0) {

        articles[[length(articles) + 1]] <- data.frame(
          scenario_id = s,
          simulation = sim,
          article_id = article_id,
          z = significant_z
        )

        n_significant <- n_significant + length(significant_z)
      }
    }

    dataset_id <- dataset_id + 1
    simulated_data[[dataset_id]] <- do.call(rbind, articles)
  }

  message("Finished scenario ", s, " of ", nrow(sim_grid))
}
saveRDS(
  list(sim_grid = sim_grid, power_mixtures = power_mixtures, simulated_data = simulated_data),
  "output/sim_data.rds"
)
