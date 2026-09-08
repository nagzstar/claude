# 16 — Model routing and team changes that need your decision (C)

Three changes, each independent. Evidence in `findings.md` (H7, F15) and `team.md`.

## C1 — Architect on Opus with a capped design; Fable reviews it

Today `researcher-architect.md` pins `model: claude-fable-5-1` (your 2026-09-07 experiment). The
one Fable design (#70) cost ≈ $12 list (84 K out, 225 K cc, 1.14 M cr) against an Opus average of
≈ $4.4, and was not exercised. The capped template (patch 08) shrinks any design ≈ 3×. Proposed:
Opus writes the ≤ 28 KB design; the same agent file in review mode on Fable (≤ 8 K out ≈ $1.5)
challenges the decisions and the authorization rule. Fable's judgement stays where it is cheap;
the long output goes to Opus. Expected ≈ $12 → ≈ $4.5 per design; +3 min wall.

```diff
--- a/.claude/agents/researcher-architect.md
+++ b/.claude/agents/researcher-architect.md
@@ -4,3 +4,3 @@
 tools: Read, Grep, Glob, Bash, Write, WebFetch, WebSearch
-model: claude-fable-5-1
+model: claude-opus-5
```
CLAUDE.md specialists table, `researcher-architect` row: default `claude-opus-5`; add to "Invoke
when": "then once more with `model: fable`, `MODE: review`, on tier 3/4 designs". Tier-4 work still
passes `model: fable` explicitly. Memory note (`agent-repo-uses-fable.md`) records the experiment;
this keeps "Fable on the design decision", moving it from writing to reviewing. If you prefer to
run the experiment as designed, skip C1 and re-judge after two batches on `metrics.csv`.

## C2 — PM conversation on Opus

`4c93ddd1` (2026-09-07, 10 h 21 m on Fable): 165 K out, 1.29 M cache-create, 40.4 M cache-read ≈
$97 list — the PM session cost more than the four most expensive feature runs together, mostly
cache-read from a long-lived context. Its work is launching, waiting, reading a result, one
judgement per item, and the release. Proposed: the PM conversation runs on `claude-opus-5` (the
installed `settings.json` already pins it; the Fable session was a manual `/model`). With patches
04, 09, 11 and 13 the PM makes far fewer turns, so the effect compounds. Nothing to diff: the
decision is "do not override the model for PM sessions" — recorded in `decisions.md` (patch 13)
and the PM skill's Boot section (one line).

## C3 — `fullstack-engineer` for small two-sided tickets

Evidence: #55 (3 files each side), #56 (frontend + a 3 KB `send-push` link change), #33-sized
tickets. Two engineers cost two boots (≈ 63 K cc each) and two handoffs for work one Sonnet context
does in one pass; review stays independent (QA + security unchanged), ownership stays hook-enforced.
Expected ≈ −70 K cc and −1 handoff (≈ −5 K out) per small ticket, −5 min wall.

New `.claude/agents/fullstack-engineer.md` (frontmatter; body = the two engineers' method sections
merged, ≤ 5 KB):

```yaml
---
name: fullstack-engineer
description: Implements a SMALL NGM change that spans app/src and supabase (≤ ~6 files, no new table, no RLS policy rewrite) in one context. Owns app/src/ and supabase/. Invoke only when the Orchestrator's contract fits on one screen; anything with a new policy or definer function goes to backend-engineer.
tools: Read, Edit, Write, Grep, Glob, Bash
model: claude-sonnet-5
effort: medium
skills:
  - ngm-standing-rules
  - app-deployment
  - db-deployment
hooks:
  PreToolUse:
    - matcher: "Edit|Write|MultiEdit|NotebookEdit"
      hooks:
        - type: command
          command: 'bash "$CLAUDE_PROJECT_DIR/.claude/hooks/guard-paths.sh" fullstack'
---
```

```diff
--- a/.claude/hooks/guard-paths.sh
+++ b/.claude/hooks/guard-paths.sh
@@ -76,6 +76,11 @@ case "$role" in
   deployment)
     is_task_file && exit 0
     printf '%s' "$rel" | grep -Eq '^\.github/' && exit 0
     deny ;;
+  fullstack)
+    is_task_file && exit 0
+    printf '%s' "$rel" | grep -Eq '^(\.github|\.claude|\.agent-context)/' && deny
+    printf '%s' "$rel" | grep -Eq '^claude\.md$' && deny
+    printf '%s' "$rel" | grep -Eq '^(app|supabase|terraform)/' && exit 0
+    deny ;;
```
`validate.sh` cases: `paths allow fullstack "$N/app/src/pages/X.tsx"`, `paths allow fullstack
"$N/supabase/migrations/x.sql"`, `paths block fullstack "$N/.github/workflows/deploy.yml"`.
CLAUDE.md "Smallest team": add "Small change on both sides, no new policy → fullstack-engineer →
qa-engineer (+ security-reviewer if it touches a trigger or function)". Routing eval: add
`small-two-sided-55` variant expecting `fullstack-engineer` once C3 is accepted. The guard in patch
02 must list `fullstack-engineer` among the engineers.
