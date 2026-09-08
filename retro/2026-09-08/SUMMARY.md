# Retrospective 2026-09-08 — summary

Scope: 16 headless runs (14 result JSONs), 82 agent transcripts, 77 issues, 78 pipeline runs, both
git logs, 2026-09-06/07. Ten features reached READY FOR PROD; five runs were lost; $284 list spent
by the runs plus ≈ $129 by the two PM conversations. Details: `baseline.md`, `findings.md`,
`team.md`, `patches/`, `measurement.md`.

The shape of the problem, in one paragraph: **runs are lost to two mechanical failures** (an
orchestrator that ends its turn with agents in the background; file writes through heredocs that
the hook or Windows rejects), **tokens go to re-reading** (the orchestrator alone is 40 % of all
cache-read; 60 % of bytes read are the same files read by several agents; every fresh context
pays ≈ 60 K tokens to boot), and **time to prod is waiting, not working** (median 4.1 h from
`ready` to start and 4.4 h from READY to RELEASED against a 55-minute run). The pipeline itself is
healthy (0 failures, 1 rerun, 28 minutes of Actions for the day).

## Top ten changes, in order

| # | change | metric moved | estimated effect | effort | kind | patch |
|---|---|---|---|---|---|---|
| 1 | `Agent` hook: no background delegation under `NGM_HEADLESS`; launcher preserves the tree (diff + stash) on any abnormal end | F-run, time | −4 lost runs and −113 min of reruns per 16 runs; no hand rescue | S | mechanical | 02, 04 |
| 2 | guard-prod ignores heredoc bodies and refuses heredocs > 2 KB ("use Write") | F-run, output | 4 failures/16 runs → 0; −15–20 K output each; one lost design avoided | S | mechanical | 03 |
| 3 | Context restructure: lessons index ≤ 120 lines + domain files; deployment skills → checklists; ≤ 5 lessons forwarded per handoff; size caps in `validate.sh`/`check-app.sh` | cache-create, boot | −45 K cc and −3 tool calls per issue; growth stops | M | caps mechanical, split is content (ticket T3) | 06, 07 |
| 4 | Orchestrator stops doing specialist work: Explore sweep once, `dev-probe.sh`, QA owns DEV validation, design read as "Decisions" only | cache-read, output, time | −3 M cr, −20 K out, −10 min per issue | S–M | script + rule | 05, 12 |
| 5 | Capped design template (28 KB, hook-enforced) + pattern catalogue; architect skipped for a named pattern | output, cc, time | −50 K out, −100 K cc per design; −$4.4 and −16 min per pattern-shaped issue | M | mechanical cap | 06, 08 |
| 6 | Queue runner (`--queue`), standing-decisions register, ticket readiness checklist, Haiku triage | time, F-run | `ready` → start 4.1 h → minutes when you are away; no more designs on unsettled decisions (#68 ×2) | S | runner mechanical, rest template | 13 |
| 7 | PM conversation on Opus (your call) | session window | ≈ −$60–90/day list ≈ room for 2 more runs per window | S | settings | 16 |
| 8 | Trust pre-flight (`hasTrustDialogAccepted`) | denials, latency | allow list active in every run; −3 denials/14 runs | S | mechanical | 01 |
| 9 | Corrections continue the same agent (`SendMessage`); security review diff-scoped; QA + security dispatched in one turn | cache-create | −80 K cc per correction round (14/16 runs); −100 K cc per review | S | prose + handoff | 12 |
| 10 | One canonical record: the READY FOR PROD comment is the report; task-file caps; `metrics.csv` + `retro/metrics.js` write the #31 row | output, PM turns | −10 K out, −40 K cc per issue; next retrospective costs nothing | S | template + script | 04, 09, measurement |

Also proposed: limit detection with exit 3 and the resume command (04); routing eval cases from the
real tickets (10); `prod-release.sh` behind the unchanged gate (11); install manifest and
`validate.sh --installed`, RETROSPECTIVE.md out of the skills tree (15); Opus architect + Fable
review mode and a `fullstack-engineer` role (16, your decision); local DB gate options and the seven
ngm.app tickets (14).

Already working, not re-proposed: #39 (check-dev), #43 (typecheck), the 17:42 prompt fix (held for 7
calls — patch 02 makes it a hook). The 22:18 routing change has one unexercised data point.

## Team: current → proposed

| agent | model today → proposed | owns | invoked when | parallel with |
|---|---|---|---|---|
| Orchestrator (headless) | opus / fable for batches (unchanged) | commits, pushes, `prod-release.sh` after your yes | always | – |
| Orchestrator (PM conversation) | fable (by hand) → **opus** (C2) | backlog, launches, releases | PM mode | – |
| Explore | haiku (unchanged) | – | **before every PLAN** (facts, pattern, triage), locating code | other Explore calls |
| researcher-architect | fable → **opus**, capped design (C1) | `.agent-context/` | no catalogued pattern, or a decision must be agreed | – |
| researcher-architect, review mode | **fable** (new use, C1) | – | tier 3/4 designs, ≤ 8 K out | – |
| backend-engineer | sonnet; opus on RLS/definer/trigger (unchanged, now hook-checked) | `supabase/`, `terraform/` | DB/infra | frontend-engineer |
| frontend-engineer | sonnet (opus only with a stated tier — hook) | `app/src/` | UI | backend-engineer |
| fullstack-engineer (C3) | sonnet | `app/src/` ∪ `supabase/` | small two-sided tickets, no new policy | – |
| qa-engineer | sonnet (unchanged) | tests, evidence, **DEV validation (dev-probe, Playwright later)** | any non-trivial change | security-reviewer |
| security-reviewer | opus; fable on RLS/definer/trigger (unchanged) | – | auth/roles/data/migrations/workflows, **diff-scoped** | qa-engineer |
| deployment-engineer | sonnet (unchanged) | `.github/workflows/` | the pipeline itself changes | – |

Not added: `context-curator` (scripts remove most of its work), a separate `design-reviewer` (the
architect in review mode does it), a `triage` agent (an Explore prompt does it).

## Patch groups

- **A — quick wins (≤ 1 h, no behaviour risk):** 01 trust pre-flight · 02 agent-call guard · 03
  heredoc guard · 04 launcher preserve/limit/metrics · 05 dev-probe · 06 size caps.
- **B — one session each:** 07 context restructure · 08 design template + patterns · 09 record
  dedupe · 10 routing evals · 11 prod-release script · 12 handoffs/review/corrections · 13 PM
  instructions + queue runner · 15 install manifest.
- **C — your decision:** 14 local DB gate (options A/B/C) + the ngm.app tickets T1–T7 · 16 model
  routing (Opus architect + Fable review; PM on Opus) and the fullstack role.

Which patch groups shall I apply — A, B, C, or a subset? On your yes I apply them in this repo
only, run `bash scripts/validate.sh`, commit one commit per group, run
`powershell -File scripts/install-into-repo.ps1`, and list the ngm.app tickets (T1–T7 in patch 14)
for you to create through PM mode.
