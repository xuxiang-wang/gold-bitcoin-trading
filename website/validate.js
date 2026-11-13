// Checks the JavaScript engine against the R results. Run from the project folder:
//   Rscript website/export_validation.R && node website/validate.js
const fs = require("fs");
const E = require("./engine.js");

function readCsv(path) {
  return fs.readFileSync(path, "utf8").trim().split(/\r?\n/).slice(1).map(line => line.split(","));
}
function isoDate(mdy) {
  const [m, d, y] = mdy.split("/").map(Number);
  return `20${String(y).padStart(2, "0")}-${String(m).padStart(2, "0")}-${String(d).padStart(2, "0")}`;
}
const bitcoin = readCsv("data/BCHAIN-MKPRU.csv").map(r => [isoDate(r[0]), Number(r[1])]);
const gold = readCsv("data/LBMA-GOLD.csv").map(r => [isoDate(r[0]), r[1] === "" || r[1] === undefined ? null : Number(r[1])]);
const P = E.preparePrices(bitcoin, gold);
const reference = JSON.parse(fs.readFileSync("website/validation.json", "utf8"));

let worst = 0;
for (const c of reference.cases) {
  const run = E.runStrategy(P, { riskAversion: c.risk_aversion, halfLifeMean: c.half_life_mean, horizon: c.horizon,
    maximumBitcoinWeight: c.maximum_bitcoin_weight, costMultiplier: c.cost_multiplier });
  const rel = Math.abs(run.value[P.n - 1] / Number(c.final) - 1);
  worst = Math.max(worst, rel);
  console.log(`fixed  ${JSON.stringify([c.risk_aversion, c.half_life_mean, c.horizon, c.maximum_bitcoin_weight, c.cost_multiplier])}`,
    `R ${Number(c.final).toFixed(4)} JS ${run.value[P.n - 1].toFixed(4)} trades R ${c.trades} JS ${run.trades}`);
}
for (const a of reference.adaptive) {
  const run = E.runAdaptive(P, { riskAversion: a.risk_aversion });
  const rel = Math.abs(run.value[P.n - 1] / a.adaptive_final_value - 1);
  worst = Math.max(worst, rel);
  console.log(`adaptive risk ${a.risk_aversion}: R ${a.adaptive_final_value.toFixed(4)} JS ${run.value[P.n - 1].toFixed(4)} trades R ${a.adaptive_trades} JS ${run.trades}`);
}
const bh = E.summarize(E.buyAndHold(P, 1, 0));
console.log("buy-and-hold bitcoin JS", bh.finalValue.toFixed(4), "R", reference.comparison[3].final_value);
console.log("largest relative difference:", worst.toExponential(2));
process.exit(worst < 1e-6 ? 0 : 1);
