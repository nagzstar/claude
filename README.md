# NGM Engineering Team

An orchestrated agent team for the **NextGenMaher** application
(`C:/Users/nagaj/git/ngm.app`). This repo is the configuration source of truth; the
application repo carries a gitignored, installed copy.

## How to use it

Run Claude Code from this directory (or from `ngm.app` after installing) and state the
**outcome** plainly:

```
Fix the mentor dashboard crash when a message has no responses.
Let participants save mentor responses as favourites.
Review the security of the admin user-management flow.
Add a smoke check after the dev deploy.
Make the participant message list usable on a phone.
```

The session you are talking to is the Orchestrator (`CLAUDE.md`). It classifies the work
into a tier, picks the smallest team and the right model for each piece, writes the contract,
delegates with scoped handoffs, reviews, integrates (commits and pushes to `main`), watches
the dev pipeline, validates on https://dev.nextgenmaher.com and reports **READY FOR PROD** —
or asks you when the decision is genuinely yours. You should not need to name agents or
manage context. To constrain it, say so ("frontend only", "investigate, don't implement").

## Architecture

```
User
 └─ Orchestrator (CLAUDE.md — your session model; Opus 5 recommended, Fable for tier-4 work)
     ├─ Explore (built-in, haiku)        locate code, sweep files
     ├─ researcher-architect (opus)      investigate + design; writes only .agent-context/
     ├─ backend-engineer (sonnet)        supabase/, terraform/
     ├─ frontend-engineer (sonnet)       app/src/
     ├─ deployment-engineer (sonnet)     .github/workflows/
     ├─ qa-engineer (sonnet)             independent functional verification; test files only
     └─ security-reviewer (opus)         independent authorization / RLS / pipeline-safety review; read-only
     scripts (no model): check-app.sh · check-dev.sh · context-drift.sh
     hooks   (no model): guard-prod.sh (PROD boundary) · guard-paths.sh (file ownership)
```

Lifecycle for every non-trivial task: `PLAN → DELEGATE → EXECUTE → VERIFY → REVIEW → INTEGRATE
→ COMPLETE`. Engineers never commit; the Orchestrator integrates after review.

## Model strategy

| Tier | Model | Used for |
|---|---|---|
| 1 | scripts, `Explore` on haiku | deterministic gates, locating code |
| 2 | claude-sonnet-5 | routine implementation on established patterns, functional QA, tests |
| 3 | claude-opus-5 | design, security review, existing-RLS or auth changes, pipeline gating/ordering |
| 4 | claude-fable-5-1 | replacing an architectural pattern, hard root-cause, anything a tier-3 attempt failed |

Defaults are in each agent's frontmatter; the Orchestrator raises a model per invocation
when the tier calls for it, and escalates one tier after two failed correction rounds.
Security review and RLS work never run below Opus. The orchestrator session is pinned per
repo in `.claude/settings.json`: `claude-fable-5-1` here, where a change to the system shapes
every future session, and `claude-opus-5` in the copy installed into `ngm.app` (switch to
Fable with `/model` for a tier-4 task); Sonnet specialists run at `effort: medium` for cost
and speed, with Opus as the escalation when a result is thin.

A **mobile version** is on the roadmap (see `project.md`); its approach is a tier-4 decision
made with you before any code, so no mobile agent exists yet.

## Safety rails that are enforced, not just written

- **`.claude/hooks/guard-prod.sh`** blocks, for every agent and model: any workflow dispatch
  or API dispatch naming prod, rerunning a run with a prod job, direct `terraform apply` /
  `wrangler` / `supabase db push`, and force pushes.
- **`.claude/hooks/guard-paths.sh`** blocks each specialist from editing files outside its
  ownership (so QA cannot fix what it reviews and two engineers cannot touch the same file).
- **`.claude/settings.json`** keeps the deny list as a second layer and allows the routine
  dev commands so they do not prompt.

GitHub cannot enforce the prod gate on a private free-plan repo, so the hook plus policy is
the control. **PROD is yours**: the team stops at READY FOR PROD with release notes and risks.

## Cost

NGM must stay **free or as close to free as possible** — a hard requirement. Every component
is on a free tier; the only recurring cost is the `nextgenmaher.com` domain. No agent adopts
a paid plan, add-on, runner or service without asking you and stating the free alternative.

## Layout

```
CLAUDE.md                          Orchestrator contract (always in context)
.claude/agents/*.md                Six specialists — model, tools, ownership hook, role prompt
.claude/skills/ngm-standing-rules  Rules preloaded into every specialist (single source)
.claude/skills/ngm-facts           Environment, cost and deployment-authority facts
.claude/skills/ngm-feature-prompt  How to write a pasteable multi-phase feature prompt (prompts/)
.claude/hooks/                     guard-prod.sh, guard-paths.sh
.claude/scripts/                   check-app.sh, check-dev.sh, context-drift.sh
.claude/settings.json              Permissions + the prod guard hook
.agent-context/project.md          Architecture summary — read instead of re-exploring
.agent-context/security-model.md   Roles, RLS, the dual-role-system hazard
.agent-context/delivery.md         Pipelines, environments, gaps (delivery work only)
.agent-context/baseline.json       Accepted lint/test state of main (read by check-app.sh)
.agent-context/handoff.md          Delegation, correction and task-file formats
.agent-context/tasks/              Per-task shared state and resume point (tracked in both repos)
.agent-context/lessons.md          Cumulative lessons learnt + backlog of problems spotted (tracked)
prompts/                           Feature prompts the user pastes to start large, multi-phase work
evals/                             Routing cases + runner (costs tokens); see evals/README.md
scripts/validate.sh                Deterministic self-test (free) — also runs in CI
scripts/install-into-repo.ps1      Deploy the system into the NGM repo (gitignored there)
```

## Where records live

Task files and `lessons.md` are written to whichever repo the session was started in, and
are tracked in both. Because they are the project's audit trail and backlog, **prefer
starting sessions inside `ngm.app`** (after installing) so the records travel with the code.

## Maintenance

- `bash scripts/validate.sh` before committing a change here. It checks frontmatter, models,
  hooks, references and the guard scripts' block/allow tables.
- After changing any agent, skill, hook or script: `powershell -File scripts/install-into-repo.ps1`
  to refresh the copy in `ngm.app`. Never edit the installed copy.
- `project.md`, `security-model.md` and `delivery.md` change only when architecture changes.
  `bash .claude/scripts/context-drift.sh` shows whether their sources moved since they were
  verified. Keep them short — they are read on every task.
- Lint/test baseline: only `check-app.sh --update-baseline`, after a deliberate clean-up you
  have agreed to.
- Model IDs are pinned (`claude-sonnet-5`, `claude-opus-5`, `claude-fable-5-1`). When a new
  generation ships, update the frontmatter and the approved set in `scripts/validate.sh`.
