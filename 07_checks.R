# 2022 MCM Problem C: Trading Strategies
# Step 7. Checks that the code does what the write-up says. Every check prints PASS or FAIL.
# (The website's JavaScript engine is checked separately: website/validate.js.)

source("strategy.R")
report <- function(name, passed) cat(ifelse(passed, "PASS", "FAIL"), name, "\n")

# 1. The daily optimizer finds the true optimum: compare with a brute-force grid on random problems.
set.seed(7)
worst_gap <- 0
for (problem in 1:300) {
  random_matrix <- matrix(rnorm(4), 2)
  covariance <- crossprod(random_matrix) * 1e-3 + diag(1e-5, 2)
  expected_return <- rnorm(2, 0.002, 0.004)
  risk_aversion <- sample(c(1, 5, 20), 1)
  maximum_bitcoin_weight <- sample(c(0.5, 1), 1)
  gold_tradable <- runif(1) > 0.3
  current <- runif(2)
  current <- current / sum(current) * runif(1)
  cost <- c(0.01, 0.02)
  objective <- function(weights) {
    -30 * sum(expected_return * weights) + risk_aversion / 2 * 30 * drop(t(weights) %*% covariance %*% weights) +
      sum(cost * abs(weights - current))
  }
  target <- choose_weights(current, cost, expected_return, covariance, risk_aversion, 30,
                           maximum_bitcoin_weight, gold_tradable)
  grid <- expand.grid(gold = if (gold_tradable) seq(0, 1, by = 0.005) else current[1],
                      bitcoin = seq(0, maximum_bitcoin_weight, by = 0.005))
  fees <- with(grid, cost[1] * abs(gold - current[1]) + cost[2] * abs(bitcoin - current[2]))
  feasible <- with(grid, gold + bitcoin + fees <= 1 & bitcoin <= maximum_bitcoin_weight * (1 - fees))
  if (!any(feasible)) next
  worst_gap <- max(worst_gap, objective(target) - min(apply(grid[feasible, ], 1, objective)))
}
report("optimizer is never beaten by a brute-force grid (worst gap <= 1e-12)", worst_gap <= 1e-12)

# 2. Accounting on the pre-specified run.
run <- run_strategy()
gold_ounces <- run$daily$gold_weight * run$daily$value / prices$gold_price
closed_days <- which(!prices$gold_tradable)[-1]
report("gold holdings never change on days the gold market is closed",
       max(abs(gold_ounces[closed_days] - gold_ounces[closed_days - 1]), na.rm = TRUE) < 1e-9)
report("weights stay between 0 and 1 and never exceed 100% together",
       all(run$daily$gold_weight >= 0, run$daily$bitcoin_weight >= 0,
           run$daily$gold_weight + run$daily$bitcoin_weight <= 1 + 1e-6))
report("no trades during the 30-day warm-up", all(run$daily$value[1:30] == 1000))

# 3. The bitcoin cap holds after every day's trading.
capped <- run_strategy(maximum_bitcoin_weight = 0.5)
# A price rise can lift bitcoin above the cap during a day; the strategy sells down that same day.
report("bitcoin share never above a 50% cap after each day's trading", max(capped$daily$bitcoin_weight) <= 0.5 + 1e-6)

# 4. No look-ahead: change every price after day 1000 and the first 1000 days must not change.
original_prices <- prices
set.seed(8)
prices$bitcoin_price[1001:nrow(prices)] <- prices$bitcoin_price[1001:nrow(prices)] * exp(rnorm(nrow(prices) - 1000, 0, 0.05))
prices$gold_price[1001:nrow(prices)] <- prices$gold_price[1001:nrow(prices)] * exp(rnorm(nrow(prices) - 1000, 0, 0.02))
prices$bitcoin_return <- c(NA, diff(prices$bitcoin_price) / head(prices$bitcoin_price, -1))
prices$gold_return <- c(0, diff(prices$gold_price) / head(prices$gold_price, -1))
prices$gold_return[is.na(prices$gold_return)] <- 0
changed <- run_strategy()
lstm <- read.csv("output/lstm_forecasts.csv")
prices <- original_prices
report("strategy's first 1000 days are identical when later prices change",
       identical(changed$daily$value[1:1000], run$daily$value[1:1000]))
report("LSTM forecasts exist only from day 181 (trained on past data)",
       all(is.na(lstm$gold_next_day[1:180])) && !any(is.na(lstm$gold_next_day[181:nrow(lstm)])))

# 5. A benchmark recomputed by hand.
report("buy-and-hold bitcoin = 1000 / 1.02 / 621.65 * 46368.69",
       abs(readRDS("output/benchmarks.rds")$bitcoin_hold[nrow(prices)] - 1000 / 1.02 / 621.65 * 46368.69) < 1e-6)
