# 2022 MCM Problem C: Trading Strategies
# Step 4a. LSTM forecasts of daily returns, trained with past data only (walk-forward).
# Run before 04_compare_methods.R.
#
# LSTM forecasting is a common choice for this problem. This step builds it under the
# same no-hindsight rule as everything else, so it can replace the momentum estimate in the strategy.
# R's torch package cannot be installed in the environment used for this analysis, so this one step
# is written in Python (PyTorch). It reads output/prices.csv from 01_prepare_data.R and writes
# output/lstm_forecasts.csv for 04_compare_methods.R.
#
# Design, fixed before any results were seen:
#   Input       the last 30 daily returns of gold and bitcoin (2 features x 30 days)
#   Targets     (a) next-day return; (b) average daily return over the next 30 days
#               (b matches the strategy's 30-day horizon)
#   Model       one LSTM layer with 16 units, then a linear layer to 2 outputs (gold, bitcoin)
#   Training    Adam, learning rate 0.001, batches of 64, mean squared error on standardized
#               returns; the last 20% of each training window (by date) is held out for early
#               stopping (patience 20, at most 200 epochs); average of 3 models with different seeds
#   Walk-forward first fit on day 181, refit every 30 days. A model fitted on day T is used for
#               days T to T+29, and is trained only on samples whose target was known by day T.
#               Before day 181 there is no forecast and the strategy uses the momentum estimate.

import numpy as np
import pandas as pd
import torch

prices = pd.read_csv("output/prices.csv")
returns = prices[["gold_return", "bitcoin_return"]].fillna(0).to_numpy()
days = len(returns)
window = 30
first_fit = 180          # 0-based day index (the 181st day)
refit_every = 30
seeds = [1, 2, 3]
torch.set_num_threads(2)


class Forecaster(torch.nn.Module):
    def __init__(self):
        super().__init__()
        self.lstm = torch.nn.LSTM(input_size=2, hidden_size=16, batch_first=True)
        self.output = torch.nn.Linear(16, 2)

    def forward(self, sequence):
        hidden, _ = self.lstm(sequence)
        return self.output(hidden[:, -1, :])


def features_ending_at(day):
    return returns[day - window + 1: day + 1]


def target_for(day, horizon):
    return returns[day + 1: day + 1 + horizon].mean(axis=0)


def fit_and_forecast(fit_day, horizon, forecast_days):
    # Samples whose whole target window ends on or before the fit day.
    sample_days = np.arange(window, fit_day - horizon + 1)
    inputs = np.stack([features_ending_at(day) for day in sample_days])
    targets = np.stack([target_for(day, horizon) for day in sample_days])
    input_mean, input_sd = inputs.reshape(-1, 2).mean(axis=0), inputs.reshape(-1, 2).std(axis=0)
    target_mean, target_sd = targets.mean(axis=0), targets.std(axis=0)
    inputs = (inputs - input_mean) / input_sd
    targets = (targets - target_mean) / target_sd
    split = int(len(sample_days) * 0.8)
    train_x, train_y = torch.tensor(inputs[:split], dtype=torch.float32), torch.tensor(targets[:split], dtype=torch.float32)
    valid_x, valid_y = torch.tensor(inputs[split:], dtype=torch.float32), torch.tensor(targets[split:], dtype=torch.float32)
    new_x = torch.tensor((np.stack([features_ending_at(day) for day in forecast_days]) - input_mean) / input_sd,
                         dtype=torch.float32)

    forecasts = []
    for seed in seeds:
        torch.manual_seed(seed)
        model = Forecaster()
        optimizer = torch.optim.Adam(model.parameters(), lr=0.001)
        best_loss, best_state, waited = np.inf, None, 0
        for epoch in range(200):
            model.train()
            order = torch.randperm(len(train_x))
            for start in range(0, len(train_x), 64):
                batch = order[start: start + 64]
                optimizer.zero_grad()
                loss = torch.nn.functional.mse_loss(model(train_x[batch]), train_y[batch])
                loss.backward()
                optimizer.step()
            model.eval()
            with torch.no_grad():
                valid_loss = torch.nn.functional.mse_loss(model(valid_x), valid_y).item()
            if valid_loss < best_loss:
                best_loss, best_state, waited = valid_loss, {k: v.clone() for k, v in model.state_dict().items()}, 0
            else:
                waited += 1
                if waited >= 20:
                    break
        model.load_state_dict(best_state)
        model.eval()
        with torch.no_grad():
            forecasts.append(model(new_x).numpy() * target_sd + target_mean)
    return np.mean(forecasts, axis=0)


output = pd.DataFrame({"date": prices["date"]})
for name, horizon in [("next_day", 1), ("next_30_days", 30)]:
    forecast = np.full((days, 2), np.nan)
    for fit_day in range(first_fit, days, refit_every):
        forecast_days = np.arange(fit_day, min(fit_day + refit_every, days))
        forecast[forecast_days] = fit_and_forecast(fit_day, horizon, forecast_days)
        print(name, "fit on day", fit_day + 1, flush=True)
    output[f"gold_{name}"] = forecast[:, 0]
    output[f"bitcoin_{name}"] = forecast[:, 1]

output.to_csv("output/lstm_forecasts.csv", index=False)
print("wrote output/lstm_forecasts.csv")
