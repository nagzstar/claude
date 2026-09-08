---
name: ngm-facts
description: Authoritative NextGenMaher (NGM) project facts — environments, dev/prod URLs, hosting, source control, CI/CD, database, free-tier limits, and the deployment authority boundary between Claude and the user. Load when working on NGM deployment, environments, hosting, pipelines, releases, cost questions, or to confirm who may deploy what. The compact table lives in CLAUDE.md; this is the detail behind it.
---

# NextGenMaher (NGM) — Core Project Facts

Source of truth for environment, cost and deployment facts. If repository code conflicts
with a fact here, **flag the discrepancy** rather than silently revising this document.

| Item | Value |
|---|---|
| Environments | local, dev, prod — only these |
| DEV / PROD URL | https://dev.nextgenmaher.com / https://nextgenmaher.com |
| Hosting | Cloudflare Pages, direct-upload (wrangler from CI); projects `ngm-dev`, `ngm-prod` |
| Source control / CI | GitHub `nagzstar/ngm.app`, GitHub Actions; GitHub Environments `dev`/`prod` scope secrets by name |
| Working branch | `main` — direct commit/push; no PR required; no branch protection (unavailable on the free plan, and not wanted) |
| Database | Supabase (dev `qcpeqygsfhhzegsvzikp`, prod `cuwnzdysvaroglqqxhhh`) |
| Infrastructure | Terraform on HCP Terraform, workspaces `ngm-dev` / `ngm-prod`, auto-apply off |
| Pipelines | Infrastructure (`terraform/**`) and application (`app/**`, `supabase/**`) — separate, by path filter |
| DEV / PROD authority | Claude / **User** — Claude asks "Shall I deploy this to prod?" and releases only on an explicit yes |
| Cost posture | Free or as close to free as possible — hard requirement |

## Cost — the free-tier design (verified 2026-09-06)

The only recurring cost in the stack is the `nextgenmaher.com` domain.

| Component | Plan | Relevant limit |
|---|---|---|
| GitHub | Free | private repo; limited monthly Actions minutes — the scarcest resource in the stack |
| HCP Terraform | Free | 500 managed resources |
| Supabase | Free | **2 projects** (dev + prod already use both); nano compute; projects pause after inactivity |
| Cloudflare | Free | Pages + DNS only; no Workers paid tiers, R2, KV, D1, WAF, Argo |

Ruled out unless the user approves the cost: a third Supabase project (so no test/staging
environment), `instance_size` on the Supabase project (paid compute — deliberately unset in
`terraform/modules/supabase/main.tf`), Supabase add-ons (PITR, extra compute, custom API
domains), paid Cloudflare products, self-hosted or larger runners, commercial CI/scanning/
monitoring products, and **GitHub Pro** — which would give branch protection and required
reviewers, and which the user has explicitly declined. That is why the production gate is
policy plus a local hook rather than a GitHub control.

Free tooling covers the known gaps: `npm audit`, Dependabot, and OSS Actions such as
tfsec/checkov/trivy. A dev validation failure may mean the free Supabase project is paused,
not that the code is broken — check that first.

## Deployment authority

**DEV — Claude acts autonomously.** Modify app, infrastructure and database code; commit and
push to `main` (the push triggers the dev deploy); trigger, rerun and monitor dev pipelines;
read logs; fix failures; redeploy; run QA and defensive security testing. Do not stop at
"the code is ready" and do not ask between intermediate dev steps:

```
CODE → REVIEW → COMMIT → PUSH → PIPELINE → DEV DEPLOYMENT → VALIDATION
```

**PROD — the user decides, every time; the Orchestrator carries it out.** Claude never
dispatches `environment: prod`, reruns a prod run, or weakens a production control on its own
initiative. When DEV is validated the Orchestrator reports **READY FOR PROD** with release
notes and risks and asks exactly **"Shall I deploy this to prod?"**, then waits. Only an
explicit yes in the conversation is approval — not silence, not "looks good", not an
instruction given before DEV was validated. On yes, the Orchestrator records the approval
(`bash .claude/scripts/prod-approval.sh grant <sha> "<the user's words>"`), dispatches the
prod workflows the change needs in order (`terraform-apply.yml` → `database-migration.yml` →
`deploy.yml`), watches each run, validates https://nextgenmaher.com read-only, revokes the
approval, records the release in the task file and reports **RELEASED TO PROD**. Specialists
never release; if the user says no or does not answer, the work stops at READY FOR PROD.

```
DEV VALIDATED → READY FOR PROD (release notes + risks) → "Shall I deploy this to prod?"
  → yes → prod-approval grant → dispatch prod → watch → validate prod → revoke → RELEASED TO PROD
  → no / silence → stop
```

Enforcement: the `.claude/hooks/guard-prod.sh` PreToolUse hook blocks every prod dispatch and
prod rerun unless a fresh approval (60 minutes) recorded by `prod-approval.sh` exists, and
always blocks them from a subagent; it blocks direct `terraform apply`/`wrangler`/`supabase db
push` and force pushes unconditionally. A hook "ask" decision cannot do this job: it is
ignored in auto and bypass modes and by the existing allow rules. Nothing in GitHub enforces
the boundary (free plan), so the policy of asking first is absolute regardless.

## Validating on DEV

`bash .claude/scripts/dev-probe.sh` signs in as `anon | participant | mentor | admin` from the
`NGM_DEV_*` environment variables (names in `TEST-ACCOUNTS.md`; values never in the repo) and
calls REST, RPC and storage on DEV, printing only statuses. `matrix <method> <path>` runs one
call as all four roles. Use it; never read `.env`, never write a probe script, never grep the
bundle for keys (all three were denied or reinvented on 2026-09-07).

## CI/CD principle

Everything deployed goes through a pipeline: `CODE → GITHUB → PIPELINE → ENVIRONMENT`. Never
deploy by hand when a workflow does the job; if a step is manual today, improve the pipeline.
Schema changes are migrations, version-controlled and pipeline-applied, never reproduced by
hand between environments. Workflow-by-workflow detail: `.agent-context/delivery.md`.

## Known discrepancies — do not silently "correct"

1. The repository was renamed from `ngm.terraform` to `ngm.app`; remote, repo name and local
   folder `C:/Users/nagaj/git/ngm.app` now agree. Resolved.
2. `main` has no branch protection and cannot have any on this plan; the user accepts this
   and works directly on `main`.
3. The production gate is therefore policy plus the local hook, not a GitHub control.
