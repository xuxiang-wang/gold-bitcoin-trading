# 2022 MCM Problem C: Trading Strategies
# Step 3. Benchmarks: what simple choices achieve under the same rules, and the hindsight upper bound.
# They set the standard any strategy has to be judged against.

source("strategy.R")

# ---- Benchmarks (same commissions, same trading calendar) ----
first_gold_day <- which(prices$gold_tradable)[1]
bitcoin_hold <- 1000 / 1.02 / prices$bitcoin_price[1] * prices$bitcoin_price
gold_hold <- c(rep(1000, first_gold_day - 1),
               1000 / 1.01 / prices$gold_price[first_gold_day] * prices$gold_price[first_gold_day:nrow(prices)])
half_and_half <- c(rep(1000, first_gold_day - 1),
                   500 / 1.01 / prices$gold_price[first_gold_day] * prices$gold_price[first_gold_day:nrow(prices)] +
                     500 / 1.02 / prices$bitcoin_price[first_gold_day] * prices$bitcoin_price[first_gold_day:nrow(prices)])

# Trend following: two $500 sleeves; each holds its asset when price is above its 50-day average, else cash.
trend_value <- numeric(nrow(prices))
trend_trades <- 0
trend_fees <- 0
sleeve_cash <- c(gold = 500, bitcoin = 500)
sleeve_units <- c(gold = 0, bitcoin = 0)
moving_average_gold <- zoo::rollmeanr(prices$gold_price, 50, fill = NA)
moving_average_bitcoin <- zoo::rollmeanr(prices$bitcoin_price, 50, fill = NA)
for (day in seq_len(nrow(prices))) {
  current_price <- c(gold = prices$gold_price[day], bitcoin = prices$bitcoin_price[day])
  signal <- c(gold = current_price[["gold"]] > moving_average_gold[day],
              bitcoin = current_price[["bitcoin"]] > moving_average_bitcoin[day])
  can_trade <- c(gold = prices$gold_tradable[day], bitcoin = TRUE)
  cost <- c(gold = 0.01, bitcoin = 0.02)
  for (asset in c("gold", "bitcoin")) {
    if (is.na(signal[[asset]]) || !can_trade[[asset]]) next
    if (signal[[asset]] && sleeve_units[[asset]] == 0) {
      sleeve_units[[asset]] <- sleeve_cash[[asset]] / (1 + cost[[asset]]) / current_price[[asset]]
      trend_fees <- trend_fees + sleeve_cash[[asset]] - sleeve_cash[[asset]] / (1 + cost[[asset]])
      sleeve_cash[[asset]] <- 0
      trend_trades <- trend_trades + 1
    } else if (!signal[[asset]] && sleeve_units[[asset]] > 0) {
      proceeds <- sleeve_units[[asset]] * current_price[[asset]]
      sleeve_cash[[asset]] <- proceeds * (1 - cost[[asset]])
      trend_fees <- trend_fees + proceeds * cost[[asset]]
      sleeve_units[[asset]] <- 0
      trend_trades <- trend_trades + 1
    }
  }
  trend_value[day] <- sum(sleeve_cash) + sleeve_units[["bitcoin"]] * current_price[["bitcoin"]] +
    ifelse(is.na(current_price[["gold"]]), 0, sleeve_units[["gold"]] * current_price[["gold"]])
}

# ---- Perfect-foresight upper bound (uses future prices; not a feasible strategy) ----
# With proportional commissions the best hindsight portfolio is always fully in one asset,
# so dynamic programming over three states (cash, gold, bitcoin) gives the exact maximum.
best <- c(cash = 1000, gold = -Inf, bitcoin = -Inf)  # best value held in each state, in that state's units of dollars
for (day in seq_len(nrow(prices))) {
  if (day > 1) {
    growth_gold <- ifelse(is.na(prices$gold_price[day - 1]), 1, prices$gold_price[day] / prices$gold_price[day - 1])
    best[["gold"]] <- best[["gold"]] * growth_gold
    best[["bitcoin"]] <- best[["bitcoin"]] * prices$bitcoin_price[day] / prices$bitcoin_price[day - 1]
  }
  previous <- best
  best[["cash"]] <- max(previous[["cash"]],
                        ifelse(prices$gold_tradable[day], previous[["gold"]] * 0.99, -Inf),
                        previous[["bitcoin"]] * 0.98)
  if (prices$gold_tradable[day]) {
    best[["gold"]] <- max(previous[["gold"]], best[["cash"]] / 1.01)
  }
  best[["bitcoin"]] <- max(previous[["bitcoin"]], best[["cash"]] / 1.02)
}
perfect_foresight <- max(best)

benchmarks <- rbind(
  summarize_path(rep(1000, nrow(prices)), "Hold cash"),
  summarize_path(gold_hold, "Buy and hold gold", 1, 1000 - 1000 / 1.01),
  summarize_path(bitcoin_hold, "Buy and hold bitcoin", 1, 1000 - 1000 / 1.02),
  summarize_path(half_and_half, "Buy and hold 50/50", 2, 500 - 500 / 1.01 + 500 - 500 / 1.02),
  summarize_path(trend_value, "50-day trend following", trend_trades, trend_fees)
)
print(benchmarks, digits = 3)
cat("Perfect-foresight maximum (hindsight bound, not achievable):", format(perfect_foresight, big.mark = ","), "\n")

write.csv(benchmarks, "output/benchmarks.csv", row.names = FALSE)
saveRDS(list(bitcoin_hold = bitcoin_hold, gold_hold = gold_hold, half_and_half = half_and_half,
             trend_value = trend_value, perfect_foresight = perfect_foresight),
        "output/benchmarks.rds")
