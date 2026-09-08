# 07 — Context restructure: lessons index + per-domain files, skills as checklists, forward ≤ 5 lessons (B)

**Finding.** H8: `lessons.md` (750 lines) is read by the Orchestrator in 14/16 runs (≈ 16 K tokens,
re-read when it overflows the Bash cap) and by 5 subagents; the deployment skills (10–11 KB each)
are preloaded into engineers and their "Lessons learnt / Known problems / Open questions / Last
synced" sections (≈ 55 lines each) duplicate `lessons.md`; backend boots with 22 KB of skill text.

**Expected effect.** Orchestrator boot ≈ 110 KB → ≈ 45 KB (−15 K cache-create, −2 tool calls);
engineer boot −5 K cc each (31 boots/16 runs); lessons stop being a growing file everyone reads.
Net fixed context: **smaller** than today (this patch deletes more than it adds).

## 1. `lessons.md` → index + domain files (ngm.app owns it: ticket T3 in patch 14)

Target shape, enforced by `check-app.sh` (patch 06, `LESSONS_MAX_LINES=120`):

```
# NGM — Lessons index            (≤ 80 lines of lessons + the rules below)
One line per lesson: date · task · **rule** → detail file#anchor. A lesson that recurs twice
becomes a gate (script/hook/template cap), not a line; note the gate here and delete the line.
## Database   → .agent-context/lessons/database.md
## Application → lessons/application.md
## Infrastructure and pipelines → lessons/delivery.md
## Process → lessons/process.md
## Problems spotted → GitHub issues labelled `claude` (nothing here)
```
The per-task sections (lines 238–750 today) move under the four domain files; the 14 lessons that
are already gates (check-dev, typecheck, heredoc, resume check, Write tool) are deleted with a
pointer to the gate.

## 2. Who reads what (CLAUDE.md boot; the Orchestrator forwards)

```diff
--- a/CLAUDE.md
+++ b/CLAUDE.md
@@ -39,9 +39,10 @@
 ## Boot and resume (before delegating anything)
 
-1. Read `.agent-context/project.md` and `NGM_ROOT/.agent-context/lessons.md` — always. Read
-   `security-model.md` only if the task touches auth, roles, permissions, user data or admin
-   features; `delivery.md` only for CI/CD, deployment, environment or release work.
+1. Read `.agent-context/project.md` and the **lessons index** `NGM_ROOT/.agent-context/lessons.md`
+   (≤ 120 lines; never the `lessons/` detail files — the specialist that needs them loads them via
+   its skill). Read `security-model.md` only if the task touches auth, roles, permissions, user
+   data or admin features; `delivery.md` only for CI/CD, deployment, environment or release work.
+   Every handoff carries the ≤ 5 index lines that apply to that agent's files, verbatim.
```
And in `handoff.md`'s template, after CONSTRAINTS: `LESSONS THAT APPLY (≤ 5, from the index): …`.

## 3. Deployment skills → checklists (delete, do not add)

In each of `app-deployment`, `db-deployment`, `infra-deployment` `SKILL.md`: delete the sections
`## Lessons learnt`, `## Known problems`, `## Open questions`, `## Last synced` (app: lines
103–160; db: 102–166; infra: 98–166) and replace with one line: `Lessons and known problems:
NGM_ROOT/.agent-context/lessons.md (index) → lessons/<domain>.md.` Keep Precedence, Prerequisites,
Procedure, Verification, Rollback. Expected sizes: app ≈ 5.5 KB, db ≈ 5.5 KB, infra ≈ 6 KB (cap
them at 7,000 in `validate.sh` section 7 once done, 4,000 after a second pass that turns Procedure
into a numbered checklist).

## 4. Specialists load their domain lessons (agent frontmatter, no new prose)

`backend-engineer.md` skills: keep `db-deployment`, `infra-deployment`; `frontend-engineer.md`:
keep `app-deployment`. Each skill's Procedure step 1 already says "read project.md"; add one line
after it: `2. Read NGM_ROOT/.agent-context/lessons/<domain>.md (≤ 150 lines) — the lessons for
your files.` (database.md for db-deployment, application.md for app-deployment, delivery.md for
infra-deployment.)

## 5. `RETROSPECTIVE.md` and `handoff.md`

`RETROSPECTIVE.md` moves out of the skills tree (patch 15). `handoff.md` stays; its "Returning work
for correction" block changes in patch 12.

## What is deleted from files read at boot
CLAUDE.md: net −0 lines (the boot step is rewritten in place). Skills: −55 lines each ×3. lessons.md
at boot: −630 lines. Handoff template: +1 line.
