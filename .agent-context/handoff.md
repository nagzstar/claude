# Handoff & Task File Formats

## Why

An agent's context is whatever the Orchestrator puts in it. The handoff *is* the context
budget. Too little and the agent explores blindly; too much and you pay for context it never
uses. Every specialist already has the standing rules preloaded (skill `ngm-standing-rules`)
and reads `project.md` itself — do not restate either.

## The rule

**Send references, not contents.** Agents can read files. Never paste source, conversation
history, another agent's raw report, full build logs, or `project.md`'s contents. Do forward:
decisions made, the agreed contract, a specific error message, the exact acceptance criteria.

## Handoff template

```
TASK:        one sentence.
TASK FILE:   .agent-context/tasks/<slug>.md   (read for full context)
TIER:        2 | 3 | 4   (model passed on the Agent call if above your default)
BASE COMMIT: <sha>       (reviewers diff against this)

GOAL:        what must be true when this is done, in user terms.

RELEVANT FILES:
  - path — why it matters / what to do there
  - path — read-only, for pattern reference

CURRENT BEHAVIOUR:  what happens today.
EXPECTED BEHAVIOUR: what should happen.

CONSTRAINTS:
  - patterns to follow, things not to change
  - files owned by another agent — read-only for you
  - cross-cutting files assigned to YOU for this task (else read-only): …

ARCHITECTURAL DECISIONS (already made — do not redesign):
  - data model / contract / authorization rule and where it is enforced

ACCEPTANCE CRITERIA:
  1. checkable statement
  2. checkable statement

OUT OF SCOPE: what not to do.
RETURN: COMPLETE | BLOCKED | NEEDS-DECISION, in your agent's report format. Do not commit.
```

Trim any section that is genuinely empty. Never pad.

## Sizing

- **Trivial** (one file, obvious) — the Orchestrator does it. No handoff, no task file.
- **Small** (one agent) — TASK, TIER, BASE COMMIT, GOAL, RELEVANT FILES, ACCEPTANCE CRITERIA.
- **Medium/large** — full template plus a task file.

## Parallel work

Only when tasks are genuinely independent. Write the contract **first**, put it in the task
file, then hand both agents the same contract with disjoint file ownership (the `guard-paths`
hook enforces the split, but name it anyway). If one agent needs the other's output, run
them in sequence — parallelising a dependency produces conflicting work and wasted tokens.
Both agents work in the same checkout; neither commits.

## Returning work for correction

Send the specific findings, not the whole QA report:

```
CORRECTION REQUIRED — <task>   (round N of 2)
Owner: <agent>
Findings:
  1. FAIL: <what, file:line, why>
  2. FAIL: <what, file:line, why>
Fix only these. Do not change anything else. Re-run check-app.sh and report.
```

After round 2 on the same finding, stop correcting: escalate the model one tier and re-run
the handoff, or take the specific blocker to the user.

## Task file

Create `.agent-context/tasks/<slug>.md` from `TEMPLATE.md` for medium and large work. Update
it as each agent returns — it is the shared memory between agents and across sessions, and
the resume point if a session is interrupted. When the task is done it becomes the record of
what was done and why.
