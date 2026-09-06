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
| DEV / PROD authority | Claude / **User** |
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

**PROD — the user decides.** Claude never triggers a production deployment, never dispatches
`environment: prod`, never reruns a prod run, never bypasses or weakens a production control.
Claude may prepare production-ready code, inspect prod pipelines and configuration, assess
readiness, explain what would ship, identify risks, and — once the user starts a release —
monitor it, diagnose failures and assist with rollback.

```
DEV VALIDATED → READY FOR PROD (release notes + risks) → USER DEPLOYS → CLAUDE MAY MONITOR
```

Enforcement: the `.claude/hooks/guard-prod.sh` PreToolUse hook blocks prod dispatches,
prod reruns, direct `terraform apply`/`wrangler`/`supabase db push` and force pushes on every
agent. Nothing in GitHub enforces it (free plan), so the policy is absolute regardless.

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
