# Findings — root causes, ranked

Rank = impact × confidence ÷ effort. Metrics: F-run, F-quality, F-pipeline, F-validation; tokens
per delivered issue (out / cache-create weighted); time `ready` → RELEASED. Baseline numbers are in
`baseline.md`; log times UTC. "Mechanical" = enforced by a script/hook/template cap, not prose.

## Already addressed — did it work?

| change | evidence after the change | verdict |
|---|---|---|
| #39 check-dev false PASS (`ceb7ab0`, 14:27 BST) | `check-dev.sh --sha` used in #55 rerun (PASS on `f0af477`), #33, #56 rerun; no "no runs = PASS" since | **worked**; keep |
| #43 typecheck stage (`7865861`) | `check-app.sh` runs `npm run typecheck` first; #57 (stale `types.ts`) was found by it | **worked** |
| 17:42 BST prompt fix ("turn ending IS the session ending", `5c5ba4a`) | `run_in_background` on 60/71 Agent calls before, **0/7 after** (#56 rerun, #70); no ceiling kill after | worked so far, but it is prose — 2 runs is not proof (F1 makes it mechanical) |
| 22:18 BST routing change (Fable architect/orchestrator for batches, `a8d2a36`) | one run (#70): Fable architect 84 K out / 225 K cc / 1.14 M cr ≈ $12 list vs Opus architect avg ≈ $4.4; design 55 KB, then the run was stopped by the user | **too early to judge**; the design was not exercised. See F7/F8 for a cheaper shape that keeps Fable's judgement |

## Hypotheses

**H1 — Lost runs from background delegation. KEEP, with a correction.** Background dispatch was
near-universal (60/71 calls) and by itself not fatal: 10 runs delivered with it. The killer is the
orchestrator ending its turn while agents run: #12 09:50 (`RESULT … turns=7` at 10:33:56 while the
frontend engineer was mid-write), #56 17:21 (RESULT 17:33:39 two minutes after the architect's
write failed). #55 13:55 ended without any RESULT (terminated externally at 14:05; no stderr). Two
more runs (#3, #8) paid the 600 s ceiling **after** delivery, killing subagents whose later output
was never read. Lost: ≈ $25 and 55 min directly, 113 min of reruns. Recurrence after 17:42: none in
7 calls. Mechanical fix: hook on `Agent` rejecting `run_in_background` under `NGM_HEADLESS=1`
(patch 02) + launcher preserves the tree on any abnormal exit (patch 04). Confidence high. Effort S.
Moves F-run (5/16 → target ≤ 1/16), reruns (−4 per 16), time (−113 min per 16 runs).

**H2 — Allow list inert. KEEP.** 16/16 logs; `hasTrustDialogAccepted=false` for both path
spellings. 9 denials in 14 JSONs; 4 of them (.env) would still be denied by the deny list, 2
(heredocs) by the hook, so trust would have saved 3 denials and the classifier's per-call
adjudication (latency not measurable from the logs; the auto classifier also produced the #13 prod
probe and #56 JWT-grep denials). Fix: pre-flight refusing to launch until the flag is true (patch
01). Confidence high on the fact, medium on the size of the effect. Effort S.

**H3 — Session-limit deaths. KEEP.** #13 05:25–05:27, JSON `success` (a limit death looks like
success to the launcher); 69 min idle before the rerun. Empirically 3 tier-3 issues + part of a
fourth (≈ $96 list, ≈ 1.2 M output tokens, 3.2 h) reached the limit from 02:14. The proposed profile
(F5–F7, −30 to −40 % output/cc per issue) allows ≈ 4.5–5 issues per window. Fix: launcher detects
the limit text in the log/result, exits 3, prints the reset time and the resume command; the queue
runner (patch 13) sleeps until the reset instead of stopping. Effort S. Confidence medium.

**H4 — Where the tokens go. KEEP, quantified.** Opus 89 % of cost; on Opus cache-read is 52 %,
cache-create 23 %, output 25 % (list price). Attribution: (a) boot cost of fresh contexts (system
prompt + preloaded skills + `project.md`/`security-model.md`/`lessons.md` reads) ≈ 4.4 M cc = 34 % of
all cache-create; context-file bytes are 10 % of everything read, design docs 15 %, task files 5 %;
(b) **the orchestrator alone is 40 % of all cache-read** (66 tool calls per run, 8.9 M cr) —
duplicate reads across agents are 60 % of bytes read. Output: file writes are only 15 % of output
tokens (code 8 %, design 3.4 %, records/comments 4 %); thinking + prose + tool arguments are 85 %.
So the biggest single lever is **fewer orchestrator turns and tool calls** (F5), then boot/context
(F6), then design (F7). Records (H10) are real but small (≈ 4 % of output).

**H5 — Heredoc writes. KEEP, cause widened.** 4 failures in 6 runs: guard-prod false positive (#13
05:18:59, #55 15:04:26), **Windows command-line limit** (#55 14:18:27; #56 17:31:49 `ENAMETOOLONG`,
design lost, run lost). The lesson exists (`lessons.md` line 229, `d9b0bcd`) and recurred 4 times
the same day. Mechanical: guard-prod strips heredoc bodies before matching and **blocks any heredoc
body > 2,000 bytes** with "use Write" (patch 03). Confidence high. Effort S. Saves ≈ 15–20 K output
per avoided failure and removes one F-run class.

**H6 — DEV probe harness reinvented. KEEP.** `ngm.js` (#12 10:18), `devprobe.sh` (#55, 5 uses),
token sign-ins hand-rolled in #12/#13, 5 `.env` denials hunting for keys, #8's whole 25-min rerun
was the orchestrator validating alone. Committed `dev-probe.sh` (patch 05), QA owns validation
(patch 12). Effort S. Saves ≈ 10–15 orchestrator tool calls and ≈ 20 K output per issue; removes
the `.env` denial class.

**H7 — Tier inflation. KEEP for frontend, KILL for backend.** Backend ran on Opus in 13/15
invocations, but 7 of the 8 backend tasks changed RLS or a definer function — the rule requires
Opus there. Frontend Opus (6/16: #4, #12 ×4, #13, #56) had 1.25 correction rounds vs Sonnet's 1.0;
no quality signal for the upgrade; cost ≈ $2 extra per invocation (≈ $12 total). An architect ran on
a tier-2 UI consolidation (#56 first run) and the rerun delivered without one, 0 corrections. Fable
architect: 2.8× Opus cost per design, unexercised. Fix: routing eval cases from real tickets (patch
10) + an Agent-call guard that refuses `model: opus|fable` for engineers unless the handoff says
`TIER: 3|4` (patch 02). Effort S. Confidence medium. Small token effect (≈ 3 %/issue).

**H8 — Context re-reading and bloat. KEEP.** `lessons.md` 64.7 KB (≈ 16 K tokens) read by the
orchestrator in 14/16 runs, triple-read when it overflowed the Bash cap (#12 lines 9–11; #70), plus 5
subagent reads; +44 lines per task. Deployment skills (10–11 KB each) are preloaded: backend boots
with 22 KB of skill text, and their "Lessons learnt / Known problems / Open questions" sections
duplicate `lessons.md`. Orchestrator boot ≈ 110 KB before the first action. Fix (patch 07): ≤ 80-line
index at boot, per-domain files loaded by the specialist's skill, orchestrator forwards ≤ 5
lessons, size caps in `validate.sh`, "recurs twice → becomes a gate". Effort M. Saves ≈ 15 K cc per
orchestrator boot and ≈ 5 K per engineer boot ≈ 45 K cc per issue, plus ≈ 3 tool calls.

**H9 — Design docs. KEEP.** 5 docs, 62–81 KB, 950–1,364 lines, 18–42 code fences (10–15 SQL),
read 3–7× per run (#8: ×7 = 539 KB ≈ 135 K tokens), the orchestrator reads them whole (#4: 67 KB).
"Moderated member-submitted table + private bucket + push" was designed three times (#13, #8, #12).
Fix (patch 08): capped template (≤ 400 lines / 28 KB, enforced by the guard-paths hook on Write for
`*-design.md`), no restated context, no SQL listings, per-engineer sections, a `patterns.md`
catalogue so the architect is skipped when the ticket names a pattern. Saves ≈ 50 K output + ≈ 100 K
cc per designed issue; skipping the architect saves ≈ $4.4 and ≈ 16 min per pattern-shaped issue.
Effort M. Confidence high.

**H10 — Quadruple recording. KEEP, smaller than assumed.** Task files 9–45 KB, comments + reports
292 KB scratch, lessons +44 lines, #31 row: ≈ 120 K output tokens over 16 runs (≈ 4 %) but the task
file is then re-read ≈ 5× per run (#55: 67 KB). Fix (patch 09): the READY FOR PROD comment **is**
the final report; the task file's evidence sections are capped; lessons ≤ 5 lines/task; the #31 row
is written by the launcher from `metrics.csv`. Effort S. Saves ≈ 10 K output + ≈ 40 K cc per issue.

**H11 — Migrations first executed in CI/DEV. PARTLY KILL.** This batch: 0 red pipeline runs, 1
rerun (rate limit on `setup-cli@latest`, still `@v1` in `database-migration.yml`), 0 green-but-dead.
The RLS-level defects (#3, #8, #12, #13) were caught by security review before push. A local
Postgres gate needs Docker/WSL or `supabase` CLI — none installed; it is a user decision (patch 14,
group C) with a Docker-less option. The cheap parts — pin `setup-cli`, post-deploy smoke check — are
already consolidated in ngm.app #21; patch 14 gives the ticket text. Effort L. Impact low now.

**H12 — Prod release procedure. KEEP, re-sized.** Releases took 3–7 min and 4–20 K output each
(PM transcripts) — cheap. The real time is `ready-for-prod` → RELEASED median 4.4 h (the user's
availability), which no script changes. `prod-release.sh` (patch 11) still pays: ordered dispatch,
`gh run watch`, read-only validation and the record in one command, fewer turns in the PM session
(F15). Effort M. Saves ≈ 3 min and ≈ 10 K output per release.

**H13 — Drift. KEEP, small.** One stale line (`RETROSPECTIVE.md` in ngm.app; the installer never
syncs skills-root files); settings differences are intended. Manifest + `validate.sh --installed`
(patch 15). Effort S.

**H14 — Stops a better ticket would have prevented. KEEP, re-shaped.** Zero headless
`needs-decision` stops: the orchestrator decided the architect's NEEDS-DECISION items from precedent
(#8: 3 items; #4: AC 8). The cost was **mid-flight decision changes**: #68 paused after PLAN when the
source decision changed (`52f4572`), then #70 stopped by the user at 22:52 (≈ $18, 22 min) — and two
launcher refusals (22:25, 22:30:10) before it. Standing decisions are scattered across 4 files (8
"(user decision …)" notes). Fix (patch 13): `decisions.md` register, ticket readiness checklist
(including "Pattern:" and "Decisions final: yes"), queue runner with "work through" as the default.
Effort S. Confidence medium.

## Findings the data added

**F15 — The PM conversation costs as much as 4–5 feature runs.** `4c93ddd1` (Fable, 10 h 21 m):
165 K out, 1.29 M cc, 40.4 M cache-read ≈ $97 list; `012dc5ab` (Opus, 8.5 h) ≈ $32. Long-lived
sessions are cache-read machines; on Fable the cache-read alone is ≈ $60. The PM's work is plumbing
(launch, wait, read a result, comment) plus one judgement per item. Fix: PM session on Opus (its
`settings.json` already says so — the user chose Fable by hand), and the launcher/metrics/release
scripts cut PM turns. User decision (group C). Saves ≈ $60–90/day of PM at list, i.e. the session
window's headroom for ≈ 2 more feature runs.

**F16 — The orchestrator does specialist work.** 66 tool calls/run, 37 KB code + 26 KB design read
per run, probes written (#12 `ngm.js`, #55 `devprobe.sh`), whole design docs read in chunks, DEV
validation alone (#8 rerun: 70 tools, 59 K out, 7 M cr). Every orchestrator tool call is re-read on
every later turn (40 % of all cache-read). Fix: scripts that return one line (`check-dev`,
`dev-probe`, `pm-run-issue` summary), design "Decisions" section only, QA owns validation, Explore
gathers facts once and the handoff forwards them (patch 12). Effort S–M. Target: ≤ 35 tool calls per
run → ≈ −3 M cache-read per issue (≈ −9 %).

**F17 — Security review is the heaviest reader.** 229 KB avg, #12 rerun 400 KB, 654 K cc, 109 K out,
40 min — more than both engineers. It reads whole migrations and pages rather than the diff. Fix:
handoff gives `git diff --name-only <base>..HEAD` and the base commit; reviewer reads diffs first
(patch 12). Saves ≈ 100 K cc per review. Effort S.

**F18 — Corrections re-spawn a fresh context.** All 14 correction rounds were new Agent calls
(boot ≈ 63 K cc + re-reading the design ≈ 18 K). Claude Code 2.1.261 offers `SendMessage` to a
spawned agent with its context intact. Fix: correction rounds and "thin result → retry" continue the
same agent (patch 12). Saves ≈ 80 K cc per round ≈ 1.1 M over 16 runs (8 % of cc). Effort S.

**F19 — Time to prod is queue and release waiting, not run time.** `ready` → start median 4.1 h,
RFP → released 4.4 h, run 55 min. Fix: `pm-run-issue.sh --queue` runs the ready items one after
another (still one at a time, still never prod) and pauses for a limit reset; releases stay
batched. Cuts ready→start to minutes when the user is away. Effort S. Confidence high.

**F20 — Failed launches leave prompt-only files** (#20 01:39, #4 02:13, #70 22:25 and 22:30:10):
the pre-flight died after writing the prompt. Cosmetic; patch 04 writes the prompt after the
pre-flight and records the refusal reason.

## Ranking

| # | finding | metric moved | estimate per issue (or per 16 runs) | conf. | effort | mechanical? | patch |
|---|---|---|---|---|---|---|---|
| 1 | F1 background-agent guard + tree preservation | F-run, time | −4 lost runs, −113 min reruns, −$25 lost per 16 runs | high | S | yes | 02, 04 |
| 2 | H5 heredoc guard (size + body-stripping) | F-run, out | −1 lost run, −15–20 K out per failure, 4 failures/16 runs | high | S | yes | 03 |
| 3 | H8 context restructure + skill checklists | cc, boot | −45 K cc, −3 tool calls; caps stop growth | high | M | caps yes, split is content | 07 |
| 4 | F16 + H6 orchestrator footprint, dev-probe, QA owns validation | cr, out, time | −3 M cr, −20 K out, −10 min | high | S–M | script yes | 05, 12 |
| 5 | H9 design cap + pattern catalogue | out, cc, time | −50 K out, −100 K cc per design; architect skipped ≈ −$4.4, −16 min | high | M | cap yes | 08 |
| 6 | F19 + H14 queue runner, decisions register, readiness checklist | time, F-run | ready→start 4.1 h → minutes; −1 paused run per ~10 | med | S | runner yes | 13 |
| 7 | F15 PM session on Opus | session window | ≈ −$60–90/day list; ≈ +2 runs per window | high | S | settings | 16 (C) |
| 8 | H2 trust pre-flight | denials, latency | −3 denials/14 runs; classifier off the hot path | high | S | yes | 01 |
| 9 | F18 same-context corrections | cc | −80 K cc per round (14 rounds/16 runs) | med | S | prose | 12 |
| 10 | H10 record dedupe | out, cc | −10 K out, −40 K cc | med | S | caps yes | 09 |
| 11 | F17 security review scope | cc, time | −100 K cc, −10 min per review | med | S | prose + handoff | 12 |
| 12 | H3 limit detection + resume | time | −69 min idle per limit death | med | S | yes | 04 |
| 13 | H7 routing eval cases + engineer-model guard | out | ≈ −$1–2/issue; prevents architect on tier 2 | med | S | guard yes | 02, 10 |
| 14 | H12 prod-release.sh | time, PM turns | −3 min, −10 K out per release | med | M | yes | 11 |
| 15 | H13 install manifest | drift | 1 stale file today | high | S | yes | 15 |
| 16 | H11 local DB gate, setup-cli pin, smoke check | F-pipeline, F-validation | 1 rerun/27 runs today; insurance | low | L | CI yes | 14 (C) |
