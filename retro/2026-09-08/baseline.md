# Baseline — NGM agent system, deliveries of 2026-09-06/07

Sources: 16 headless runs with a log (14 with a result JSON) under `NGM_ROOT/.agent-context/pm-runs/`,
their 16 main transcripts and 66 subagent transcripts, GitHub (77 issues, timelines, 78 Actions
runs), both git logs, the task files. Scripts used (scratchpad, not committed): `agg-runs.js`,
`agg-transcripts.js`, `analysis.js`, `gh-pull.js`/`gh-summary.js`, `baseline.js`. Log times are
**UTC**; git and file mtimes are BST (UTC+1). No run was in progress (no `.pm-run.lock`).

Arithmetic conventions. Tokens per agent come from each transcript's `message.usage`, counted once
per `message.id` (stream-json repeats the usage on every content block; without the de-dupe the
sums are 1.7–2.3× too high). Per-run totals agree with the JSON `modelUsage` within 2 % (#4:
transcripts 311 K out / 1.58 M cache-create vs JSON 315 K / 1.58 M). Wall time = first
timestamped log line → `RESULT` line (or last line). "Boot cost" = an agent's tokens before its
first Edit/Write or first non-read-only Bash (check-app, tests, git, gh, curl, node). Bytes read =
length of the tool results returned to that agent, attributed to the file named in the Read or
`cat`/`sed` command. Costs are the JSON's notional `total_cost_usd` (list price).

## 1. Per issue (runs summed)

| issue | runs | 1st run | cost $ | Opus out/cc/cr | Sonnet out/cc/cr | other out/cc/cr | turns | wall min | design KB | task KB | corr. rounds | QA FAIL / sec FAIL | pipeline runs / min | ready→start h | start→RFP h | RFP→released h | escaped defects |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| #1 | 1 | ok | 21.10 | 125K/366K/23.1M | 56K/221K/9.7M | haiku 8K/63K/617K | 3 | 31 | – | 28.9 | 1 | 1 / 0 | 3 / 3.0 | 2.3 | 0.4 | 8.8 | – |
| #3 | 1 | ok† | 28.01 | 273K/858K/17.1M | 124K/504K/20.4M | – | 12 | 70 | 67.5 | 13.5 | 1 | 0 / 1 | 2 / 1.7 | 2.8 | 1.3 | 7.5 | #60 |
| #4 | 1 | ok | 36.58 | 288K/1.29M/36.8M | 26K/292K/4.8M | – | 14 | 54 | 67.6 | 22.9 | 1 | 0 / 0 | 2 / 1.9 | 1.3 | 0.9 | 9.4 | #33 #32 #57 |
| #6 | 1 | ok | 5.79 | 38K/100K/4.5M | 38K/160K/3.4M | haiku 5K/46K/467K | 57 | 32 | – | 12.7 | 1 | 1 / 0 | 1 / 1.3 | 6.6 | 0.5 | 4.4 | – |
| #8 | 2 | ok†‡ | 40.10 | 360K/1.23M/33.5M | 99K/571K/15.1M | – | 83 | 102 | 77.8 | 45.3 | 2 | 0 / 1 | 2 / 1.9 | 7.2 | 1.7 | 2.7 | #47 |
| #12 | 2 | LOST | 57.08 | 524K/2.06M/52.8M | 64K/351K/8.1M | – | 20 | 113 | 80.7 | 31.8 | 2 | 0 / 1 | 4 / 4.1 | 8.9 | 1.7 | 0.9 | – |
| #13 | 2 | LOST | 44.53 | 401K/1.66M/38.3M | 55K/507K/8.8M | – | 64 | 83 | 62.3 | 10.8 | 2 | 0 / 1 | 2 / 1.9 | 4.1 | 2.5 | 4.9 | – |
| #33 | 1 | ok | 7.79 | 80K/256K/6.0M | 25K/69K/1.6M | – | 49 | 27 | – | 18.5 | 0 | 0 / 0 | 1 / 0.6 | 4.0 | 0.4 | 4.9 | – |
| #55 | 2 | LOST | 23.57 | 254K/1.06M/33.5M | 71K/480K/12.0M | – | 127 | 71 | – | 25.0 | 0 | 0 / 0 | 2 / 2.2 | 1.7 | 1.2 | 0.9 | – |
| #56 | 2 | LOST | 19.72 | 167K/601K/16.5M | 38K/204K/8.3M | haiku 9K/103K/549K | 64 | 57 | – | 9.2 | 0 | 0 / 0 | 2 / 2.3 | 4.3 | 1.1 | 3.0 | – |
| #70 (#68) | 1 | LOST | n/a | – | 0.7K/79K/91K | **Fable** 104K/356K/2.1M | – | 22 | 55.3 | 12.8 | 0 | – | 0 | – | – | – | – |
| **total** | 16 | 4 clean / 2 † / 5 lost | **284.25** | 2.41M/8.91M/254M | 581K/3.19M/89M | | | 662 | | | 11 | 2 / 5 | 21 / 21 | | | | 6 |

† `Background tasks still running after 600s; terminating` appeared **after** the RESULT line: the
issue was delivered but subagents were still running when the process was killed (their tokens are
in the JSON; their work after the orchestrator's final message was discarded).
‡ #8's first run ended with DEV validation outstanding; a second 25-min orchestrator-only run
(`issue-8-…T092501Z`, $6.16) did the validation, and that session was then resumed interactively
until 13:22 UTC (transcript `4099a182`).

Lost runs (F-run), what was lost and what it cost:

| run (UTC) | how it ended | lost | rerun |
|---|---|---|---|
| #13 05:01 | `You've hit your session limit · resets 7:30am` ×3 at 05:25–05:27 (log lines 133–136); JSON says `success`, 53 turns | $10.06, 26 min; design saved by the user (`edb6a0b`, 07:34 BST) | 06:36, after **69 min** idle; 58 min, $34.48 |
| #12 09:50 | orchestrator ended its turn at 10:33:56 with both engineers backgrounded; `…terminating` at 600 s | $20.33, 43 min; 3,848 uncommitted lines rescued by hand (`47251bf`) | 10:35; 69 min, $36.74 |
| #55 13:55 | no RESULT; last line 14:05:04; both engineers backgrounded; partial diff saved by hand (`issue-55-partial-*`, 15:05 BST) | ≈$6 (transcript: 53 K out, 307 K cc, 5.3 M cr), 9 min | 14:10; 62 min, $23.57 |
| #56 17:21 | architect's design heredoc failed `ENAMETOOLONG: name too long, uv_spawn` at 17:31:49 (30 KB command line); orchestrator ended turn at 17:33:39 "waiting"; `…terminating` | $4.17, 12 min; design never reached disk | 17:43; 44 min, $15.54 |
| #70 22:30 | user stopped it at 22:52 ("save work and stop", session `ea036997`) right after the Fable design; two launcher attempts at 22:25 and 22:30:10 left prompt files only | ≈$18 list (Fable 104 K out), 22 min; design preserved by hand (`730df20`) | not yet |

Sum lost ≈ **$58 and 112 min** of runs, plus 233 min of reruns and 69 min waiting for the limit.
F-run rate: 5 of 16 runs (31 %); clean first-run success 4 of 11 issues (36 %).

## 2. Where the tokens go

| model | out | cache-create | cache-read | cost | share | cost split out / cc / cr (list price) |
|---|---|---|---|---|---|---|
| claude-opus-5 | 2.41 M | 8.91 M | 253.7 M | $252.01 | 89 % | 25 % / 23 % / 52 % |
| claude-sonnet-5 | 581 K | 3.19 M | 89.4 M | $31.66 | 11 % | 18 % / 25 % / 56 % |
| claude-haiku-4-5 | 23 K | 212 K | 1.6 M | $0.57 | 0 % | |

Per delivered issue (10, excluding #70): out ≈ 317 K, cache-create ≈ 1.3 M, cache-read ≈ 35 M,
cost ≈ $28 (median $25). The user's estimate (cache-read ≈ half, cache-create ≈ quarter) holds.

Per agent type, averaged over invocations (16 orchestrator, 66 subagents):

| agent | n | models | out | cc | cr | bytes read | boot cc | boot tools | wall s | tool calls | ctx/design/task/code bytes read | reads lessons / project / security-model / design (invocations) |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| orchestrator | 16 | opus 15, fable 1 | 56 K | 172 K | **8.9 M** | 178 K | 22 K | 0 | 3,130 | 66 | 46K / 26K / 8K / 37K | 14 / 16 / 11 / 8 |
| researcher-architect | 7 | opus 6, fable 1 | **70 K** | 253 K | 2.2 M | 224 K | 58 K | 8 | 978 | 36 | 39K / 0 / 5K / 77K | 3 / 6 / 7 / 0 |
| security-reviewer | 10 | opus 10 | 39 K | 195 K | 3.0 M | **229 K** | 48 K | 4 | 758 | 38 | 22K / 19K / 9K / 115K | 1 / 0 / 9 / 4 |
| frontend-engineer | 16 | opus 6, sonnet 10 | 33 K | 150 K | 4.6 M | 148 K | 65 K | 10 | 552 | 50 | 6K / 30K / 4K / 68K | 0 / 6 / 0 / 7 |
| backend-engineer | 15 | opus 13, sonnet 2 | 25 K | 112 K | 2.0 M | 111 K | 63 K | 6 | 439 | 25 | 1K / 37K / 7K / 43K | 1 / 0 / 0 / 9 |
| qa-engineer | 15 | sonnet 14, opus 1 | 25 K | 153 K | 4.0 M | 170 K | 64 K | 9 | 796 | 49 | 4K / 29K / 15K / 76K | 0 / 4 / 1 / 6 |
| Explore | 3 | haiku 3 | 7 K | 71 K | 544 K | 169 K | 71 K | 29 | 88 | 29 | 0 / 0 / 0 / 158K | – |

- The orchestrator's cache-read (16 × 8.9 M = 142 M) is **40 % of all cache-read**: a 66-call
  context re-read on every turn. #55's rerun: 126 tool calls, 127 turns, 21 M cache-read.
- Boot cost (system prompt + preloaded skills + context reads before the first action) summed over
  all 82 invocations ≈ 4.4 M cache-create = **34 % of all cache-create**.
- Bytes read across all agents 13.78 MB: code 5.63 MB (41 %), design docs 2.06 MB (15 %), context
  files 1.40 MB (10 %), task files 0.65 MB (5 %), other tool output (git, gh, tests) 29 %. Files read
  by **more than one agent in the same run: 8.29 MB = 60 %** of all bytes read (§4).
- Bytes written: code 978 KB (52 %), design docs 414 KB (22 %), scratch comments/reports/probes
  292 KB (15 %), task files 194 KB (10 %), lessons.md 3 KB. All writes ≈ 470 K tokens = 15 % of
  output; the other 85 % is thinking (#4: 84 K of 288 K Opus output), chat text and tool arguments.
- Architect output per design: 46–105 K tokens (Opus), 84 K (Fable, #70). Fable architect list cost
  ≈ $12 vs Opus architect average ≈ $4.4 (70 K out, 253 K cc, 2.2 M cr).

Interactive sessions on 2026-09-07 (not in any run JSON): the PM conversation `4c93ddd1` ran on
**Fable** for 10 h 21 m (223 messages, 165 K out, 1.29 M cache-create, **40.4 M cache-read** ≈ $97
list) and `012dc5ab` on Opus for 8 h 35 m (163 K out, 1.12 M cc, 42.6 M cr ≈ $32). The PM overhead
(≈ $129) is 45 % on top of the $284 spent by the feature runs.

## 3. Time

| phase | median | range | note |
|---|---|---|---|
| `ready` → run start | 4.1 h | 1.3–8.9 h | queue: one session at a time, user-paced |
| run wall (delivered runs) | 55 min | 27–77 min | design phase 13–21 min of it when an architect ran |
| rerun after a lost run | 58 min | 44–69 min | 4 reruns; #13 also waited 69 min for the limit reset |
| `ready-for-prod` → RELEASED | 4.4 h | 0.9–9.4 h | the 7 overnight features were released together at 12:30 UTC |
| release procedure itself | 4 min | 3–7 min | 6–17 tool calls, 4–20 K output tokens per release (from the PM transcripts) |
| `needs-decision` → `ready` | – | – | zero headless `needs-decision` stops; #68 was paused twice by a mid-flight decision change |

Pipeline: 27 Actions runs on 09-07, **0 failures, 1 rerun** (#55 Database Migration attempt 2:
`supabase/setup-cli@latest` rate limit), 28.5 minutes in total (≈ 2 min per issue; 1.4 % of the
monthly free 2,000). F-pipeline ≈ 4 %. F-validation: no green-but-dead case in this batch; #8 and
#12 both committed "DEV validation outstanding" records before validating (`b3b3d8d`, `536fad4`).

## 4. System-wide counts

- **Allow list inert in every run**: 16/16 logs open with `Ignoring 32 permissions.allow entries …
  this workspace has not been trusted`; `~/.claude.json` has `hasTrustDialogAccepted=false` for
  both `c:/…/ngm.app` and `C:/…/ngm.app`. Permission denials (14 JSONs): 9 — `.env` reads 5 (#3 ×2,
  #13, #8, #33), heredoc writes 2 (#13 design, #55 issue body), a prod probe `curl` (#13), a JWT grep
  on the bundle (#56).
- **Background delegation**: `run_in_background: true` on 60 of 71 Agent calls before the 17:42 BST
  prompt fix; 0 of 7 after it (#56 rerun, #70). Ceiling message in 4 runs (#3, #8 after delivery;
  #12, #56 fatal). `session limit`: 1 run (#13). `has not been trusted`: 16.
- **Heredoc file writes**: attempted in 6 runs; failed 3 times (guard-prod #13 05:18; guard-prod #55
  15:04; `ENAMETOOLONG` #56 17:31; #55 14:18 "exceeded the command-length limit"); rewritten with
  Write each time except #56 (lost). Cost of a failed design heredoc ≈ the doc's output tokens
  (15–20 K) plus the retry.
- **Context reads per run**: orchestrator reads `project.md` 16/16, `lessons.md` 14/16 (64.7 KB;
  exceeds the Bash output cap, so #12 read it 3 times in 9 s — log lines 9–11 — and #70 re-read the
  saved tool result twice), `security-model.md` 11/16. Subagents re-read `project.md` in 16
  invocations, `security-model.md` 17, `lessons.md` 5, the design doc 26. Orchestrator boot ≈
  105–120 KB read before the first action.
- **Duplicate reads per run** (same file, >1 agent): #8 1.66 MB (design ×7 = 539 KB, migration
  ×7 = 313 KB); #3 1.20 MB (design ×6 = 337 KB, migration ×6 = 241 KB); #12 rerun 942 KB; #4 697 KB
  (design ×5 = 291 KB). Whole-dataset 8.29 MB ≈ 2.1 M tokens of cache-create (16 % of all cc).
- **Agent calls by type:model** (78): backend-engineer opus 13 / sonnet 2; frontend-engineer opus 6 /
  sonnet 6 / default 4; qa-engineer sonnet 10 / default 4 / opus 1; security-reviewer opus 10;
  researcher-architect opus 6 / fable 1; Explore haiku 3.
- **Correction rounds by engineer model** (task files): frontend Sonnet 1.0 avg (#1, #3, #6, #43: 1
  each; #8: 2; #55: 0); frontend Opus 1.25 (#4: 1, #12: 2, #13: 2, #56: 0); backend Opus 0.6 (#3,
  #4, #8, #12, #13: 1 each; #1, #33, #55: 0). Every security FAIL (#3, #8, #12, #13) was an
  authorization/design-level finding in Opus-backend work.
- **QA and security**: dispatched in parallel (≤ 60 s apart) in 8 of 9 runs that had both; #33 ran
  them 8 min apart in the foreground.
- **lessons.md growth**: +60, +59, +81, +32, +36, +51, +22, +28, +46, +55, +14 lines over 11 tasks
  (avg **+44 lines/task**); 750 lines, 64.7 KB today. `"(user decision, 2026-09-07)"` notes live in
  CLAUDE.md (1), the PM skill (3), `pm-run-issue.sh` (3), `pm-issue.sh` (1).
- **Installed copy vs source**: identical except `settings.json` (intended: model,
  `additionalDirectories`, formatting) and `RETROSPECTIVE.md` (one stale line in ngm.app; the
  installer never syncs skills-root files). No manifest.
- **Local tooling**: no Docker, WSL, `supabase` CLI or `psql` on this PC; Claude Code 2.1.261.

## 5. Escaped defects (found by a later session)

#33 (avatar of a deactivated member stays readable — from #4; security, released as a fix), #32
(over-long bio blocks admin edits — #4), #57 (stale `types.ts` — #4/#43), #47 (`get_public_success_
stories()` has no ORDER BY — #8), #60 (stale "Auto-rejected" label — #55/#3), #36 (mock mentor seed
— #1, filed by its own session 12 min before READY). Six escapes over 10 features; 44 other `claude`
issues were filed by the delivering session itself (Problems Spotted working as designed).
