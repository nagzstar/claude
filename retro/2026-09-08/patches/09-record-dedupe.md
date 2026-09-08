# 09 — One canonical record; the issue comment is the report (B)

**Finding.** H10: the same evidence is written to the task file (9–45 KB), the READY FOR PROD
comment, a `lessons.md` section (+44 lines/task) and the final message; task files are then
re-read ≈ 5× per run (#55: 67 KB). ≈ 120 K output tokens over 16 runs plus the re-reads.

**Expected effect.** ≈ −10 K output and ≈ −40 K cache-create per issue; the record a future session
resumes from is short enough to read once.

## `TEMPLATE.md` — caps on the evidence sections

```diff
 ## Status / Log
-- <date> — what happened, decisions made, models used, escalations.
+- <date> — one line per event (agent returned / round N / pushed <sha> / check-dev PASS). ≤ 25 lines.
 
 ## Test Results
-check-app summary line; QA PASS/FAIL/WARNING summary; security-reviewer summary; check-dev result.
+check-app summary line; QA status + count of findings; security status + count; check-dev line;
+dev-probe matrix. ≤ 12 lines — the reviewers' full reports stay in their own returns, not here.
 
 ## Remaining Risks
-Anything unresolved, unverified, or deferred — including what the user must know before PROD.
+≤ 8 lines: what the user must know before PROD.
 
 ## Lessons Learnt
-What would be done differently, what surprised the team, what a future task must know.
-Durable ones are appended to `NGM_ROOT/.agent-context/lessons.md` at COMPLETE.
+≤ 5 lines. The durable ones (usually 0–2) go to the lessons index as ONE line each with a
+pointer to `lessons/<domain>.md`. A lesson that already exists becomes a gate, not a repeat.
```
Whole task file target ≤ 12 KB (warned by `check-app.sh`: `task=WARN` when a task file exceeds
16,000 bytes; not a failure — records may legitimately be longer for a batch).

## `pm-run-issue.sh` prompt — the comment is the report

```diff
 Finishing — before your final message
-- READY FOR PROD → \`pm-issue.sh status ${issue} ready-for-prod\` and a comment headed
-  "✅ READY FOR PROD" containing: commit sha(s), DEV pipeline run ids, what was validated on
-  DEV and how, release notes, risks, and the resume command above.
+- READY FOR PROD → \`pm-issue.sh status ${issue} ready-for-prod\` and ONE comment headed
+  "✅ READY FOR PROD" in the CLAUDE.md report format (Completed … Prod), ≤ 60 lines: commit
+  sha(s), DEV run ids, what was validated and how, release notes, risks, resume command.
+  Your final message is then two lines: "Report: <comment url>" and the Prod line. Do not
+  repeat the report in the chat, the task file or lessons.md.
```
and in CLAUDE.md `## Reporting to the user`, replace "End every task with this, and nothing longer"
with: "End every task with this (≤ 60 lines). In a headless session it is the READY FOR PROD
comment and nothing else is repeated." (no new lines; a rewrite of the existing sentence).

## `#31` row from the launcher
The PM no longer copies numbers: patch 04's `metrics.csv` line + `retro/metrics.js --issue <n>`
prints the #31 row (see `measurement.md`); the PM skill step 3 says "paste the printed row".
