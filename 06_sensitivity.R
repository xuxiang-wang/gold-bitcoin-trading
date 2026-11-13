# 2022 MCM Problem C: Trading Strategies
# Step 6. Sensitivity: how much do the results depend on commissions and on the model's own settings,
# and would re-choosing those settings every day help?

source("strategy.R")
backtest <- readRDS("output/backtest.rds")
strategy <- backtest$strategy
bitcoin_hold <- backtest$bitcoin_hold
half_and_half <- backtest$half_and_half
gold_hold <- backtest$gold_hold
results <- read.csv("output/strategy_comparison.csv")

# ---- (a) Transaction costs: scale both commissions (1x = 1% gold, 2% bitcoin) ----
cost_sensitivity <- do.call(rbind, lapply(c(0, 0.25, 0.5, 1, 1.5, 2, 3), function(multiplier) {
  run <- run_strategy(cost_multiplier = multiplier)
  data.frame(
    cost_multiplier = multiplier,
    gold_commission = 0.01 * multiplier,
    bitcoin_commission = 0.02 * multiplier,
    final_value = tail(run$daily$value, 1),
    trades = run$trades,
    fees_paid = run$fees_paid,
    average_bitcoin_weight = mean(run$daily$bitcoin_weight),
    average_gold_weight = mean(run$daily$gold_weight),
    buy_and_hold_bitcoin = 1000 / (1 + 0.02 * multiplier) / prices$bitcoin_price[1] * tail(prices$bitcoin_price, 1)
  )
}))
print(cost_sensitivity, digits = 3)
write.csv(cost_sensitivity, "output/cost_sensitivity.csv", row.names = FALSE)

# ---- (b) Model settings: does the conclusion depend on the pre-specified choice? ----
settings <- expand.grid(risk_aversion = c(1, 2, 5, 10, 20),
                        half_life_mean = c(14, 30, 60, 120),
                        horizon = c(10, 30, 60))
setting_results <- do.call(rbind, lapply(seq_len(nrow(settings)), function(row) {
  run <- run_strategy(risk_aversion = settings$risk_aversion[row],
                      half_life_mean = settings$half_life_mean[row],
                      horizon = settings$horizon[row])
  cbind(settings[row, ], summarize_path(run$daily$value, "grid", run$trades, run$fees_paid)[, -1])
}))
write.csv(setting_results, "output/setting_grid.csv", row.names = FALSE)

cat("\nAcross", nrow(setting_results), "settings:\n")
print(summary(setting_results[, c("final_value", "sharpe_ratio", "max_drawdown")]))
cat("Share beating buy-and-hold 50/50 in final value:",
    mean(setting_results$final_value > tail(half_and_half, 1)), "\n")
cat("Share beating buy-and-hold bitcoin in final value:",
    mean(setting_results$final_value > tail(bitcoin_hold, 1)), "\n")
cat("Share with lower max drawdown than buy-and-hold bitcoin:",
    mean(setting_results$max_drawdown < results$max_drawdown[4]), "\n")
cat("Rank of the pre-specified setting by final value:",
    rank(-setting_results$final_value)[with(setting_results, risk_aversion == 5 & half_life_mean == 30 & horizon == 30)],
    "of", nrow(setting_results), "\n")

# ---- (c) Year by year (each year runs 9/11 to 9/10) ----
year_end <- prices$date %in% as.Date(c("2016-09-11", "2017-09-10", "2018-09-10", "2019-09-10", "2020-09-10", "2021-09-10"))
yearly <- data.frame(
  year_ending = format(prices$date[year_end][-1], "%Y"),
  strategy = diff(log(strategy$daily$value[year_end])),
  buy_and_hold_bitcoin = diff(log(bitcoin_hold[year_end])),
  buy_and_hold_gold = diff(log(gold_hold[year_end]))
)
yearly[, -1] <- exp(yearly[, -1]) - 1
print(yearly, digits = 3)
write.csv(yearly, "output/yearly_returns.csv", row.names = FALSE)

# ---- (d) Settings re-chosen every day ----
# The trader fixes the risk level; every day the signal settings (momentum half-life and horizon)
# switch to whichever of 12 candidates grew most over the past 180 days. Candidates are tracked as
# paper portfolios, so every choice uses only prices up to that day.
candidates <- expand.grid(half_life_mean = c(14, 30, 60, 120), horizon = c(10, 30, 60))
lookback_days <- 180

adaptive <- do.call(rbind, lapply(c(1, 2, 5, 10, 20), function(risk_aversion) {
  # Paper portfolios: one per candidate setting, at the trader's risk level.
  paper_value <- sapply(seq_len(nrow(candidates)), function(row) {
    run_strategy(risk_aversion = risk_aversion, half_life_mean = candidates$half_life_mean[row],
                 horizon = candidates$horizon[row])$daily$value
  })
  # Growth over the past 180 days, known at each day's close; before 180 days of history,
  # use the pre-specified setting (half-life 30, horizon 30).
  past_growth <- rbind(matrix(NA, lookback_days, ncol(paper_value)),
                       log(paper_value[-(1:lookback_days), ] / paper_value[1:(nrow(paper_value) - lookback_days), ]))
  chosen <- apply(past_growth, 1, function(growth) if (all(is.na(growth))) NA else which.max(growth))
  chosen[is.na(chosen)] <- which(candidates$half_life_mean == 30 & candidates$horizon == 30)

  run <- run_strategy(risk_aversion = risk_aversion,
                      half_life_mean = candidates$half_life_mean[chosen],
                      horizon = candidates$horizon[chosen])
  fixed <- run_strategy(risk_aversion = risk_aversion)
  data.frame(
    risk_aversion = risk_aversion,
    adaptive_final_value = tail(run$daily$value, 1),
    adaptive_sharpe_ratio = summarize_path(run$daily$value, "adaptive")$sharpe_ratio,
    adaptive_max_drawdown = summarize_path(run$daily$value, "adaptive")$max_drawdown,
    adaptive_trades = run$trades,
    setting_changes = sum(diff(chosen) != 0),
    fixed_final_value = tail(fixed$daily$value, 1),
    candidates_median_final_value = median(paper_value[nrow(paper_value), ]),
    candidates_best_final_value_in_hindsight = max(paper_value[nrow(paper_value), ]),
    adaptive_rank_among_13 = sum(paper_value[nrow(paper_value), ] > tail(run$daily$value, 1)) + 1
  )
}))
print(adaptive, digits = 3, row.names = FALSE)
write.csv(adaptive, "output/adaptive_settings.csv", row.names = FALSE)
