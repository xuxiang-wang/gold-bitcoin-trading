# 2022 MCM Problem C: Trading Strategies
# Step 8. Figures for the write-up. (The website is built separately: node website/build.js.)
# Run steps 1-6 first.

library(ggplot2)
library(tidyr)

prices <- readRDS("output/prices.rds")
backtest <- readRDS("output/backtest.rds")
cost_sensitivity <- read.csv("output/cost_sensitivity.csv")

series_colors <- c("Cost-aware mean-variance" = "#2a78d6", "Buy and hold bitcoin" = "#eb6834",
                   "Buy and hold 50/50" = "#1baf7a", "Buy and hold gold" = "#eda100")

paths <- data.frame(
  date = prices$date,
  `Cost-aware mean-variance` = backtest$strategy$daily$value,
  `Buy and hold bitcoin` = backtest$bitcoin_hold,
  `Buy and hold 50/50` = backtest$half_and_half,
  `Buy and hold gold` = backtest$gold_hold,
  check.names = FALSE
)
long_paths <- pivot_longer(paths, -date, names_to = "strategy", values_to = "value")
long_paths$strategy <- factor(long_paths$strategy, levels = names(series_colors))

chart_theme <- theme_minimal(base_size = 11) +
  theme(panel.grid.minor = element_blank(), legend.position = "top", legend.title = element_blank())

ggplot(long_paths, aes(date, value, color = strategy)) +
  geom_line(linewidth = 0.6) +
  scale_y_log10(labels = scales::dollar) +
  scale_color_manual(values = series_colors) +
  labs(x = NULL, y = "Portfolio value (log scale)",
       title = "Value of $1,000, 9/11/2016 to 9/10/2021, after commissions") +
  chart_theme
ggsave("output/figure_portfolio_value.png", width = 8, height = 4.5, dpi = 200)

long_paths$drawdown <- ave(long_paths$value, long_paths$strategy, FUN = function(value) value / cummax(value) - 1)
ggplot(long_paths, aes(date, drawdown, color = strategy)) +
  geom_line(linewidth = 0.6) +
  scale_y_continuous(labels = scales::percent) +
  scale_color_manual(values = series_colors) +
  labs(x = NULL, y = "Drop from previous peak", title = "Drawdowns") +
  chart_theme
ggsave("output/figure_drawdown.png", width = 8, height = 4, dpi = 200)

allocation <- data.frame(date = prices$date,
                         Bitcoin = backtest$strategy$daily$bitcoin_weight,
                         Gold = backtest$strategy$daily$gold_weight)
allocation$Cash <- 1 - allocation$Bitcoin - allocation$Gold
long_allocation <- pivot_longer(allocation, -date, names_to = "holding", values_to = "weight")
long_allocation$holding <- factor(long_allocation$holding, levels = c("Bitcoin", "Gold", "Cash"))
ggplot(long_allocation, aes(date, weight, fill = holding)) +
  geom_area() +
  scale_fill_manual(values = c(Bitcoin = "#eb6834", Gold = "#eda100", Cash = "#c3c2b7")) +
  scale_y_continuous(labels = scales::percent) +
  labs(x = NULL, y = "Share of portfolio", title = "How the strategy allocated its money") +
  chart_theme
ggsave("output/figure_allocation.png", width = 8, height = 4, dpi = 200)

ggplot(cost_sensitivity, aes(factor(cost_multiplier), final_value)) +
  geom_col(fill = "#2a78d6", width = 0.6) +
  geom_text(aes(label = scales::dollar(round(final_value))), vjust = -0.4, size = 3.2) +
  scale_y_continuous(labels = scales::dollar, expand = expansion(mult = c(0, 0.1))) +
  labs(x = "Commission as a multiple of the contest rates (1 = 1% gold, 2% bitcoin)",
       y = "Value on 9/10/2021", title = "Higher commissions lower the final value") +
  chart_theme
ggsave("output/figure_cost_sensitivity.png", width = 8, height = 4, dpi = 200)
