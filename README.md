# Trading Gold and Bitcoin Without Hindsight

**2022 MCM Problem C.** A reproducible analysis built from the public contest data. The README follows the order of the analysis; each step has its own script.

**Interactive page:** https://xuxiang-wang.github.io/projects/gold-bitcoin/


## 1. The problem and its rules

A trader starts with $1,000 on 9/11/2016 and may hold cash, gold, and bitcoin until 9/10/2021. The contest asked for:

- the best daily trading strategy;
- evidence that it is the best;
- how much transaction costs matter.

Every strategy here, benchmarks included, follows the same rules:

- **No hindsight.** The decision on day *t* uses only prices up to and including day *t*, and trades at day *t*'s price.
- **Market days.** Gold trades only on days the London market publishes a price; bitcoin trades every day.
- **Commissions.** Each purchase or sale costs 1% of the amount for gold and 2% for bitcoin.
- **Valuation.** The portfolio is valued at market prices on 9/10/2021.

"Best" is judged on both final value and risk: annual volatility, Sharpe ratio, and maximum drawdown, the largest fall from a previous peak.

## 2. The data (`01_prepare_data.R`)

- **Bitcoin** has a price on all 1,826 days.
- **Gold** has 1,265 rows. Ten of them are blank, around Christmas and New Year, which leaves 1,255 trading days.

**How the calendar is built:**

- The calendar is bitcoin's.
- Gold is tradable only on days with a price. On other days, holdings are valued at the last gold price.
- Blanks are not interpolated, because interpolation would use the next day's price.
- On 9/11/2016 there is no gold price yet, so gold cannot be held that day.

## 3. Benchmarks (`02_benchmarks.R`)

Simple choices under the same rules set the standard. A perfect-foresight bound shows what hindsight would buy. With proportional commissions, the best hindsight portfolio is always fully in one asset, so dynamic programming over three states (cash, gold, bitcoin) gives the exact maximum.

| Benchmark | Value on 9/10/2021 | Sharpe ratio | Max drawdown |
|---|---:|---:|---:|
| Hold cash | $1,000 | | 0% |
| Buy and hold gold | $1,341 | 0.50 | 19% |
| Buy and hold bitcoin | $73,127 | 1.49 | 83% |
| Buy and hold 50/50 | $37,953 | 1.38 | 81% |
| 50-day trend following | $12,876 | 1.23 | 74% |
| Perfect foresight (not achievable) | $33.7 billion | | |

Bitcoin rose about 75-fold, so buying and holding it is a very high bar for final value. The hindsight bound shows why very large reported results usually mean future prices leaked into the decisions.

## 4. Comparing methods (`03_lstm_forecasts.py`, `04_compare_methods.R`)

**The strategy (`strategy.R`).** The method is a cost-aware mean-variance allocation:

- **Estimates.** Each day the strategy estimates each asset's expected daily return and a covariance matrix.
- **Objective.** It chooses weights to maximize *horizon × expected return − (risk aversion / 2) × horizon × variance − commissions*.
- **Constraints.** No short selling and no borrowing.
- **Why it rarely trades.** The commission is paid once, but the expected gain builds up over the 30-day horizon, so the strategy trades only when the expected benefit exceeds the cost.
- **Exact solution.** The commission makes the objective kinked at the current position. Each day is therefore solved as up to four smooth quadratic programs, one for each buy/sell direction per asset, and the best is kept.

**Two candidates for the expected return.** Both were set up before any results were seen:

- **Momentum.** An exponentially weighted mean of past returns with a 30-day half-life.
- **LSTM.** A neural-network forecast, a common choice for this problem. Here it is built without hindsight:
  - input: the last 30 days of gold and bitcoin returns;
  - targets: either the next day's return or the average return over the next 30 days;
  - model: one LSTM layer with 16 units, averaged over 3 seeds;
  - training: walk-forward, refit every 30 days from day 181, using only samples whose outcome was already known on the fit day.

**Forecast accuracy (days 181 onward, out of sample).** R² is measured against always forecasting zero:

| Target | Asset | LSTM R² | Momentum R² | LSTM direction right | Days the price rose | Diebold-Mariano p |
|---|---|---:|---:|---:|---:|---:|
| Next day | Gold | −0.1% | −1.3% | 53% | 53% | 0.06 |
| Next day | Bitcoin | −0.5% | −0.1% | 54% | 54% | 0.62 |
| Next 30 days | Gold | −5.4% | −33% | 41% | 54% | 0.04 |
| Next 30 days | Bitcoin | 3.1% | −6.5% | 60% | 63% | 0.36 |

Neither method forecasts daily returns better than zero, and neither picks direction better than always guessing "up". The 30-day LSTM forecast for bitcoin was positive on 97% of days: it learned bitcoin's upward drift, not when to trade.

**Strategy results.** Risk aversion is 5; everything else is identical across the three rows.

| Expected-return estimate | Final value | Sharpe | Max drawdown | Trades |
|---|---:|---:|---:|---:|
| **Momentum** | **$21,064** | **1.50** | **46%** | 504 |
| LSTM, next day | $1,532 | 0.43 | 75% | 903 |
| LSTM, next 30 days | $7,937 | 1.14 | 68% | 453 |

Momentum beat both LSTM versions on final value and Sharpe ratio at four of five risk levels. The exception was the most aggressive level, risk aversion 1: there the 30-day LSTM ended higher, $48,410 against $32,785. It got there by holding bitcoin almost all the time (96% on average), and it had bitcoin's 83% drawdown and a lower Sharpe ratio. **Momentum is the method used from here on.**

**The chosen method against the benchmarks:**

| Strategy | Value on 9/10/2021 | Annual growth | Annual volatility | Sharpe ratio | Max drawdown | Trades |
|---|---:|---:|---:|---:|---:|---:|
| Cost-aware mean-variance, momentum | $21,064 | 84% | 48% | 1.50 | 46% | 504 |
| Buy and hold bitcoin | $73,127 | 136% | 79% | 1.49 | 83% | 1 |

The strategy did not beat holding bitcoin on final value. It cut the drawdown about in half and the volatility by about 40%, at almost the same return per unit of risk. It controls risk; it shows no evidence of predicting returns.

## 5. Settings the trader chooses (`05_user_choices.R`)

Two settings express the trader's preferences, so they are left to the trader, on the website as well:

- **Risk tolerance:** six levels, risk aversion 1 to 50.
- **Bitcoin cap:** a hard limit on bitcoin's share of the portfolio, applied after the day's commissions.

All 24 combinations trace a clear trade-off between final value and worst drop. For example:

| Risk tolerance | Bitcoin cap | Final value | Max drawdown |
|---|---:|---:|---:|
| Very aggressive | none | $32,785 | 73% |
| Moderate | none | $21,064 | 46% |
| Moderate | 50% | $5,520 | 37% |
| Most cautious | none | $1,553 | 9% |

The model's own settings, momentum half-life and horizon, are not offered as choices. Step 6 only checks how much the results depend on them.

## 6. Sensitivity (`06_sensitivity.R`)

**Commissions.** Both rates are scaled together:

| Commission multiple | 0× | 0.25× | 0.5× | 1× | 1.5× | 2× | 3× |
|---|---:|---:|---:|---:|---:|---:|---:|
| Final value | $50,736 | $36,567 | $29,400 | $21,064 | $14,366 | $11,548 | $7,289 |
| Trades | 1,327 | 921 | 713 | 504 | 412 | 331 | 257 |

**Model settings.** Across 60 combinations of risk aversion (1 to 20), momentum half-life (14 to 120 days), and horizon (10 to 60 days):

- final values ranged from $1,588 to $47,805, with a median of $9,864;
- none beat holding bitcoin on final value;
- 95% had a lower maximum drawdown;
- 7% had a higher Sharpe ratio;
- the pre-specified setting ranked 18th.

The best of the 60 was only knowable afterwards, so it is not a strategy. The conclusion about risk holds across settings; the size of the final value depends on them.

**Re-choosing settings every day.** The trader fixes the risk level. Each day the strategy then follows whichever of 12 signal settings grew most over the past 180 days, tracked as paper portfolios. This did worse than the fixed setting at every risk level:

| Risk tolerance | Fixed setting | Re-chosen daily | Median of the 12 | Best of the 12 (hindsight) |
|---|---:|---:|---:|---:|
| Very aggressive (1) | $32,785 | $22,812 | $27,763 | $47,805 |
| Aggressive (2) | $27,143 | $14,058 | $26,789 | $37,651 |
| Moderate (5) | $21,064 | $8,509 | $14,385 | $21,064 |
| Cautious (10) | $7,932 | $4,161 | $5,376 | $9,788 |
| Very cautious (20) | $3,025 | $2,610 | $2,430 | $3,694 |

Recent winners did not keep winning, and the switching added trades.

## 7. Checks (`07_checks.R`, `website/validate.js`)

Each check prints PASS or FAIL:

- **Optimizer.** The daily optimizer is never beaten by a brute-force grid on 300 random problems.
- **Market days.** Gold holdings never change on days the gold market is closed.
- **Weights.** They stay between 0 and 1, and the 30-day warm-up has no trades.
- **Bitcoin cap.** Bitcoin's share stays at or below the cap after each day's trading.
- **No look-ahead.** Changing every price after day 1000 leaves the first 1000 days identical.
- **LSTM training.** LSTM forecasts start on day 181 and use past data only.
- **Benchmark by hand.** Buy-and-hold bitcoin matches a hand calculation.

**Two problems the checks found and that are now fixed:**

- **Cap applied to the wrong value.** The bitcoin cap was applied to the portfolio before that day's commission, so after the fee bitcoin could sit up to 0.3 percentage points above it.
- **Rejected constraint.** On days the gold market was closed with no gold held, the solver rejected a redundant constraint and occasionally skipped a valid option. This changed 5 of the 60 settings in step 6 by up to 3%, all at risk aversion 1 or 2. The pre-specified result did not change.

The website's JavaScript engine is a port of `strategy.R`. Across 14 cases it matches the R results to within 2.2e-14, including trade counts.

## 8. Publishing (`08_figures.R`, `website/`)

`08_figures.R` draws the figures in `output/`. `website/index.html` shows only the chosen method. Visitors set the risk tolerance, the bitcoin cap, and the commission level, and the full backtest reruns in the browser against the buy-and-hold benchmarks.

## Limitations

- One five-year path, dominated by bitcoin's rise. No out-of-sample period exists within the contest data.
- Trading at the same day's price after seeing it is slightly optimistic.
- Gold's return is 0 on closed days, which understates gold's variance a little.

## How to run

R 4.3 or later with `dplyr`, `zoo`, `quadprog`, `ggplot2`, `tidyr`, `scales`, `sandwich`, `jsonlite`. Python 3 with `numpy`, `pandas`, `torch` for step 4a. Node.js for the website.

```
Rscript 01_prepare_data.R      # step 2: daily calendar
Rscript 02_benchmarks.R        # step 3: benchmarks and the perfect-foresight bound
python3 03_lstm_forecasts.py   # step 4a: walk-forward LSTM forecasts (about 15 minutes)
Rscript 04_compare_methods.R   # step 4: momentum vs LSTM; chosen method vs benchmarks
Rscript 05_user_choices.R      # step 5: risk tolerance x bitcoin cap
Rscript 06_sensitivity.R       # step 6: commissions, model settings, re-choosing daily
Rscript 07_checks.R            # step 7: checks
Rscript website/export_validation.R && node website/validate.js   # step 7: browser engine
Rscript 08_figures.R           # step 8: figures
node website/build.js          # step 8: website/index.html
```

`strategy.R` holds the shared strategy code that the steps source. All scripts run from this folder and write to `output/`. Apart from the LSTM step, everything runs in about two minutes. The LSTM step is in Python because R's torch package could not be installed in the environment used for this analysis.

## Data

The contest problem statements are not included here; they are published by the contest organizers.


`data/LBMA-GOLD.csv` and `data/BCHAIN-MKPRU.csv` are the files provided with the 2022 MCM Problem C (© COMAP). The contest restricted solutions to these two files.
