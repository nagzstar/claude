# 13 — Instructions from the user: ticket template, standing-decisions register, readiness checklist, queue runner (B)

**Finding.** H14/F19/F20: standing decisions are scattered across four files (8 "(user decision,
2026-09-07)" notes); #68 was designed twice and paused twice by a mid-flight decision change
(≈ $18, 22 min, plus the user's time); the queue waits for the user (`ready` → start median 4.1 h)
because each item is confirmed one at a time; 50 `claude` issues were triaged by hand.

**Expected effect.** Decisions are assumed, not re-asked; a ticket cannot be `ready` with an open
product decision; the ready queue runs unattended (still one session at a time, still never prod);
a Haiku triage pass costs ≈ $0.10 instead of PM turns on Opus/Fable.

## 1. New file `.agent-context/decisions.md` (installed; ≤ 60 lines; the Orchestrator may assume these)

```markdown
# Standing decisions — dated, one line each; the Orchestrator assumes them without asking
- 2026-09-06 · Environments: local, dev, prod only; no staging/UAT (Supabase free plan: 2 projects).
- 2026-09-06 · PROD only on the user's explicit yes to "Shall I deploy this to prod?"; DEV autonomous.
- 2026-09-06 · Free tier only; GitHub Pro ruled out; Actions minutes are the scarcest resource.
- 2026-09-06 · `main` only, no PRs, no branch protection; infra and app pipelines never merged.
- 2026-09-06 · Agents use the DEV admin/mentor/participant accounts themselves (`NGM_DEV_*`).
- 2026-09-07 · Backlog = GitHub Issues; one fresh headless session per item; the batch is the unit of delivery.
- 2026-09-07 · A `blocked` ticket is never started; only the user lifts a block (status back to `ready`).
- 2026-09-07 · Delivery order is the pinned numbered sequence (#29), not P-buckets.
- 2026-09-07 · Overlapping tickets are consolidated, never delivered twice.
- 2026-09-07 · Fable: batch orchestrator, architect (review), security review of RLS/definer/trigger changes; engineers/QA/Explore never above the ladder.
- 2026-09-07 · Member-submitted content is moderated (P1) with anonymity enforced in the database, not the UI (#8 round 1).
- 2026-09-07 · Storage is private buckets + signed URLs with per-member caps (P2); no public buckets.
- 2026-09-07 · Problems spotted are filed as `claude` issues, never appended to lessons.md.
```
Move the scattered notes here: CLAUDE.md line 148 ("user decision, 2026-09-07; judged on …"),
PM skill lines 158–169 and 193–200, `pm-run-issue.sh` header lines 7–8 and 186–187, `pm-issue.sh`
line 21 — each becomes "(decisions.md)" — net −12 lines of prose across the boot-read files.

## 2. PM skill — ticket shape gains two sections and a readiness checklist

```diff
 ## Security & cost security surface (auth/roles/RLS/edge functions/user data: yes/no + what);
                    cost: free, or the figure and the free alternative
+## Pattern         P1–P5 from .agent-context/patterns.md, with deviations — or "none: needs a design"
+## Tier            2 | 3 | 4 and the one reason (drives models and whether an architect runs)
 ## Depends on      #refs, or "nothing"
```
Add after "Status: `needs-info` while you are still asking …" (line 95):

```markdown
**Ready means all of:** every Open question is empty **or** moved to Decisions with a date; the
data source and the authorization rule are decided (not "to be discussed"); Pattern and Tier are
filled; Depends-on items are `ready-for-prod` or released; the user has said "ready". A decision
changed after `ready` puts the ticket back to `needs-info` — a running session on it is stopped
first (`pm-run-issue.sh` pre-flight refuses a `needs-info` ticket).
```

## 3. Default: work through the ready items

PM skill step 1: replace "then ask **once** ("Start #N <title> now?")" with "then start it; ask
only when the next item is P2/P3 and nothing above it is ready, or when the user has asked to be
consulted per item. The user's standing instruction is 'work through the ready items'
(decisions.md)." Step 5 becomes: "Continue with the next ready item until the sequence is empty,
a session ends NEEDS-DECISION/BLOCKED, or the limit resets are being waited on."

`pm-run-issue.sh`: new option `--queue` (runs the pinned delivery order's ready items in sequence,
one session at a time, honouring the lock; exit 3 from a run → sleep until the printed reset time,
then continue; `needs-decision`/`blocked` → skip and continue; prod never). ≈ 25 lines: loop over
`pm-issue.sh list --ready-in-order` (new sub-command printing the sequence from #29), calling
itself per item without `--queue`.

## 4. Triage on Haiku before the PM conversation

PM skill Boot step: "Run `Explore` (`model: haiku`, read-only) over `pm-issue.sh list --all` with
the prompt: group `claude` issues that change the same file or function, flag duplicates by title
and body, propose batch membership per the surface; return a table. Then decide." The `Explore`
call is ≈ 70 K cc / 7 K out; the five manual consolidations of 2026-09-07 took ≈ 20 PM tool calls.

## 5. PM session model (C, see patch 16): the conversation ran on Fable for 10 h on 2026-09-07.
