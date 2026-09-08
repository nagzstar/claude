# NGM agent-system retrospective — failure rate, tokens, ticket-to-prod

Paste everything below this line into a Claude Code session started in
`C:/Users/nagaj/git/claude` (its `settings.json` pins Fable and grants access to
`C:/Users/nagaj/git/ngm.app` through `additionalDirectories`). Run it once per batch of
delivered issues; the output folder is dated so runs can be compared.

---

## Session override — read first

This is an **analysis session, not a delivery session**. For this session only:

- CLAUDE.md's Orchestrator boot sequence, lifecycle, PM mode and reporting format do **not**
  apply. Do not delegate to `researcher-architect`, the engineers, `qa-engineer` or
  `security-reviewer`. The only subagent you may use is the built-in `Explore` on `haiku`, for
  bulk read-only sweeps. Never pass `run_in_background`.
- `C:/Users/nagaj/git/ngm.app` (`NGM_ROOT`) is **read-only**. A feature session may be running
  there (`NGM_ROOT/.agent-context/.pm-run.lock`); do not touch its tree, its lock or GitHub
  issue labels. Never read `.env` files or `TEST-ACCOUNTS.md` values; never print secrets.
- Write only under `retro/<YYYY-MM-DD>/` in this repo (create it; today's date). Change nothing
  else — not CLAUDE.md, not the agents, not ngm.app — until I approve patches at the end.

## Goal

Using both repos and the evidence of the features and bug fixes delivered so far, recommend
changes to the agent system (CLAUDE.md, agents, skills, hooks, scripts, `settings.json`,
`pm-run-issue.sh`, the PM skill and ticket format), to the **team itself** (which agents are
missing, which should be merged, which should run in parallel, which should share one
context), and to how I write tickets and instructions, that will:

1. **reduce the failure rate** (definitions below),
2. **reduce tokens per delivered issue**, and
3. **reduce the time from a `ready` ticket to RELEASED TO PROD**.

Every recommendation must be tied to evidence, quantified against the baseline, and delivered as
a patch I can apply. Prefer **mechanical enforcement** (a script, a hook, a `validate.sh` case,
a template with a hard cap, a launcher pre-flight) over new prose in CLAUDE.md: the history in
this repo shows prose rules recurring as failures (the heredoc rule was recorded on 2026-09-07
02:01 and the same failure happened four more times that day; the "never end a turn waiting"
rule was added only after four runs were lost to it). Any change that adds prose to a file read
at boot must also say what to delete, so the fixed context does not grow.

## Definitions — measure these; every finding must move at least one

**Failure classes**

- **F-run** — a headless run that ends without the issue at `ready-for-prod`, `needs-decision`
  or `blocked` with its work preserved: killed at the 600 s background ceiling, session-limit
  death, crash, or a "success" result with the issue still `in-progress`.
- **F-quality** — QA FAIL rounds, security findings that needed a correction round, and
  **escaped defects**: a `bug`/`claude` issue or a fix commit attributable to a feature after it
  was READY FOR PROD or released.
- **F-pipeline** — red GitHub Actions runs, reruns (`run_attempt > 1`), rate-limit failures.
- **F-validation** — pipeline green but the feature dead on DEV/prod (RETROSPECTIVE.md records
  this three times for sign-up).

**Tokens** — per delivered issue, by type and model: input, cache-creation, cache-read, output
(from the run JSONs' `usage` for the main session and `modelUsage` for every model, subagents
included). The notional `total_cost_usd` is fine for ranking, but the binding constraint is the
subscription's session window: #13's first run died with "You've hit your session limit ·
resets 7:30am" and the rerun waited ~70 minutes for the reset. So weight **output** and
**cache-creation** tokens (the expensive ones) and count limit stalls as time.

**Time** — per issue: `ready` → run start; run wall time (first timestamped log line → the
`RESULT` line — the JSON's `duration_ms` is not wall time); rerun time; waiting on me
(`needs-decision` → `ready`); waiting for a limit reset; `ready-for-prod` → RELEASED TO PROD.

## Evidence sources (exact locations)

- **Run records** (gitignored, on disk): `NGM_ROOT/.agent-context/pm-runs/issue-<n>-<ts>.{json,log,prompt.md}`,
  plus `issue-55-partial-*` leftovers. JSON fields: `subtype`, `is_error`, `num_turns`,
  `duration_ms`, `duration_api_ms`, `total_cost_usd`, `permission_denials`, `usage`,
  `modelUsage`, `result`. Log lines are `HH:MM:SS TEXT|TOOL|RESULT …`; the claude process's
  stderr is appended **untimestamped** to the same file (e.g. `Ignoring 32 permissions.allow
  entries…`, `Background tasks still running after 600s; terminating`).
- **Transcripts**: `C:/Users/nagaj/.claude/projects/C--Users-nagaj-git-ngm-app/<session-id>.jsonl`
  and any sidechain/subagent transcript files in that project directory (session ids are in
  each `.prompt.md` and `.json`). Each assistant message carries `message.usage` and
  `message.model`. Inspect one file's keys first, then write **one node script** that
  aggregates tokens per session by agent and by phase; never read a transcript into context.
- **Task records**: `NGM_ROOT/.agent-context/tasks/*.md` — Status/Log (correction rounds,
  escalations), Test Results, Remaining Risks, Lessons Learnt, Problems Spotted; the
  `*-design.md` files (five of them are 62–81 KB); `prod-release-2026-09-07.md` (four releases);
  `issue-39-check-dev-gate.md` and `issue-43-typecheck-gate.md` (process fixes already made —
  do not re-propose them; check whether they worked).
- **Context files**: `NGM_ROOT/.agent-context/lessons.md` (750 lines, 64.7 KB), this repo's
  `.agent-context/project.md` (15.6 KB), `security-model.md` (19.1 KB), `delivery.md` (11.5 KB),
  `handoff.md`, `tasks/TEMPLATE.md`; `CLAUDE.md` (15.8 KB); `.claude/agents/*.md`;
  `.claude/skills/*/SKILL.md` (the three deployment skills are 10–11 KB each and also "carry
  the lessons"); `.claude/skills/RETROSPECTIVE.md`; `evals/`; `scripts/validate.sh`;
  `scripts/install-into-repo.ps1`.
- **Git**: `git -C "$NGM_ROOT" log --date=iso-strict --format='%ad %h %s'` and the same here —
  feature → record → fix → "Released to prod" sequences and the gaps between them.
- **GitHub** (`gh`, read-only): `gh issue list -R nagzstar/ngm.app --state all --limit 200
  --json number,title,labels,createdAt,closedAt`; `gh api repos/nagzstar/ngm.app/issues/<n>/timeline
  --paginate` (labeled/unlabeled events with timestamps → phase stamps per issue);
  `gh api repos/nagzstar/ngm.app/issues/<n>/comments` ("🚧 Started", "✅ READY FOR PROD",
  "❓ NEEDS DECISION", "⛔ BLOCKED", "🚀 RELEASED TO PROD" headers); issue **#31** (the existing
  delivery-metrics record — extend it, do not duplicate it);
  `gh api repos/nagzstar/ngm.app/actions/runs --paginate` (`name`, `run_started_at`,
  `updated_at`, `conclusion`, `run_attempt`, `event`) → pipeline durations, failures, reruns and
  Actions minutes per day.

## Step 1 — Baseline → `retro/<date>/baseline.md`

Compute with scripts (node; do not assume `jq` exists on this PC), then write the tables.

Per issue (one row per issue, runs summed, with a runs column): runs · first-run outcome ·
total cost · output / cache-creation / cache-read tokens by model · turns · wall time ·
design-doc KB · task-file KB · correction rounds · QA + security findings · pipeline runs and
minutes · `needs-decision` stops · `ready` → released hours · escaped defects.

System-wide: bytes of context each agent reads before doing any work (from each log's first
~20 TOOL lines, per orchestrator / architect / engineer / QA / security); `Agent` calls by
`subagent_type` and `model`; how many times `lessons.md`, `project.md`, `security-model.md` and
each design doc are read per run and by whom; heredoc writes that were blocked and rewritten;
permission denials by reason; occurrences of `Background tasks still running`, `session limit`
and `has not been trusted`; the growth of `lessons.md` per delivered task; Actions minutes used
per day and per push.

**Agent activity matrix** (per run, then summed): one row per agent invocation — type, model,
wall time, tool calls, files read and bytes, the three largest files it read, output tokens,
what it produced — and its **boot cost**: tokens consumed before its first Edit/Write/probe
(from the transcripts). Mark every file read by more than one agent in the same run, and
whether QA and security ran in sequence or in parallel. This matrix is the basis of Step 3.

State the arithmetic behind every number so I can check it. Where a source is missing (a run
without a JSON, a session with no transcript), say so and move on.

## Step 2 — Verify these hypotheses (keep or kill each, with evidence)

I have already looked at the run records. Verify each of these against the full data, correct
anything I have wrong, and quantify it.

- **H1 Lost runs from background delegation.** #12 (09:50 run) and #56 (17:21 run) end with
  `Background tasks still running after 600s; terminating` after the Orchestrator dispatched
  specialists with `run_in_background: true` and then ended its turn "waiting"; #55's 13:55 run
  ends mid-work with no `RESULT` while both engineers were backgrounded. Each lost $4–20 of
  tokens and 10–45 minutes, then needed a fresh 40–70-minute rerun. The prompt fix landed 17:42 ("a headless session's turn ending IS the
  session ending"). Check for recurrence after 17:42 and propose a **mechanical** guard: a
  `PreToolUse` hook on `Agent` that rejects `run_in_background` when the launcher sets a headless
  marker (e.g. `NGM_HEADLESS=1`), and/or `CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS`, plus
  launcher-side detection that preserves the working tree (WIP commit or stash tagged as an
  unreviewed draft) on any abnormal exit — #12's near-loss of 3,848 lines is in `lessons.md`.
- **H2 The allow list is inert in headless runs.** Every log begins `Ignoring 32
  permissions.allow entries from .claude/settings.json: this workspace has not been trusted`, so
  `--permission-mode auto` adjudicates every call. Fix: pre-flight in `pm-run-issue.sh` that
  refuses to launch unless `projects["C:/Users/nagaj/git/ngm.app"].hasTrustDialogAccepted` is
  true in `C:/Users/nagaj/.claude.json`; keep the deny list. Measure any change in denials and
  in per-call latency.
- **H3 Session-limit deaths.** #13's first run died at the limit (53 turns, ~$10, 25 min lost)
  and the rerun waited for the reset. Launcher: detect the limit message in the result/log,
  exit with a distinct code, print the reset time, and offer/automate `claude -p --resume <id>`
  after the reset; PM: start large batches right after a reset. Estimate how many issues per
  window the current token profile allows and how many the proposed one would.
- **H4 Where the tokens go.** Opus is 76–95 % of spend (your #31 finding); on my estimate
  cache-read is roughly half of cost and cache-creation a quarter (e.g. #4: Opus output 288 K,
  cache-create 1.29 M, cache-read 36.8 M tokens).
  Attribute this with the transcripts: what share of cache-creation/read comes from (a) each
  subagent's fresh read of `project.md` + `security-model.md` + `lessons.md` (~25 K tokens ×
  4–6 agents per issue), (b) design-doc reads, (c) task-file re-reads; what share of **output**
  tokens is (a) design docs, (b) task file + issue comments + `lessons.md` + final report
  (the same evidence written four times), (c) code.
- **H5 Heredoc writes blocked by `guard-prod`, then rewritten.** Design docs in #12 (heredoc
  10:09, `Write` 10:14), #13 (the heredoc is in its `permission_denials`) and #56 (the same
  pattern at 17:31); an issue body in #55's 14:10 run. Each rewrite of a design doc is ~20 K
  output tokens. Make it mechanical: `guard-prod.sh` strips heredoc bodies before matching (add a
  `validate.sh` block/allow case), and/or the architect and PM write files with `Write` only.
- **H6 The DEV probe harness is reinvented every run** (#12 wrote `ngm.js`, #55 wrote
  `devprobe.sh`; `.env` reads were denied in #3, #8, #13, #33). Propose a committed
  `.claude/scripts/dev-probe.sh` (sign in as admin/mentor/participant from `NGM_DEV_*` env
  vars and the served bundle's anon key; REST/RPC/storage helpers; never prints values),
  documented in `ngm-facts` and allow-listed.
- **H7 Tier inflation.** Engineers were dispatched with `model: "opus"` (#12, #55 logs) and a
  full architect pass ran for tier-2-shaped work (#56, a UI consolidation). Run the real cases
  against `evals/routing-cases.json` (add them), and measure correction rounds by engineer
  model to decide whether Sonnet engineers actually need the upgrade. Also check whether the
  2026-09-07 22:18 routing change (Fable for the architect and for batch orchestration) raises
  the design phase's cost — the architect writes the most output tokens of any agent — and
  whether "Fable where judgement is cheap, not where tokens are" is better served by an Opus
  architect writing a capped doc plus a short Fable review of it.
- **H8 Context re-reading and bloat.** `lessons.md` is read by the Orchestrator and again by
  every subagent (#70 log: Orchestrator 22:30:52, architect 22:33:08), exceeds the Bash output
  cap so it is read twice (#12 lines 9–11, #70 lines 7/10/13), and grows ~60 lines per task;
  the deployment skills and RETROSPECTIVE.md overlap it. Propose: a ≤ 80-line index at boot,
  per-domain detail files loaded only by the specialist that needs them (via its preloaded
  skill), the Orchestrator forwarding the ≤ 5 relevant lessons in the handoff, size caps
  enforced by `validate.sh`, and a rule that a lesson recurring twice becomes a gate, not a
  line.
- **H9 Design docs are the largest artefacts** (62–81 KB, five of them), written in one shot,
  then read by the Orchestrator in six chunks, by both engineers, QA and security. The shape
  "moderated member-submitted table + private bucket + push" was designed from scratch three
  times (#13, #8, #12). Propose a design template with a hard cap (decisions, contract,
  ownership, AC mapping; no restated context, no code listings; per-engineer sections) and a
  small pattern catalogue so the architect is skipped when a pattern exists.
- **H10 Quadruple recording.** The same evidence goes into the task file (20–45 KB), issue
  comments, a `lessons.md` section and the final report. Propose one canonical record with
  short pointers elsewhere, and a cap on the task file's evidence sections.
- **H11 Migrations are first executed in CI/DEV** ("cannot be applied locally"): the
  `fix_is_anonymous_null` migration, #55's `supabase/setup-cli@latest` rate-limit failure, and
  three green-but-dead deployments in RETROSPECTIVE.md. Propose a free local gate
  (`check-db.sh`: apply all migrations in order to a fresh local Postgres — `supabase start` or
  a plain Docker Postgres — and run the RLS probes) run by backend-engineer before COMPLETE;
  pin `setup-cli`; the post-deploy smoke check in `deploy.yml` (RETROSPECTIVE item 8, still
  open). State the Actions-minute cost of anything that runs in CI. Check whether Docker is
  available on this PC before recommending it.
- **H12 The prod release is a manual, sequential, token-consuming procedure** (four releases
  on 2026-09-07). Propose `prod-release.sh <sha>` — pre-flight, ordered dispatch, watch,
  read-only validation, record — still behind `prod-approval.sh grant`, so the Orchestrator asks
  the question and runs one script.
- **H13 Drift between the source repo and the installed copy.** ngm.app's `settings.json`
  (`claude-opus-5`, no `additionalDirectories`, 3.7 KB vs 1.8 KB) and RETROSPECTIVE.md
  (15,257 vs 15,249 bytes) differ; the installer deletes skills it does not know
  (RETROSPECTIVE item 1); `validate.sh` §5 only checks that the installer names each
  directory, never the installed copy itself. Propose a manifest written by the installer and
  a `validate.sh` comparison of the installed copy against it.
- **H14 Stops that a better ticket would have prevented.** Count `needs-decision` stops and
  mid-flight instruction changes (#68: source decision changed after PLAN → paused) and classify
  each question: answerable from a standing decision, answerable at ticket time, or genuinely
  new. Propose a **standing-decisions register** (one dated line each — the "(user decision,
  2026-09-07)" notes are currently scattered through CLAUDE.md, the PM skill and
  `pm-run-issue.sh`) that the Orchestrator may assume, a ticket-readiness checklist for the PM
  skill, and the default of "work through the ready items" so I am not asked per item.

Add any finding the data shows that is not on this list.

## Step 3 — Team topology: gaps and consolidation → `retro/<date>/team.md`

Use the activity matrix to answer two questions: **where would another agent — or several in
parallel — pay for itself**, and **where would fewer contexts do the same work better**?

The test for any change here: a new agent must either remove a failure class or save more
tokens than its own boot cost, without breaking review independence (QA and security never
fix what they review) or the ownership hooks; a consolidation must never put review and
implementation in one context for anything with a security surface. Remember that subagents
cannot spawn subagents, so fan-out is always the Orchestrator's job, and that every fresh
context re-reads whatever it needs — parallelism buys wall time, not tokens.

Look for, with evidence from the matrix:

- **Work done by the wrong (expensive) agent.** The Orchestrator reading code and writing a
  probe harness while engineers ran (#12, `ngm.js` at 10:18); the architect on Opus/Fable
  reading `node_modules/@supabase/storage-js` source to learn an API (#12 10:00–10:01); the
  Orchestrator re-reading the whole design doc in six chunks to "review" it.
- **Duplicate reads.** The same files read by the architect, both engineers, QA and security
  in one run — quantify the bytes per run. Candidate fix: the Orchestrator gathers the facts
  once through parallel `Explore` (haiku) sweeps and forwards them in every handoff, so the
  specialists start from facts instead of exploring.
- **Sequential phases that are independent.** Are QA and security dispatched in parallel
  (both are independent by rule)? Are batch members with disjoint files built in parallel
  (allowed since 22:11)? Is anything else serialised only by habit?
- **Correction rounds and thin results.** Is a correction sent to a fresh engineer context
  (full re-read) or to the one that did the work? Check whether the installed Claude Code
  version can continue a subagent with its context intact (`SendMessage` or resume by agent
  id). If it can, corrections — and the "thin result, re-run on Opus" rule — should continue
  the same context rather than re-spawn.
- **Phases with no owner today.** Prod release execution; context curation (folding lessons,
  re-verifying `project.md`/`security-model.md` — RETROSPECTIVE item 7 says the security
  model went stale); triage of the `claude`-filed issues (70 issues in two days); local
  migration validation; browser-level DEV validation (RETROSPECTIVE's open question:
  rendering was only ever checked by me on a phone); library/API fact-finding; metrics.
- **Candidates to evaluate** — each with boot cost, tokens saved or failure class removed,
  wall-time effect, and the hook, ownership or `validate.sh` change it needs:
  - *new*: a `context-curator` (Sonnet or Haiku) that runs at COMPLETE instead of the
    Orchestrator doing the lessons/issues/record work on Opus or Fable; a `ui-validator`
    (Sonnet) driving a committed Playwright smoke script against DEV (free, no Actions
    minutes); a `triage` agent (Haiku) that dedupes and labels `claude` issues and proposes
    batch membership before the PM conversation; a Fable `design-reviewer` of a capped Opus
    design instead of a Fable architect; parallel `Explore` fact-gathering before PLAN;
    parallel per-role authorization probes through the committed harness.
  - *consolidate*: skip the architect where a pattern exists (the Orchestrator writes the
    contract, as CLAUDE.md already says but the logs show rarely happens); one `fullstack`
    engineer instance for small tickets that touch both sides (needs a `guard-paths` role);
    QA and security in parallel; DEV validation owned by `qa-engineer` with the committed
    harness, never the Orchestrator; the three deployment skills (10–11 KB each, preloaded
    into the engineers) collapsed into one short per-role checklist; `RETROSPECTIVE.md` moved
    out of the skills tree (it is a document, not a skill).
  - *remove or stop invoking*: anything the matrix shows adding boot cost without changing an
    outcome.
- For every candidate give the numbers — boot cost, tokens saved per issue, reruns or
  defects avoided, minutes saved — and the rule it touches. Rank them together with the
  findings in Step 4; a team change that is not backed by the matrix is not proposed.

## Step 4 — Root-cause and rank → `retro/<date>/findings.md`

For each finding: evidence (cite `path:line` or `issue-N-<ts>.log HH:MM:SS`), mechanism, the
metric(s) it moves with a numeric estimate from the baseline ("~N K tokens per issue", "~N
reruns per 10 issues", "~N min per issue"), confidence, effort (S/M/L), and any conflict with
my rules (below). Rank by impact × confidence ÷ effort. Say explicitly which findings are
already addressed by #39, #43, the 17:42 prompt change or the 22:18 routing change, and
whether the data after those changes shows them working.

## Step 5 — Patches → `retro/<date>/patches/NN-<slug>.md`

One file per accepted finding or team change: the finding; expected effect; **unified diffs**
for files in this repo (CLAUDE.md, agents, skills, hooks, scripts, `settings.json`,
`pm-run-issue.sh`, `validate.sh`, `install-into-repo.ps1`, `evals/routing-cases.json`); new
agent files complete with frontmatter, ownership hook and `validate.sh` cases; new files in full;
`validate.sh` cases to add; and, for anything in ngm.app (workflows, `package.json` scripts,
`lessons.md` restructuring, `TEST-ACCOUNTS.md`), the exact ticket text to create through PM
mode instead — the agent system never edits ngm.app from here. Group the patches:

- **A — quick wins**: ≤ 1 hour, no behaviour risk (trust flag pre-flight, background-agent
  guard, heredoc handling, probe script, size caps, launcher metrics, limit detection).
- **B — medium**: one session each (context restructure, design template + pattern catalogue,
  handoff/record dedupe, routing eval cases, release script, QA/security in parallel,
  same-context correction rounds).
- **C — structural**: needs my decision (local DB gate, routing/model changes, new or merged
  agents, CI changes that cost minutes, anything touching the prod gate's mechanics).

Include the "instructions from the user" patch: the PM skill's ticket template, the
standing-decisions register, the readiness checklist and the per-item confirmation default.

## Step 6 — Measurement → `retro/<date>/measurement.md`

Propose (as a patch) that `pm-run-issue.sh` appends one line per run to
`NGM_ROOT/.agent-context/pm-runs/metrics.csv` (issue, ts, model, outcome, turns, wall_s, cost,
output/cache-create/cache-read tokens, denials, rerun-of), and a `retro/metrics.js` that
prints the Step 1 tables from the JSONs and the CSV so the next retrospective costs nothing to
compute. Set targets for the next ten issues (e.g. first-run success, tokens per issue,
median `ready` → released) and say how #31 is updated.

## Constraints — my decisions; do not propose against them

Free tier only (no paid runners, services or plans; GitHub Pro is ruled out; Actions minutes
are the scarcest resource, so any new CI step states its minutes). `main` only — no PRs, no
branch protection. PROD only on my explicit yes to "Shall I deploy this to prod?", in those
words; never weaken `guard-prod.sh` or `prod-approval.sh`. One feature session at a time; the
batch is the unit of delivery; a `blocked` ticket is never started. Security review and RLS
work never below Opus. `lessons.md` and task records are owned and tracked by ngm.app and are
the audit trail. The installed copy in ngm.app is never edited directly; changes land here and
are installed. Model ids stay pinned. Do not re-propose what #39, #43 or RETROSPECTIVE.md
already fixed — check first.

## Working rules for this session

Keep your own tokens low: aggregate with node scripts and `Explore` (haiku) sweeps; `Read`
only the line ranges you need; never `cat` a log or a transcript; do not restate file
contents in the report; cite instead. Total written output across all deliverables ≤ 1,800
lines. If the #70 session is still running, note it and exclude its partial data from the
baseline. Never print secrets.

## Deliverables, then stop

`retro/<date>/baseline.md`, `team.md`, `findings.md`, `patches/NN-<slug>.md`,
`measurement.md`, and `SUMMARY.md` — one page: the top ten changes in order (system and team
changes together), each with the metric moved, the estimated effect, the effort and whether
it is mechanical or prose; plus the proposed team as a table (agent · model · owns · when
invoked · runs in parallel with) next to the current one. Then **stop** and ask me
which patch groups to apply. On my yes: apply in this repo only, run `bash scripts/validate.sh`,
commit one commit per patch group, run `powershell -File scripts/install-into-repo.ps1`, and
list the ngm.app tickets I should create through PM mode.
