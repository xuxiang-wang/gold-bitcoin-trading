# 2022 MCM Problem C: Trading Strategies
# Step 4. Compare candidate methods under the same rules, then fix the method used from here on.
# Run 03_lstm_forecasts.py first.
#
# Two candidates for the expected-return estimate, each set up before any results were seen:
#   momentum  exponentially weighted mean of past returns (half-life 30 days), see strategy.R
#   LSTM      walk-forward neural-network forecasts (a common choice for this problem),
#             with two targets: next-day return and average return over the next 30 days
# Everything else is identical: risk estimate, commissions, constraints, 30-day horizon.
#
# (a) Forecast accuracy on days the LSTM had not seen (day 181 onward):
#     the LSTM, the momentum estimate the strategy uses (30-day half-life), and a forecast of zero.
#     Out-of-sample R squared = 1 - (squared error of the forecast) / (squared error of forecasting zero);
#     a negative value means the forecast did worse than always predicting zero.
#     Diebold-Mariano test: is the LSTM's squared error different from the momentum estimate's?
#     (Newey-West standard errors; lag 5 for next-day targets, 30 for overlapping 30-day targets.)
# (b) The same strategy with the LSTM forecast in place of the momentum estimate.
#     Everything else is unchanged: risk, commissions, constraints, horizon.

library(sandwich)
source("strategy.R")
lstm <- read.csv("output/lstm_forecasts.csv")
days <- nrow(prices)
asset_returns <- cbind(gold = prices$gold_return, bitcoin = prices$bitcoin_return)
asset_returns[is.na(asset_returns)] <- 0

# Momentum estimate exactly as in the strategy (known at each day's close).
momentum <- matrix(0, days, 2)
decay <- 0.5^(1 / 30)
for (day in 2:days) momentum[day, ] <- decay * momentum[day - 1, ] + (1 - decay) * asset_returns[day, ]

# ---- (a) Forecast accuracy ----
accuracy <- do.call(rbind, lapply(c(next_day = 1, next_30_days = 30), function(horizon) {
  target_name <- ifelse(horizon == 1, "next_day", "next_30_days")
  evaluated <- which(!is.na(lstm[[paste0("gold_", target_name)]]) & seq_len(days) + horizon <= days)
  do.call(rbind, lapply(1:2, function(asset) {
    actual <- sapply(evaluated, function(day) mean(asset_returns[day + 1:horizon, asset]))
    lstm_forecast <- lstm[[paste0(c("gold_", "bitcoin_")[asset], target_name)]][evaluated]
    momentum_forecast <- momentum[evaluated, asset]
    # Gold's next-day return is 0 on closed days; leave those out of the direction count.
    moved <- actual != 0
    loss_difference <- (actual - lstm_forecast)^2 - (actual - momentum_forecast)^2
    test <- lm(loss_difference ~ 1)
    t_value <- coef(test) / sqrt(NeweyWest(test, lag = ifelse(horizon == 1, 5, 30), prewhite = FALSE)[1, 1])
    data.frame(
      target = target_name,
      asset = c("gold", "bitcoin")[asset],
      days_evaluated = length(evaluated),
      r_squared_lstm = 1 - sum((actual - lstm_forecast)^2) / sum(actual^2),
      r_squared_momentum = 1 - sum((actual - momentum_forecast)^2) / sum(actual^2),
      direction_right_lstm = mean(sign(lstm_forecast[moved]) == sign(actual[moved])),
      direction_right_momentum = mean(sign(momentum_forecast[moved]) == sign(actual[moved])),
      share_of_days_actual_rose = mean(actual[moved] > 0),
      diebold_mariano_p_value = 2 * pnorm(-abs(t_value))
    )
  }))
}))
print(accuracy, digits = 3, row.names = FALSE)
write.csv(accuracy, "output/lstm_forecast_accuracy.csv", row.names = FALSE)

# ---- (b) Strategy results ----
strategies <- do.call(rbind, lapply(c(1, 2, 5, 10, 20), function(risk_aversion) {
  do.call(rbind, lapply(c("momentum", "next_day", "next_30_days"), function(forecast_name) {
    forecast <- if (forecast_name == "momentum") NULL else
      as.matrix(lstm[, paste0(c("gold_", "bitcoin_"), forecast_name)])
    run <- run_strategy(risk_aversion = risk_aversion, forecast = forecast)
    cbind(risk_aversion = risk_aversion,
          forecast = c(momentum = "Momentum (pre-specified)", next_day = "LSTM, next day",
                       next_30_days = "LSTM, next 30 days")[[forecast_name]],
          summarize_path(run$daily$value, "x", run$trades, run$fees_paid)[, -1])
  }))
}))
print(strategies[, c("risk_aversion", "forecast", "final_value", "sharpe_ratio", "max_drawdown", "trades", "fees_paid")],
      digits = 3, row.names = FALSE)
write.csv(strategies, "output/lstm_strategy_comparison.csv", row.names = FALSE)

# ---- (c) The chosen method against the benchmarks ----
# Momentum wins on forecast accuracy (neither forecasts well, but the LSTM's errors cost more in
# trading) and on final value and Sharpe ratio at four of five risk levels, so it is the method
# used in every later step, with the pre-specified risk aversion of 5.
strategy <- run_strategy()
benchmark_paths <- readRDS("output/benchmarks.rds")
results <- rbind(
  summarize_path(strategy$daily$value, "Cost-aware mean-variance (this project)", strategy$trades, strategy$fees_paid),
  read.csv("output/benchmarks.csv")
)
print(results, digits = 3)
write.csv(results, "output/strategy_comparison.csv", row.names = FALSE)
saveRDS(c(list(strategy = strategy), benchmark_paths), "output/backtest.rds")
