# Agent evals

Two layers, deliberately different in cost.

## Layer 1 — deterministic (free, run every time)

`bash scripts/validate.sh` checks the configuration itself and the enforcement hooks, with
no model calls: agent frontmatter and models, standing-rules preload, ownership hooks
present, stale agent names, settings and hook wiring, and a table of block/allow cases for
`guard-prod.sh` (prod dispatch and rerun blocked without a recorded approval, admitted from
the main session with one, never from a subagent, expired approvals cleared; direct deploys
and force pushes always blocked) and `guard-paths.sh` (per-role file ownership). It runs in CI on this repo (`.github/workflows/validate.yml`).

These are the tests that answer "does an agent stop at the boundary of its authority?" —
because the boundary is enforced by a script, the test is a script.

## Layer 2 — routing (costs tokens, run deliberately)

`evals/routing-cases.json` holds task prompts with the expected routing decision: tier,
agents, parallelism, per-agent models, whether the Orchestrator does it itself, and where it
stops. `bash evals/run-routing-evals.sh` runs each case headlessly with the `ROUTE ONLY:`
prefix from `CLAUDE.md`, so the Orchestrator emits its plan as JSON and stops without
executing, then compares it with `expect`.

Cases cover: a trivial change stays with the Orchestrator on no model; a UI bug reaches
frontend-engineer on Sonnet; an RLS change reaches the architect and escalates the backend
to Opus with mandatory security review; a pipeline change reaches deployment-engineer; an
architectural migration is tier 4 and stops for the user; a prod release request is confirmed
with the user ("Shall I deploy this to prod?") and then done by the Orchestrator itself; a
third environment and a paid service are declined; pure code location goes to `Explore` on
Haiku.

Run with the model you use for the orchestrator session — routing quality belongs to that
model. Add a case whenever routing goes wrong in real use, with the prompt that caused it.
