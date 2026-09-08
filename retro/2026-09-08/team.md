# Team topology — gaps and consolidation

Basis: the activity matrix in `baseline.md` §2 (82 invocations over 16 runs). Tests applied to every
candidate: a new agent must remove a failure class or save more than its own boot (≈ 60–70 K
cache-create for a Sonnet/Opus specialist, ≈ 70 K for Explore on Haiku); a consolidation must never
put review and implementation in one context for anything with a security surface; subagents
cannot spawn subagents, so fan-out stays with the Orchestrator; parallelism buys wall time, not
tokens.

## What the matrix shows

**Work done by the wrong (expensive) agent.**
- Orchestrator (Opus): wrote probe harnesses (#12 `ngm.js` 10:18; #55 `devprobe.sh`, 5 uses),
  validated DEV alone (#8 rerun: 70 tool calls, 59 K out, 7 M cr, 25 min), read whole design docs
  (67 KB in #4; 57 KB in #12), read 37 KB of code per run on average. It is 40 % of all cache-read.
- Architect (Opus): read `node_modules/@supabase/storage-js` `.d.ts` to learn an API (#4 02:17:10) —
  an Explore/Haiku job; wrote 62–81 KB documents that restate `project.md` (§0 "Verified findings"
  is 40+ lines of context in each).
- Security reviewer (Opus): 229 KB read per review, 400 KB in #12 — reads whole files, not diffs.

**Duplicate reads.** Same file read by more than one agent in one run: #8 1.66 MB (design ×7,
migration ×7, page ×6), #3 1.20 MB, #12 rerun 0.94 MB, #4 0.70 MB; 8.29 MB overall = 60 % of bytes
read ≈ 2.1 M cache-create tokens. The design doc and the new migration are the two files everyone
reads. Facts gathered once by Explore and forwarded would not remove this (the specialists need the
design and the migration); a **shorter design** and a **diff-scoped review** would.

**Sequential phases that are independent.** QA and security already run in parallel (8 of 9 runs
with both; #33 sequential by habit, foreground). Batch members in parallel: no batch has completed
yet (#70 stopped at design). Engineers run in parallel in every two-sided task. Nothing else is
serialised by habit except the architect → engineers dependency, which is real.

**Correction rounds.** All 14 rounds were fresh Agent calls; none continued the engineer's
context. `SendMessage` to a spawned agent exists in 2.1.261 (this session's tool list). A fresh
context costs its boot (63 K cc) plus re-reading the design (≈ 18 K) before it fixes anything.

**Phases with no owner today.**
| phase | who did it | evidence |
|---|---|---|
| prod release execution | Orchestrator in the PM conversation, by hand | 4 releases, 3–7 min each, 6–17 tool calls |
| context curation (fold lessons, re-verify `project.md`/`security-model.md`) | nobody since `f5d2540` (03:11 BST 09-07); #63 says security-model is 7 migrations stale | lessons.md +484 lines in a day, none folded |
| triage of `claude` issues | PM by hand: 5 duplicates consolidated 22:02–22:03 | 50 `claude` issues in two days |
| local migration validation | nobody (no Docker/psql here) | 1 CI rerun, 0 failures this batch |
| browser-level DEV validation | the user, on a phone | RETROSPECTIVE open question; no Playwright |
| library/API fact-finding | architect (Opus) or engineers | #4 architect in node_modules |
| metrics | PM by hand into #31 (2 rows in a day) | #31 body 32 KB |

## Candidates, with numbers

| candidate | kind | boot cost | saves / removes | wall time | rule it touches | verdict |
|---|---|---|---|---|---|---|
| Skip the architect when the ticket names a catalogued pattern (Orchestrator writes the contract, as CLAUDE.md already says) | consolidate | 0 | ≈ 70 K out + 250 K cc + 2.2 M cr per skipped design (≈ $4.4); 3 of 5 designs were the same pattern | −13 to −21 min | PLAN step; `patterns.md`; ticket "Pattern:" field | **do** (patch 08) |
| Opus architect writing a capped design + Fable **review** of it (same agent file, `model: fable`, review-only prompt, ≤ 8 K out) instead of a Fable architect | change | +1 short Fable call (≈ 40 K cc, ≈ 8 K out ≈ $1.5) | Fable design ≈ $12 → Opus design ≈ $3 (capped) + review ≈ $1.5; keeps Fable's judgement where it is cheap | +3 min | routing table row; memory "Fable for the architect" is the user's experiment → group C | **propose (C)** (patch 16) |
| QA owns DEV validation with `dev-probe.sh`; Orchestrator never probes | consolidate | 0 (QA already runs) | Orchestrator −10–15 tool calls, −20 K out, −2–3 M cr per issue; removes the #8-style validation rerun | −10 min | INTEGRATE step; qa-engineer.md | **do** (05, 12) |
| Security review reads diffs first (`git diff --name-only <base>`) | change | 0 | ≈ −100 K cc, −30 K out per review (#12: 654 K cc) | −10 min | security-reviewer.md handoff | **do** (12) |
| Corrections continue the same engineer via `SendMessage` (also "thin result → retry") | change | 0 | ≈ 80 K cc per round; 14 rounds/16 runs | −3 min per round | handoff.md, REVIEW step | **do** (12) |
| Explore (Haiku) fact-sweeps before PLAN, forwarded in handoffs | new use | 70 K cc, 7 K out (≈ $0.10) | engineers' exploratory reads (frontend boot 10 tool calls, 65 K cc) → ≈ −30 K cc per engineer; the three runs that used Explore had ≤ 1 correction round and no architect | ±0 | PLAN step | **do** (12) |
| `context-curator` (Sonnet) at COMPLETE: fold lessons, file issues, #31 row | new agent | 60 K cc + ≈ 10 K out (≈ $0.4) | Orchestrator's COMPLETE phase ≈ 25 K Opus out + ≈ 20 tool calls (≈ $1 + cr); but `metrics.csv` and a capped lessons template remove most of that work without a model | ±0 | new agent + hook role | **not now**: scripts first (04, 09); revisit if lessons quality drops |
| `ui-validator`: QA drives a committed Playwright smoke against DEV | new capability, same agent | 0 new context; Playwright is a free npm dev dependency; no Actions minutes if run locally by QA | removes the "rendering checked only by the user" F-validation gap | +3 min | ngm.app ticket; qa-engineer.md | **propose** (ticket in 14) |
| `triage` on Haiku (Explore prompt) before the PM conversation: dedupe `claude` issues, propose batch membership | new use of Explore | ≈ 70 K cc, ≈ $0.10 | PM turns on Fable/Opus (5 manual consolidations ≈ 20 tool calls) | −10 min PM | PM skill step | **do** (13) |
| `fullstack` engineer (one Sonnet context, frontend ∪ backend paths) for small two-sided tickets (#55: 3 files each side; #56: 3 KB backend) | consolidate | saves one boot (≈ 63 K cc) + one handoff | ≈ −70 K cc, −1 handoff per small ticket; review stays separate | −5 min | new `guard-paths` role; CLAUDE.md smallest-team; validate cases | **propose (C)** (patch 16) |
| Three deployment skills (10–11 KB each, preloaded) → one ≤ 3 KB checklist per role; lessons/known-problems sections into the lessons index | consolidate | – | ≈ −5 K cc per engineer boot (31 boots/16 runs ≈ −150 K cc); backend boots with 22 KB less | ±0 | skills; validate size cap | **do** (07) |
| `RETROSPECTIVE.md` out of the skills tree | consolidate | – | removes an un-synced file and 15 KB from the installed tree | – | installer, validate | **do** (15) |
| `prod-release.sh` (Orchestrator runs one script after the user's yes) | script, no agent | – | −3 min, −10 K out per release; fixed order, read-only validation | −3 min | Prod release section; guard-prod unchanged | **do** (11) |
| Parallel per-role authorization probes through `dev-probe.sh` (QA runs admin/mentor/participant in one loop) | script | – | replaces hand-rolled sign-ins (#12, #13) | −5 min | qa-engineer.md | **do** (05) |
| Stop: architect on tier-2 UI work (#56); Orchestrator reading design docs whole; `RESULT` line per subagent; deployment-skill lesson sections | remove | – | see above | – | | **do** (02 guard, 08, 04, 07) |

## Proposed team

| agent | model | owns | invoked when | runs in parallel with |
|---|---|---|---|---|
| Orchestrator (headless: lone ticket Opus, batch Fable — unchanged; **PM conversation: Opus**, C) | opus / fable | commits, pushes, `prod-release.sh` after the user's yes | every task | – |
| Explore | haiku | nothing | before PLAN (facts, pattern check, triage sweep); locating code | several Explore calls together |
| researcher-architect | **opus** (C; today fable) | `.agent-context/` | no catalogued pattern, or a decision must be agreed; writes the **capped** design | – |
| researcher-architect, review mode | fable | nothing (read-only prompt) | tier 3/4 design exists; ≤ 8 K out | – |
| backend-engineer | sonnet; opus on RLS/definer/trigger (unchanged) | `supabase/`, `terraform/` | DB/infra | frontend-engineer |
| frontend-engineer | sonnet (opus only with `TIER: 3\|4` in the handoff — guard) | `app/src/` | UI | backend-engineer |
| fullstack-engineer (C) | sonnet | `app/src/` ∪ `supabase/` | small two-sided tickets (≤ ~6 files) | – |
| qa-engineer | sonnet | tests, task-file evidence, **DEV validation via dev-probe.sh (+ Playwright smoke when shipped)** | any non-trivial change | security-reviewer |
| security-reviewer | opus; fable on definer/RLS/trigger (unchanged) | nothing | auth/roles/data/migrations/workflows; **diff-scoped** | qa-engineer |
| deployment-engineer | sonnet | `.github/workflows/` | pipeline itself changes | – |

Current team for comparison: same agents; architect on Fable for every design; no review mode; no
fullstack role; validation shared between Orchestrator and QA; engineers frequently on Opus by
choice; PM conversation on Fable.
