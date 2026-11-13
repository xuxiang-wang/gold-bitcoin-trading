# 2022 MCM Problem C: Trading Strategies
# Step 5. Settings the trader chooses: a risk-tolerance level (risk aversion) and a cap on bitcoin's
# share of the portfolio. These express the trader's preferences, so they are left to the trader
# (on the website as well). Each choice has to be made before trading starts.
# The model's own settings (momentum half-life, horizon) are not offered as choices; step 6 only
# checks how much the results depend on them.

source("strategy.R")

# ---- (a) Risk tolerance x bitcoin cap ----
risk_levels <- c("Very aggressive" = 1, "Aggressive" = 2, "Moderate" = 5, "Cautious" = 10,
                 "Very cautious" = 20, "Most cautious" = 50)
choices <- expand.grid(risk_aversion = risk_levels, maximum_bitcoin_weight = c(0.25, 0.5, 0.75, 1))
risk_choices <- do.call(rbind, lapply(seq_len(nrow(choices)), function(row) {
  run <- run_strategy(risk_aversion = choices$risk_aversion[row],
                      maximum_bitcoin_weight = choices$maximum_bitcoin_weight[row])
  cbind(risk_level = names(risk_levels)[match(choices$risk_aversion[row], risk_levels)], choices[row, ],
        summarize_path(run$daily$value, "choice", run$trades, run$fees_paid)[, -1],
        average_bitcoin_weight = mean(run$daily$bitcoin_weight))
}))
print(risk_choices[, c("risk_level", "maximum_bitcoin_weight", "final_value", "annual_volatility",
                       "sharpe_ratio", "max_drawdown")], digits = 3, row.names = FALSE)
write.csv(risk_choices, "output/risk_choices.csv", row.names = FALSE)
