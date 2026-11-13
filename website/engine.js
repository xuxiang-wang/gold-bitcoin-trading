// Backtest engine for the 2022 MCM trading problem.
// A line-by-line port of run_strategy() in 02_backtest.R and the adaptive rule in
// 05_risk_choices_and_adaptive.R, checked against the R results (see validate.js).

function preparePrices(bitcoinRows, goldRows) {
  // bitcoinRows: [[date, price], ...] every day; goldRows: [[date, price or null], ...] market days
  const goldByDate = new Map(goldRows.map(r => [r[0], r[1]]));
  const n = bitcoinRows.length;
  const date = [], bitcoinPrice = [], goldPrice = [], goldTradable = [], bitcoinReturn = [], goldReturn = [];
  let lastGold = null;
  for (let i = 0; i < n; i++) {
    const d = bitcoinRows[i][0];
    date.push(d);
    bitcoinPrice.push(bitcoinRows[i][1]);
    const g = goldByDate.has(d) ? goldByDate.get(d) : null;
    goldTradable.push(g !== null && g !== undefined);
    if (g !== null && g !== undefined) lastGold = g;
    goldPrice.push(lastGold);
  }
  for (let i = 0; i < n; i++) {
    bitcoinReturn.push(i === 0 ? 0 : (bitcoinPrice[i] - bitcoinPrice[i - 1]) / bitcoinPrice[i - 1]);
    goldReturn.push(i === 0 || goldPrice[i - 1] === null ? 0 : (goldPrice[i] - goldPrice[i - 1]) / goldPrice[i - 1]);
  }
  return { date, bitcoinPrice, goldPrice, goldTradable, bitcoinReturn, goldReturn, n };
}

// Minimize 0.5 w'Dw - d'w over w in R^2 subject to rows a.w >= b (the first `equalities` rows hold with
// equality). D is positive definite, so the optimum is the best feasible point among the minimizers on
// every active set of size 0, 1 or 2.
function solveQP2(D, d, A, b, equalities) {
  const det = D[0][0] * D[1][1] - D[0][1] * D[1][0];
  const inv = [[D[1][1] / det, -D[0][1] / det], [-D[1][0] / det, D[0][0] / det]];
  const mul = (M, v) => [M[0][0] * v[0] + M[0][1] * v[1], M[1][0] * v[0] + M[1][1] * v[1]];
  const f = w => 0.5 * (w[0] * (D[0][0] * w[0] + D[0][1] * w[1]) + w[1] * (D[1][0] * w[0] + D[1][1] * w[1])) - d[0] * w[0] - d[1] * w[1];
  const m = A.length;
  const feasible = w => {
    for (let i = 0; i < m; i++) {
      const s = A[i][0] * w[0] + A[i][1] * w[1] - b[i];
      const tol = 1e-10 * (1 + Math.abs(b[i]));
      if (i < equalities ? Math.abs(s) > tol : s < -tol) return false;
    }
    return true;
  };
  const candidates = [];
  if (equalities === 0) candidates.push(mul(inv, d));
  const free = d0 => mul(inv, d0);
  for (let i = 0; i < m; i++) {
    if (equalities > 0 && i !== 0) continue;
    const a = A[i];
    const Ainv_a = mul(inv, a), Ainv_d = mul(inv, d);
    const denom = a[0] * Ainv_a[0] + a[1] * Ainv_a[1];
    if (denom === 0) continue;
    const lambda = (b[i] - (a[0] * Ainv_d[0] + a[1] * Ainv_d[1])) / denom;
    candidates.push(free([d[0] + lambda * a[0], d[1] + lambda * a[1]]));
  }
  for (let i = 0; i < m; i++) {
    for (let j = i + 1; j < m; j++) {
      if (equalities > 0 && i !== 0) continue;
      const a = A[i], c = A[j];
      const dt = a[0] * c[1] - a[1] * c[0];
      if (Math.abs(dt) < 1e-14) continue;
      candidates.push([(b[i] * c[1] - a[1] * b[j]) / dt, (a[0] * b[j] - b[i] * c[0]) / dt]);
    }
  }
  let best = null, bestValue = Infinity;
  for (const w of candidates) {
    if (!feasible(w)) continue;
    const v = f(w);
    if (v < bestValue) { bestValue = v; best = w; }
  }
  return best === null ? null : { solution: best, value: bestValue };
}

function runStrategy(P, options) {
  const o = Object.assign({ riskAversion: 5, halfLifeMean: 30, horizon: 30, maximumBitcoinWeight: 1,
    costMultiplier: 1, halfLifeCovariance: 30, warmUpDays: 30 }, options);
  const n = P.n;
  const halfLife = Array.isArray(o.halfLifeMean) ? o.halfLifeMean : new Array(n).fill(o.halfLifeMean);
  const horizon = Array.isArray(o.horizon) ? o.horizon : new Array(n).fill(o.horizon);
  const goldCost = 0.01 * o.costMultiplier, bitcoinCost = 0.02 * o.costMultiplier;
  const cost = [goldCost, bitcoinCost];
  const halfLives = [...new Set(halfLife)];
  const decayMean = halfLives.map(h => Math.pow(0.5, 1 / h));
  const decayCov = Math.pow(0.5, 1 / o.halfLifeCovariance);
  let cash = 1000, goldOunces = 0, bitcoins = 0;
  const meanReturn = halfLives.map(() => [0, 0]);
  let cov = [[1e-4, 0], [0, 1e-4]];
  const value = new Array(n), goldWeight = new Array(n), bitcoinWeight = new Array(n);
  let feesPaid = 0, trades = 0;

  for (let day = 0; day < n; day++) {
    const gp = P.goldPrice[day], bp = P.bitcoinPrice[day];
    let v = cash + bitcoins * bp + (gp === null ? 0 : goldOunces * gp);
    if (day > 0) {
      const r = [P.goldReturn[day], P.bitcoinReturn[day]];
      for (let k = 0; k < halfLives.length; k++) {
        meanReturn[k] = [meanReturn[k][0] * decayMean[k] + r[0] * (1 - decayMean[k]),
                         meanReturn[k][1] * decayMean[k] + r[1] * (1 - decayMean[k])];
      }
      cov = [[decayCov * cov[0][0] + (1 - decayCov) * (r[0] * r[0]), decayCov * cov[0][1] + (1 - decayCov) * (r[0] * r[1])],
             [decayCov * cov[1][0] + (1 - decayCov) * (r[1] * r[0]), decayCov * cov[1][1] + (1 - decayCov) * (r[1] * r[1])]];
    }
    if (day + 1 > o.warmUpDays) {
      const current = [Math.max(0, gp === null ? 0 : goldOunces * gp / v), Math.max(0, bitcoins * bp / v)];
      const mu = meanReturn[halfLives.indexOf(halfLife[day])];
      const H = horizon[day];
      const D = [[o.riskAversion * H * cov[0][0] + 1e-10, o.riskAversion * H * cov[0][1]],
                 [o.riskAversion * H * cov[1][0], o.riskAversion * H * cov[1][1] + 1e-10]];
      let bestObjective = Infinity, target = null;
      for (const gd of (P.goldTradable[day] ? [1, -1] : [0])) {
        for (const bd of [1, -1]) {
          const dir = [gd, bd];
          const cap = o.maximumBitcoinWeight;
          const A = [[dir[0], 0], [0, dir[1]], [-(1 + cost[0] * dir[0]), -(1 + cost[1] * dir[1])], [1, 0], [0, 1],
                     [-(cap * cost[0] * dir[0]), -(1 + cap * cost[1] * dir[1])]];
          const b = [dir[0] * current[0], dir[1] * current[1],
                     -Math.max(1, current[0] + current[1]) - (cost[0] * dir[0] * current[0] + cost[1] * dir[1] * current[1]) - 1e-9,
                     0, 0, -cap * (1 + cost[0] * dir[0] * current[0] + cost[1] * dir[1] * current[1]) - 1e-9];
          let eq = 0;
          if (gd === 0) { A[0] = [1, 0]; b[0] = current[0]; eq = 1; }
          const fit = solveQP2(D, [H * mu[0] - cost[0] * dir[0], H * mu[1] - cost[1] * dir[1]], A, b, eq);
          if (fit === null) continue;
          const objective = fit.value - (cost[0] * dir[0] * current[0] + cost[1] * dir[1] * current[1]);
          if (objective < bestObjective) { bestObjective = objective; target = fit.solution; }
        }
      }
      let goldTrade = (target[0] - current[0]) * v;
      let bitcoinTrade = (target[1] - current[1]) * v;
      if (Math.abs(goldTrade) < 0.01) goldTrade = 0;
      if (Math.abs(bitcoinTrade) < 0.01) bitcoinTrade = 0;
      const fees = goldCost * Math.abs(goldTrade) + bitcoinCost * Math.abs(bitcoinTrade);
      if (goldTrade !== 0) goldOunces = Math.max(0, goldOunces + goldTrade / gp);
      if (bitcoinTrade !== 0) bitcoins = Math.max(0, bitcoins + bitcoinTrade / bp);
      cash = cash - goldTrade - bitcoinTrade - fees;
      feesPaid += fees;
      trades += (goldTrade !== 0) + (bitcoinTrade !== 0);
      v = v - fees;
    }
    value[day] = v;
    goldWeight[day] = gp === null ? 0 : goldOunces * gp / v;
    bitcoinWeight[day] = bitcoins * bp / v;
  }
  return { value, goldWeight, bitcoinWeight, feesPaid, trades };
}

// Settings re-chosen every day: among 12 candidate (half-life, horizon) pairs, follow the one whose
// paper portfolio grew most over the past `lookback` days.
const CANDIDATES = [];
for (const H of [10, 30, 60]) for (const h of [14, 30, 60, 120]) CANDIDATES.push({ halfLifeMean: h, horizon: H });

function runAdaptive(P, options, lookback = 180) {
  const paper = CANDIDATES.map(c => runStrategy(P, Object.assign({}, options, c)).value);
  const defaultIndex = CANDIDATES.findIndex(c => c.halfLifeMean === 30 && c.horizon === 30);
  const chosen = new Array(P.n);
  for (let t = 0; t < P.n; t++) {
    if (t < lookback) { chosen[t] = defaultIndex; continue; }
    let best = -Infinity, index = defaultIndex;
    for (let c = 0; c < CANDIDATES.length; c++) {
      const g = Math.log(paper[c][t] / paper[c][t - lookback]);
      if (g > best) { best = g; index = c; }
    }
    chosen[t] = index;
  }
  const run = runStrategy(P, Object.assign({}, options, {
    halfLifeMean: chosen.map(i => CANDIDATES[i].halfLifeMean),
    horizon: chosen.map(i => CANDIDATES[i].horizon)
  }));
  run.chosen = chosen;
  run.paperFinal = paper.map(p => p[P.n - 1]);
  return run;
}

function buyAndHold(P, costMultiplier, goldShare) {
  // goldShare 0 = all bitcoin from day 1; 1 = all gold from the first gold day; 0.5 = half each on the first gold day
  const first = P.goldTradable.indexOf(true);
  const gc = 1 + 0.01 * costMultiplier, bc = 1 + 0.02 * costMultiplier;
  return P.bitcoinPrice.map((bp, t) => {
    if (goldShare === 0) return 1000 / bc / P.bitcoinPrice[0] * bp;
    if (t < first) return 1000;
    return 1000 * goldShare / gc / P.goldPrice[first] * P.goldPrice[t] +
           1000 * (1 - goldShare) / bc / P.bitcoinPrice[first] * bp;
  });
}

function summarize(value) {
  const r = [];
  for (let i = 1; i < value.length; i++) r.push((value[i] - value[i - 1]) / value[i - 1]);
  const mean = r.reduce((a, x) => a + x, 0) / r.length;
  const sd = Math.sqrt(r.reduce((a, x) => a + (x - mean) ** 2, 0) / (r.length - 1));
  let peak = -Infinity, drawdown = 0;
  for (const x of value) { peak = Math.max(peak, x); drawdown = Math.max(drawdown, 1 - x / peak); }
  const years = (value.length - 1) / 365;
  return { finalValue: value[value.length - 1], annualGrowth: Math.pow(value[value.length - 1] / 1000, 1 / years) - 1,
           annualVolatility: sd * Math.sqrt(365), sharpe: mean / sd * Math.sqrt(365), maxDrawdown: drawdown };
}

if (typeof module !== "undefined") module.exports = { preparePrices, runStrategy, runAdaptive, buyAndHold, summarize, solveQP2 };
