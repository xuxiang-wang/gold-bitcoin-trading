// Assembles website/index.html from the template, the engine and the contest data.
// Run from the project folder:  node website/build.js
const fs = require("fs");

function readCsv(path) {
  return fs.readFileSync(path, "utf8").trim().split(/\r?\n/).slice(1).map(line => line.split(","));
}
function isoDate(mdy) {
  const [m, d, y] = mdy.split("/").map(Number);
  return `20${String(y).padStart(2, "0")}-${String(m).padStart(2, "0")}-${String(d).padStart(2, "0")}`;
}
const data = {
  bitcoin: readCsv("data/BCHAIN-MKPRU.csv").map(r => [isoDate(r[0]), Number(r[1])]),
  gold: readCsv("data/LBMA-GOLD.csv").map(r => [isoDate(r[0]), r[1] === "" || r[1] === undefined ? null : Number(r[1])])
};

const engine = fs.readFileSync("website/engine.js", "utf8").replace(/if \(typeof module[^\n]*\n/, "");
const page = fs.readFileSync("website/page_template.html", "utf8")
  .replace("/*DATA*/", `const PRICE_DATA = ${JSON.stringify(data)};`)
  .replace("/*ENGINE*/", engine);
fs.writeFileSync("website/index.html", page);
console.log("wrote website/index.html", (page.length / 1024).toFixed(0), "KB");
