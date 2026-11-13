# 2022 MCM Problem C: Trading Strategies
# Step 1. Read the two price files provided by COMAP and put them on one daily calendar.
#
# Bitcoin trades every day; gold trades only on days with an LBMA price.
# A blank gold price (for example 12/23/16) is treated as a day the gold market is closed.

library(dplyr)

bitcoin <- read.csv("data/BCHAIN-MKPRU.csv")
gold <- read.csv("data/LBMA-GOLD.csv")

bitcoin$Date <- as.Date(bitcoin$Date, format = "%m/%d/%y")
gold$Date <- as.Date(gold$Date, format = "%m/%d/%y")
names(bitcoin) <- c("date", "bitcoin_price")
names(gold) <- c("date", "gold_price")

prices <- left_join(bitcoin, gold, by = "date")

# Gold can be traded only when the market published a price that day.
prices$gold_tradable <- !is.na(prices$gold_price)

# For valuing the portfolio on closed days, carry the last gold price forward.
# Before the first gold price (9/11/2016) gold cannot be held, so it stays NA.
prices$gold_price <- zoo::na.locf(prices$gold_price, na.rm = FALSE)

# Daily simple returns on the calendar grid (gold return is 0 on closed days).
prices$bitcoin_return <- c(NA, diff(prices$bitcoin_price) / head(prices$bitcoin_price, -1))
prices$gold_return <- c(NA, diff(prices$gold_price) / head(prices$gold_price, -1))
prices$gold_return[is.na(prices$gold_return)] <- 0

summary(prices)
cat("Days:", nrow(prices), " Gold trading days:", sum(prices$gold_tradable), "\n")
cat("Period:", format(min(prices$date)), "to", format(max(prices$date)), "\n")

dir.create("output", showWarnings = FALSE)
saveRDS(prices, "output/prices.rds")
write.csv(prices, "output/prices.csv", row.names = FALSE)   # read by 03_lstm_forecasts.py
