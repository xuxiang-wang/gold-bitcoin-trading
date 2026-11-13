# Writes R reference results that website/validate.js compares the JavaScript engine against.
source("strategy.R")
cases <- data.frame(risk_aversion = c(5, 1, 20, 2, 10, 5, 50, 5, 5),
                    half_life_mean = c(30, 14, 120, 60, 30, 30, 30, 14, 60),
                    horizon = c(30, 10, 60, 30, 60, 30, 30, 30, 10),
                    maximum_bitcoin_weight = c(1, 1, 1, 0.5, 0.25, 0.75, 1, 1, 0.6),
                    cost_multiplier = c(1, 1, 1, 1, 1, 0, 1, 3, 0.5))
cases$final <- NA; cases$trades <- NA
for (i in seq_len(nrow(cases))) { r <- do.call(run_strategy, as.list(cases[i, 1:5])); cases$final[i] <- sprintf("%.10f", tail(r$daily$value, 1)); cases$trades[i] <- r$trades }
adaptive <- read.csv("output/adaptive_settings.csv")
writeLines(jsonlite::toJSON(list(cases = cases, adaptive = adaptive[, c("risk_aversion", "adaptive_final_value", "adaptive_trades")],
  comparison = read.csv("output/strategy_comparison.csv")), digits = NA, auto_unbox = TRUE), "website/validation.json")
print(cases)
