# 2022 MCM Problem C: Trading Strategies
# Shared definitions, sourced by the numbered steps: the strategy and the summary measures.
#
# Rules that every strategy here follows (step 1 of the analysis turns the problem into these):
#   - The decision on day t uses prices up to and including day t, and trades at day t's price.
#   - Gold is traded only on days with a gold price; bitcoin can be traded every day.
#   - A purchase or sale of x dollars costs alpha * x (alpha = 1% gold, 2% bitcoin).
#   - Start with $1000 cash on 9/11/2016; report the marked-to-market value on 9/10/2021.
#
# Strategy (chosen in 04_compare_methods.R; settings decided before looking at results):
#   Each day, estimate each asset's expected daily return with an exponentially weighted
#   mean of past returns (momentum), and the covariance with an exponentially weighted
#   average of past squared/cross returns. Choose portfolio weights to maximize
#       horizon * expected return - (risk_aversion / 2) * horizon * variance - transaction costs
#   with no short selling and no borrowing. Because the commission is charged once but the
#   expected gain accrues over the holding horizon, the optimizer trades only when the
#   expected benefit exceeds the cost.

library(quadprog)

prices <- readRDS("output/prices.rds")

# One day's decision: the target weights (gold, bitcoin) that maximize
#   horizon * expected_return' w - (risk_aversion / 2) * horizon * w' covariance w - commissions
# given the current weights. Checked against a brute-force search in 07_checks.R.
choose_weights <- function(current, cost, expected_return, covariance, risk_aversion, horizon,
                           maximum_bitcoin_weight, gold_tradable) {
  # The commission makes the objective kinked at the current weights, so solve one smooth
  # quadratic program for each trade direction (buy or sell each asset) and keep the best.
  # On days the gold market is closed, the gold weight is fixed at its current value.
  best_objective <- Inf
  for (gold_direction in if (gold_tradable) c(1, -1) else 0) {
    for (bitcoin_direction in c(1, -1)) {
      direction <- c(gold_direction, bitcoin_direction)
      constraints <- rbind(
        diag(direction),                        # trade each asset only in the chosen direction
        -(1 + cost * direction),                # weights + commissions <= 1 (no borrowing)
        diag(2),                                # no short selling
        -(c(0, 1) + maximum_bitcoin_weight * cost * direction)  # bitcoin <= cap of the value after commissions
      )
      bounds <- c(direction * current,
                  -max(1, sum(current)) - sum(cost * direction * current) - 1e-9,
                  0, 0, -maximum_bitcoin_weight * (1 + sum(cost * direction * current)) - 1e-9)
      equalities <- 0
      if (gold_direction == 0) {
        # Gold is fixed at its current weight; its "no short selling" row (row 4) is then redundant,
        # and quadprog rejects the duplicate when the gold weight is exactly zero.
        constraints[1, ] <- c(1, 0)
        equalities <- 1
        bounds[1] <- current[1]
        constraints <- constraints[-4, ]
        bounds <- bounds[-4]
      }
      fit <- tryCatch(
        solve.QP(risk_aversion * horizon * covariance + diag(1e-10, 2),
                 horizon * expected_return - cost * direction,
                 t(constraints), bounds, meq = equalities),
        error = function(error) NULL)
      if (is.null(fit)) next
      objective <- fit$value - sum(cost * direction * current)
      if (objective < best_objective) {
        best_objective <- objective
        target <- fit$solution
      }
    }
  }
  target
}

# risk_aversion: higher = more cautious. maximum_bitcoin_weight: a hard cap on bitcoin's share.
# half_life_mean and horizon may be single numbers or one value per day (used by 06_sensitivity.R,
# where they are re-chosen every day); an exponentially weighted mean is kept for every half-life used.
# forecast: optional matrix (days x 2: gold, bitcoin) of expected daily returns from another model
# (04_compare_methods.R); on days where it is not NA it replaces the momentum estimate.
run_strategy <- function(risk_aversion = 5, half_life_mean = 30, horizon = 30, maximum_bitcoin_weight = 1,
                         cost_multiplier = 1, half_life_covariance = 30, warm_up_days = 30, forecast = NULL) {
  gold_cost <- 0.01 * cost_multiplier
  bitcoin_cost <- 0.02 * cost_multiplier
  half_life_mean <- rep_len(half_life_mean, nrow(prices))
  horizon <- rep_len(horizon, nrow(prices))
  mean_half_lives <- unique(half_life_mean)
  decay_mean <- 0.5^(1 / mean_half_lives)
  decay_covariance <- 0.5^(1 / half_life_covariance)

  cash <- 1000
  gold_ounces <- 0
  bitcoins <- 0
  mean_return <- matrix(0, 2, length(mean_half_lives))
  covariance <- diag(2) * 1e-4
  portfolio_value <- numeric(nrow(prices))
  gold_weight <- numeric(nrow(prices))
  bitcoin_weight <- numeric(nrow(prices))
  fees_paid <- 0
  trades <- 0

  for (day in seq_len(nrow(prices))) {
    gold_price <- prices$gold_price[day]
    bitcoin_price <- prices$bitcoin_price[day]
    value <- cash + bitcoins * bitcoin_price + ifelse(is.na(gold_price), 0, gold_ounces * gold_price)

    # Update estimates with today's returns (known at today's close).
    if (day > 1) {
      todays_return <- c(prices$gold_return[day], prices$bitcoin_return[day])
      mean_return <- sweep(mean_return, 2, decay_mean, "*") + outer(todays_return, 1 - decay_mean)
      covariance <- decay_covariance * covariance + (1 - decay_covariance) * tcrossprod(todays_return)
    }

    if (day > warm_up_days) {
      current <- c(max(0, ifelse(is.na(gold_price), 0, gold_ounces * gold_price / value)),
                   max(0, bitcoins * bitcoin_price / value))
      cost <- c(gold_cost, bitcoin_cost)
      expected_return <- mean_return[, match(half_life_mean[day], mean_half_lives)]
      if (!is.null(forecast) && !is.na(forecast[day, 1])) expected_return <- forecast[day, ]

      target <- choose_weights(current, cost, expected_return, covariance, risk_aversion, horizon[day],
                               maximum_bitcoin_weight, prices$gold_tradable[day])

      gold_trade <- (target[1] - current[1]) * value
      bitcoin_trade <- (target[2] - current[2]) * value
      # Ignore numerically tiny trades (under one cent).
      if (abs(gold_trade) < 0.01) gold_trade <- 0
      if (abs(bitcoin_trade) < 0.01) bitcoin_trade <- 0
      fees <- gold_cost * abs(gold_trade) + bitcoin_cost * abs(bitcoin_trade)
      # max(0, ...) removes rounding error (about 1e-15) left after selling a whole position.
      if (gold_trade != 0) gold_ounces <- max(0, gold_ounces + gold_trade / gold_price)
      if (bitcoin_trade != 0) bitcoins <- max(0, bitcoins + bitcoin_trade / bitcoin_price)
      cash <- cash - gold_trade - bitcoin_trade - fees
      fees_paid <- fees_paid + fees
      trades <- trades + (gold_trade != 0) + (bitcoin_trade != 0)
      value <- value - fees
    }

    portfolio_value[day] <- value
    gold_weight[day] <- ifelse(is.na(gold_price), 0, gold_ounces * gold_price / value)
    bitcoin_weight[day] <- bitcoins * bitcoin_price / value
  }

  list(daily = data.frame(date = prices$date, value = portfolio_value,
                          gold_weight = gold_weight, bitcoin_weight = bitcoin_weight),
       fees_paid = fees_paid, trades = trades)
}

summarize_path <- function(value, name, trades = NA, fees_paid = NA) {
  daily_return <- diff(value) / head(value, -1)
  years <- (length(value) - 1) / 365
  data.frame(
    strategy = name,
    final_value = tail(value, 1),
    annual_growth = (tail(value, 1) / 1000)^(1 / years) - 1,
    annual_volatility = sd(daily_return) * sqrt(365),
    sharpe_ratio = mean(daily_return) / sd(daily_return) * sqrt(365),
    max_drawdown = max(1 - value / cummax(value)),
    trades = trades,
    fees_paid = fees_paid
  )
}
