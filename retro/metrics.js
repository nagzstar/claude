#!/usr/bin/env node
// Prints the retrospective baseline tables from NGM_ROOT/.agent-context/pm-runs/*.{json,log}
// and metrics.csv (written by pm-run-issue.sh). No dependencies.
//   node retro/metrics.js [--since YYYY-MM-DD] [--issue N]
// Per issue: runs, first-run outcome, cost, out/cache-create/cache-read by model, turns, wall,
// denials, agent calls; totals; per-model cost split; the #31 row for --issue.
const fs = require('fs'), path = require('path');
const dir = path.join(process.env.NGM_ROOT || 'C:/Users/nagaj/git/ngm.app', '.agent-context/pm-runs');
const args = process.argv.slice(2); const opt = k => { const i = args.indexOf(k); return i >= 0 ? args[i + 1] : null; };
const since = (opt('--since') || '0000-00-00').replace(/-/g, ''), only = opt('--issue');
const k = n => n == null ? '' : n >= 1e6 ? (n / 1e6).toFixed(2) + 'M' : n >= 1e3 ? Math.round(n / 1e3) + 'K' : String(n);
if (!fs.existsSync(dir)) { console.error('no pm-runs directory at ' + dir); process.exit(1); }
const csvPath = path.join(dir, 'metrics.csv');
const csv = fs.existsSync(csvPath) ? fs.readFileSync(csvPath, 'utf8').trim().split('\n').slice(1).map(l => l.split(',')) : [];
const runs = {};
for (const f of fs.readdirSync(dir)) {
  const m = f.match(/^issue-(\d+)-(\d{8}T\d{6}Z)\.(json|log)$/); if (!m || m[2].slice(0, 8) < since) continue;
  const r = runs[`${m[1]}-${m[2]}`] ||= { issue: +m[1], ts: m[2] };
  if (m[3] === 'json') {
    const j = JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8'));
    r.cost = j.total_cost_usd; r.turns = j.num_turns; r.denials = (j.permission_denials || []).length; r.models = {};
    for (const [mm, u] of Object.entries(j.modelUsage || {})) r.models[mm] = { out: u.outputTokens, cc: u.cacheCreationInputTokens, cr: u.cacheReadInputTokens, cost: u.costUSD };
  }
  if (m[3] === 'log') {
    const raw = fs.readFileSync(path.join(dir, f), 'utf8'); const ts = raw.split('\n').filter(l => /^\d\d:\d\d:\d\d /.test(l));
    const s = t => { const [h, mi, x] = t.split(':').map(Number); return h * 3600 + mi * 60 + x; };
    r.wall = ts.length ? (s(ts[ts.length - 1].slice(0, 8)) - s(ts[0].slice(0, 8)) + 86400) % 86400 : 0;
    r.agents = ts.filter(l => / TOOL Agent /.test(l)).length; r.limit = /session limit/i.test(raw); r.bg = /Background tasks still running/.test(raw); r.result = ts.some(l => / RESULT /.test(l));
  }
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
const rows = Object.values(byIssue).sort((a, b) => a.issue - b.issue);
const names = ['opus', 'sonnet', 'fable', 'haiku'];
const pick = (b, name) => { const e = Object.entries(b.models).find(([m]) => m.includes(name)); return e ? `${k(e[1].out)}/${k(e[1].cc)}/${k(e[1].cr)}` : '-'; };
console.log('| issue | runs | first run | cost $ | ' + names.map(m => m + ' out/cc/cr').join(' | ') + ' | turns | wall min | denials | agent calls |');
console.log('|' + '---|'.repeat(11));
for (const b of rows) console.log(`| #${b.issue} | ${b.runs} | ${b.first} | ${b.cost.toFixed(2)} | ${names.map(n => pick(b, n)).join(' | ')} | ${b.turns} | ${Math.round(b.wall / 60)} | ${b.denials} | ${b.agents} |`);
const tot = rows.reduce((a, b) => { a.cost += b.cost; a.runs += b.runs; a.lost += /^ok|ready/.test(b.first || '') ? 0 : 1; return a; }, { cost: 0, runs: 0, lost: 0 });
console.log(`\nissues ${rows.length} · runs ${tot.runs} · first run not delivered ${tot.lost} · cost $${tot.cost.toFixed(2)} · per issue $${(tot.cost / Math.max(rows.length, 1)).toFixed(2)}`);
const mt = {}; for (const b of rows) for (const [m, u] of Object.entries(b.models)) { const x = mt[m] ||= { out: 0, cc: 0, cr: 0, cost: 0 }; x.out += u.out; x.cc += u.cc; x.cr += u.cr; x.cost += u.cost; }
const tc = Object.values(mt).reduce((a, x) => a + x.cost, 0) || 1;
for (const [m, x] of Object.entries(mt)) console.log(`${m}: out ${k(x.out)} cc ${k(x.cc)} cr ${k(x.cr)} cost $${x.cost.toFixed(2)} (${Math.round(100 * x.cost / tc)}%)`);
if (only && rows[0]) { const b = rows[0]; const sum = f => Object.values(b.models).reduce((a, u) => a + u[f], 0); console.log(`\n#31 row: | #${b.issue} | runs ${b.runs} | ${b.first} | $${b.cost.toFixed(2)} | out ${k(sum('out'))} | cc ${k(sum('cc'))} | cr ${k(sum('cr'))} | ${Math.round(b.wall / 60)} min | ${b.agents} agent calls |`); }
