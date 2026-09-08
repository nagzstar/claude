# Measurement — make the next retrospective free

## What is recorded (patch 04)

`pm-run-issue.sh` appends one line per run to `NGM_ROOT/.agent-context/pm-runs/metrics.csv`:

```
issue,ts,ended,model,outcome,turns,wall_s,cost_usd,out_tokens,cache_create,cache_read,denials,agent_calls,models
```
`outcome` ∈ ready-for-prod | needs-decision | blocked | incomplete | session-limit, with
`/no-result` appended when no JSON was written. `wall_s` is log-line based (never `duration_ms`).
A rerun is the same `issue` with a later `ts`; `rerun-of` is therefore derivable and not stored.
The file is gitignored with the rest of `pm-runs/`; the PM pastes the printed row into #31.

## `retro/metrics.js` (new file in this repo; no dependencies)

```js
#!/usr/bin/env node
// Prints the Step-1 tables from pm-runs/*.json and metrics.csv. Usage:
//   node retro/metrics.js [--since YYYY-MM-DD] [--issue N] [--csv]
// Per issue: runs, first-run outcome, cost, out/cache-create/cache-read by model, turns, wall,
// denials, agent calls; totals and per-model cost split; the #31 row for --issue.
const fs = require('fs'), path = require('path');
const dir = path.join(process.env.NGM_ROOT || 'C:/Users/nagaj/git/ngm.app', '.agent-context/pm-runs');
const args = process.argv.slice(2); const opt = (k) => { const i = args.indexOf(k); return i >= 0 ? args[i + 1] : null; };
const since = opt('--since') || '0000', only = opt('--issue');
const k = n => n == null ? '' : n >= 1e6 ? (n / 1e6).toFixed(2) + 'M' : n >= 1e3 ? Math.round(n / 1e3) + 'K' : String(n);
const csv = fs.existsSync(path.join(dir, 'metrics.csv')) ? fs.readFileSync(path.join(dir, 'metrics.csv'), 'utf8').trim().split('\n').slice(1).map(l => l.split(',')) : [];
const runs = {};
for (const f of fs.readdirSync(dir)) {
  const m = f.match(/^issue-(\d+)-(\d{8}T\d{6}Z)\.(json|log)$/); if (!m || m[2].slice(0, 8) < since.replace(/-/g, '')) continue;
  const r = runs[`${m[1]}-${m[2]}`] ||= { issue: +m[1], ts: m[2] };
  if (m[3] === 'json') { const j = JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8')); r.cost = j.total_cost_usd; r.turns = j.num_turns; r.denials = (j.permission_denials || []).length; r.models = {}; for (const [mm, u] of Object.entries(j.modelUsage || {})) r.models[mm] = { out: u.outputTokens, cc: u.cacheCreationInputTokens, cr: u.cacheReadInputTokens, cost: u.costUSD }; }
  if (m[3] === 'log') { const L = fs.readFileSync(path.join(dir, f), 'utf8').split('\n'); const ts = L.filter(l => /^\d\d:\d\d:\d\d /.test(l)); const s = t => { const [h, mi, x] = t.split(':').map(Number); return h * 3600 + mi * 60 + x; }; r.wall = ts.length ? (s(ts[ts.length - 1].slice(0, 8)) - s(ts[0].slice(0, 8)) + 86400) % 86400 : 0; r.agents = ts.filter(l => / TOOL Agent /.test(l)).length; r.limit = /session limit/i.test(L.join('\n')); r.bg = /Background tasks still running/.test(L.join('\n')); r.result = ts.some(l => / RESULT /.test(l)); }
  const c = csv.find(x => x[0] === m[1] && x[1] === m[2]); if (c) r.outcome = c[4];
}
const byIssue = {};
for (const r of Object.values(runs).sort((a, b) => a.ts.localeCompare(b.ts))) {
  if (only && String(r.issue) !== only) continue;
  const b = byIssue[r.issue] ||= { issue: r.issue, runs: 0, first: null, cost: 0, turns: 0, wall: 0, denials: 0, agents: 0, models: {} };
  b.runs++; b.first ||= r.outcome || (r.limit ? 'session-limit' : !r.result ? 'no-result' : r.bg ? 'delivered/bg-kill' : 'ok');
  b.cost += r.cost || 0; b.turns += r.turns || 0; b.wall += r.wall || 0; b.denials += r.denials || 0; b.agents += r.agents || 0;
  for (const [mm, u] of Object.entries(r.models || {})) { const x = b.models[mm] ||= { out: 0, cc: 0, cr: 0, cost: 0 }; x.out += u.out; x.cc += u.cc; x.cr += u.cr; x.cost += u.cost; }
}
const rows = Object.values(byIssue);
console.log('| issue | runs | first run | cost $ | ' + ['opus', 'sonnet', 'fable', 'haiku'].map(m => m + ' out/cc/cr').join(' | ') + ' | turns | wall min | denials | agent calls |');
console.log('|' + '---|'.repeat(11));
const pick = (b, name) => { const e = Object.entries(b.models).find(([m]) => m.includes(name)); return e ? `${k(e[1].out)}/${k(e[1].cc)}/${k(e[1].cr)}` : '-'; };
for (const b of rows) console.log(`| #${b.issue} | ${b.runs} | ${b.first} | ${b.cost.toFixed(2)} | ${['opus', 'sonnet', 'fable', 'haiku'].map(n => pick(b, n)).join(' | ')} | ${b.turns} | ${Math.round(b.wall / 60)} | ${b.denials} | ${b.agents} |`);
const tot = rows.reduce((a, b) => { a.cost += b.cost; a.runs += b.runs; a.lost += b.first && !/^ok|ready/.test(b.first) ? 1 : 0; return a; }, { cost: 0, runs: 0, lost: 0 });
console.log(`\nissues ${rows.length} · runs ${tot.runs} · first-run not delivered ${tot.lost} · cost $${tot.cost.toFixed(2)} · per issue $${(tot.cost / Math.max(rows.length, 1)).toFixed(2)}`);
const mt = {}; for (const b of rows) for (const [m, u] of Object.entries(b.models)) { const x = mt[m] ||= { out: 0, cc: 0, cr: 0, cost: 0 }; x.out += u.out; x.cc += u.cc; x.cr += u.cr; x.cost += u.cost; }
const tc = Object.values(mt).reduce((a, x) => a + x.cost, 0);
for (const [m, x] of Object.entries(mt)) console.log(`${m}: out ${k(x.out)} cc ${k(x.cc)} cr ${k(x.cr)} cost $${x.cost.toFixed(2)} (${Math.round(100 * x.cost / tc)}%)`);
if (only) { const b = rows[0]; if (b) console.log(`\n#31 row: | #${b.issue} | runs ${b.runs} | ${b.first} | $${b.cost.toFixed(2)} | out ${k(Object.values(b.models).reduce((a, u) => a + u.out, 0))} | cc ${k(Object.values(b.models).reduce((a, u) => a + u.cc, 0))} | cr ${k(Object.values(b.models).reduce((a, u) => a + u.cr, 0))} | ${Math.round(b.wall / 60)} min | ${b.agents} agents |`); }
```

Add to `validate.sh` section 5: `node -e 'require("./retro/metrics.js")' --help` is not needed;
just `node --check retro/metrics.js && ok`.

## Targets for the next ten issues (measured by `metrics.js --since <date>`)

| metric | baseline (10 delivered issues, 16 runs) | target |
|---|---|---|
| first-run delivered (no lost run) | 6 of 11 issues (55 %); F-run 5/16 | ≥ 9 of 10; F-run ≤ 1/10 |
| cost per delivered issue (list) | $28 (median $25) | ≤ $18 |
| output tokens per issue | 317 K | ≤ 220 K |
| cache-create per issue | 1.3 M | ≤ 0.9 M |
| cache-read per issue | 35 M | ≤ 24 M (orchestrator ≤ 35 tool calls) |
| orchestrator tool calls per run | 66 | ≤ 35 |
| correction rounds per issue | 1.1 | ≤ 1.0, none re-spawned |
| security FAIL rounds | 5 in 10 issues | ≤ 3 (designs reviewed before code) |
| escaped defects | 6 in 10 issues | ≤ 3 |
| `ready` → run start (median) | 4.1 h | ≤ 30 min with `--queue` |
| run wall (tier 3, median) | 55 min | ≤ 45 min |
| `ready-for-prod` → RELEASED (median) | 4.4 h | unchanged (your decision); release procedure ≤ 3 min |
| heredoc failures / bg kills / limit deaths | 4 / 4 / 1 | 0 / 0 / detected with exit 3 |
| lessons.md size | 750 lines | ≤ 120 (index) |
| PM session cost per day (list) | ≈ $129 | ≤ $40 |

## How #31 is updated

Keep #31 as the human-readable record: after each run the PM pastes the `#31 row` that
`node retro/metrics.js --issue <n>` prints (one line), and at each retrospective a comment links
`retro/<date>/SUMMARY.md` with the targets table above. The 2026-09-07 "Experiment: Fable for the
thinkers" comment on #31 gets its verdict from `metrics.js --since 2026-09-08` after two batches:
architect cost per design, correction rounds and security FAILs, compared with this baseline.
