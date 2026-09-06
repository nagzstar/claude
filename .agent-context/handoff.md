# Handoff & Task File Formats

## Why

An agent's context is whatever the Orchestrator puts in it. The handoff *is* the context budget. Get it wrong in either direction and the system degrades: too little and the agent explores the repo blindly; too much and you pay for context it never uses.

## The rule

**Send references, not contents.** Agents can read files. Pasting source into a prompt duplicates it into two context windows.

Bad — pastes 2,000 lines the agent will read anyway:
> Here is AuthContext.tsx: `import React...` (2,000 lines)

Good — 3 lines, same information:
> Inspect:
> - `app/src/contexts/AuthContext.tsx` — add the mutation here, follow `addResponse`
> - `supabase/migrations/20260318010735_*.sql` — existing RLS pattern

Never forward: conversation history, another agent's raw report, full build logs, `project.md`'s contents (reference it by path — agents read it themselves).

Do forward: decisions made, the agreed contract, a specific error message, the exact acceptance criteria.

## Handoff template

```
TASK:        one sentence.
TASK FILE:   .agent-context/tasks/<slug>.md   (read for full context)

GOAL:        what must be true when this is done, in user terms.

RELEVANT FILES:
  - path — why it matters / what to do there
  - path — read-only, for pattern reference

CURRENT BEHAVIOUR:  what happens today.
EXPECTED BEHAVIOUR: what should happen.

CONSTRAINTS:
  - patterns to follow, things not to change
  - files owned by another agent — read-only for you

ARCHITECTURAL DECISIONS (already made — do not redesign):
  - data model / contract / authorization rule

ACCEPTANCE CRITERIA:
  1. checkable statement
  2. checkable statement

OUT OF SCOPE: what not to do.
```

Trim any section that is genuinely empty. Never pad.

## Sizing

- **Trivial** (one file, obvious) — the Orchestrator does it. No handoff.
- **Small** (one agent) — TASK, GOAL, RELEVANT FILES, ACCEPTANCE CRITERIA. No task file needed.
- **Medium/large** — full template plus a task file.

## Parallel work

Only when tasks are genuinely independent. Write the contract **first**, put it in the task file, then hand both agents the same contract and disjoint file ownership. If one agent needs the other's output, run them in sequence — parallelising a dependency produces conflicting work and wasted tokens.

## Returning work for correction

Send the specific findings, not the whole QA report:

```
CORRECTION REQUIRED — <task>
Owner: <agent>
Findings:
  1. FAIL: <what, file:line, why>
  2. FAIL: <what, file:line, why>
Fix only these. Do not change anything else. Re-run build/lint/test and report.
```

## Task file format

Create `.agent-context/tasks/<slug>.md` from `TEMPLATE.md` for medium and large work. Update it as each agent returns — it is the shared memory between agents and across sessions, and it means a later agent can be handed one path instead of a re-explanation. When the task is done it becomes the record of what was done and why.
