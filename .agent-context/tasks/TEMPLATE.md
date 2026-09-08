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
- <date> — one line per event (agent returned / round N / pushed <sha> / check-dev PASS). ≤ 25 lines.

## Test Results
check-app summary line; QA status + count of findings; security status + count; check-dev line;
per-role DEV status matrix. ≤ 12 lines — the reviewers' full reports stay in their own returns.

## Remaining Risks
≤ 8 lines: what the user must know before PROD.

## Lessons Learnt
≤ 5 lines. The durable ones (usually 0–2) go to the lessons index as ONE line each with a
pointer to `lessons/<domain>.md`. A lesson that already exists becomes a gate, not a repeat.
Whole file target ≤ 12 KB; the READY FOR PROD comment is the report, not this file.

## Problems Spotted (out of scope for this task)
| Problem | Owner | Tier |
|---|---|---|
|  |  |  |
Each row is filed as its own GitHub issue labelled `claude` at COMPLETE (`pm-issue.sh new`); put the issue numbers here.
