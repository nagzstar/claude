# <Task name>

Status: NOT STARTED | IN PROGRESS | IN REVIEW | BLOCKED | DONE
Owner: Orchestrator
Tier: 2 | 3 | 4   (models actually used are logged below)
Base commit: <sha of NGM main when work started>
Issue: #<n> (when started from the backlog; otherwise "none")
Updated: <date>

## Goal
One paragraph, in user terms.

## Acceptance Criteria
1.
2.
3.

## Architecture Decisions
Data model, API/contract, authorization rule (who may create/read/update/delete/approve) and
where it is enforced, frontend vs backend responsibility, migration strategy and
compatibility with the deployed frontend, mobile behaviour.
Decided once, here. Implementing agents follow this rather than redesigning.

## Relevant Files
| Path | Role | Owner |
|---|---|---|
|  |  |  |

## Agent Assignments
| Agent | Model | Scope | Status |
|---|---|---|---|
|  |  |  |  |

## Lifecycle
- [ ] PLAN — criteria, tier, contract, ownership written
- [ ] DELEGATE — handoffs sent
- [ ] EXECUTE — engineers COMPLETE
- [ ] VERIFY — qa-engineer PASS; security-reviewer PASS (if required)
- [ ] REVIEW — quality gate applied; corrections ≤ 2 rounds
- [ ] INTEGRATE — committed <sha>, pushed, check-dev PASS, behaviour validated on DEV
- [ ] COMPLETE — reported; context files updated if architecture changed

## Status / Log
- <date> — what happened, decisions made, models used, escalations.

## Test Results
check-app summary line; QA PASS/FAIL/WARNING summary; security-reviewer summary; check-dev result.

## Remaining Risks
Anything unresolved, unverified, or deferred — including what the user must know before PROD.

## Lessons Learnt
What would be done differently, what surprised the team, what a future task must know.
Durable ones are appended to `NGM_ROOT/.agent-context/lessons.md` at COMPLETE.

## Problems Spotted (out of scope for this task)
| Problem | Owner | Tier |
|---|---|---|
|  |  |  |
Each row is filed as its own GitHub issue labelled `claude` at COMPLETE (`pm-issue.sh new`); put the issue numbers here.
