# NGM — Delivery & Pipeline Model

Last verified: 2026-09-06 against `.github/workflows/*` and `terraform/`.
Read this **only** for CI/CD, deployment, release or environment work. It is not needed
for ordinary feature or bug tasks.

## Repository layout — one repo, two delivery paths

NGM is a **monorepo**, not split infra/app repositories. `terraform/` and `app/` live in
`nagzstar/ngm.app` together. The separation the project wants is therefore enforced by
**path-based triggers**, and it already works. Do not propose splitting the repository,
and do not merge the pipelines.

| Path | Pipeline | Workflows |
|---|---|---|
| `terraform/**` | Infrastructure | `terraform-plan.yml`, `terraform-apply.yml` |
| `app/**` | Application | `deploy.yml` |
| `supabase/migrations/**`, `supabase/functions/**` | Application (DB) | `database-migration.yml` |

Environments are **local, dev, prod only**. Never add test/staging/UAT/preview.

## Infrastructure pipeline (verified)

**`terraform-plan.yml`** — triggers on PR and push to `main` under `terraform/**`, plus manual.
Matrix over `[dev, prod]`. Steps: `fmt -check -recursive` → `init` → `validate` → `plan`,
then posts the plan as a PR comment (truncated to the last 60 kB). `shell: bash` is set
explicitly so `-o pipefail` makes a failed `plan | tee` actually fail — do not remove that.
`continue-on-error` on the plan step exists so the comment is still posted; a following step
re-fails the job. **Never applies from a PR.** Correct as designed.

**`terraform-apply.yml`** — `workflow_dispatch` only, environment choice `dev`/`prod`.
Runs `init` → `apply -auto-approve` → `output`. The deliberate design note in the file:
GitHub Environment protection rules are not free on private repos and HCP auto-apply is off,
so **a human dispatching the workflow is the approval gate**. Respect that reasoning; if you
want a stronger gate, propose it, do not silently rewire it.

**State/config**: HCP Terraform. `TF_WORKSPACE=ngm-<env>` selects the workspace; each
workspace supplies its own secrets and its own `-var-file` via `TF_CLI_ARGS_plan`/`_apply`,
which is why no `-var-file` appears in the workflows. Auth via `TF_TOKEN_app_terraform_io`
from `secrets.TF_API_TOKEN`. Terraform manages two local modules, `./modules/supabase` and
`./modules/cloudflare`. See `terraform/README.md`.

## Application pipeline (verified)

**`deploy.yml`** — push to `main` under `app/**` deploys to **dev automatically**;
`workflow_dispatch` with `environment: prod` is the production gate.
Steps: checkout → setup-node 20 (npm cache on `app/package-lock.json`) → `npm ci` →
`npm test` → `npm run build` → `cloudflare/wrangler-action@v3` `pages deploy dist`
to project `ngm-<env>`. `environment:` is set per run, so dev and prod use the **same secret
names with different values**.

**`database-migration.yml`** — push to `main` under `supabase/migrations/**` or
`supabase/functions/**` migrates dev automatically; dispatch for prod.
Steps: `supabase link` → `supabase db push` → `supabase functions deploy`.
Migrations are therefore **application-owned**, not Terraform-owned — the file's own comment
explains the Supabase Terraform provider cannot manage migrations or edge functions. Keep it
that way.

## Live state — verified 2026-09-06

| Fact | Value |
|---|---|
| GitHub repo | `nagzstar/ngm.app` — `origin` points here directly (renamed from `ngm.terraform`; remote corrected 2026-09-06) |
| DEV site | https://dev.nextgenmaher.com — HTTP 200 |
| PROD site | https://nextgenmaher.com — HTTP 200 |
| Pages projects | `ngm-dev`, `ngm-prod` (direct-upload; wrangler pushes `dist` from CI) |
| GitHub Environments | `dev` and `prod` exist, scoping secrets by name |
| `gh` CLI | v2.100.0, authenticated as `nagzstar` |
| Branch protection | **None, and unavailable** — private repo on a free plan (protection API returns 403) |

Cloudflare wiring lives in `terraform/modules/cloudflare`: a Pages project, a
`cloudflare_pages_domain` for the custom hostname, and a **proxied** CNAME to the
`pages.dev` subdomain (proxying is what allows a CNAME at the zone apex, via CNAME
flattening). All four workflows have real successful runs in history.

**Deployment authority: DEV is Claude's, PROD is the user's.** Because branch protection and
environment required-reviewers are unavailable on this plan, nothing technically prevents a
`workflow_dispatch` with `environment: prod`. The production gate is therefore **policy**, and
must be treated as absolute precisely because no system enforces it. GitHub Pro would technically
enable both controls, but it is a **paid plan and therefore ruled out** by the free-tier
requirement — policy is the gate.

## Cost constraint — free or as close to free as possible

**Hard requirement.** The whole stack is on free tiers and the only recurring cost is the
`nextgenmaher.com` domain. Never add a paid plan, add-on, runner or service without asking
the user first. Full detail in the `ngm-facts` skill; the delivery-specific consequences are:

- **GitHub Actions minutes are the scarcest resource in the stack.** They are the binding
  constraint on how ambitious CI can be. This is a further reason path-based triggers matter:
  never widen a filter so unrelated changes burn minutes. Prefer one well-targeted job over
  several broad ones, and prefer adding a step to an existing job over adding a new job.
- **No self-hosted or larger runners.** GitHub-hosted `ubuntu-latest` only.
- **No commercial scanning or deployment products.** The gaps below can all be closed with
  free tooling — `npm audit`, Dependabot, and OSS Actions such as tfsec/checkov/trivy.
- **HCP Terraform free tier is capped at 500 managed resources.** The current stack is far
  below it, but count the cost of anything that would create resources in bulk.
- **Supabase free plan allows 2 projects, and dev + prod already use both.** There is no room
  for a third environment even if one were wanted.
- Free Supabase projects **pause after inactivity**. A failed dev validation may mean the dev
  project is paused rather than the code being broken — check that before debugging.

## Known gaps and constraints — read before "improving" anything

1. **Build-once-promote is not currently possible.** Vite inlines `VITE_SUPABASE_*` at
   **build time**, so the artefact is inherently environment-specific and dev and prod are
   separate builds. This is a genuine architectural constraint, not an oversight. Moving to
   promote-one-artefact requires switching to **runtime** configuration (e.g. fetching config
   from a static endpoint on boot), which is an application change with its own risks. Raise
   it as a decision; do not half-implement it.

2. **There is no PR pipeline for application code.** `terraform-plan.yml` runs on PRs, but
   `deploy.yml` runs only on push to `main` and manual dispatch. App tests therefore run
   *after* merge, at deploy time. This is the largest real gap against the intended flow and
   the highest-value thing to fix — a PR-triggered `npm ci` + `npm test` + `npm run build` job.

3. **Do NOT add `npm run lint` as a blocking step** without first clearing the baseline.
   Lint currently fails on untouched `main` with 22 errors and 14 warnings (see
   `project.md`). Adding it as a gate would red-build every PR on day one. Either fix the
   baseline first as its own task, or add it non-blocking.

4. **Migration and app deploy ordering is unmanaged.** They are independent workflows with
   disjoint path filters. A single merge touching both `app/**` and `supabase/migrations/**`
   starts both **concurrently**, with no guarantee migrations land first. Backwards-compatible,
   additive migrations are what currently makes this safe. For any breaking schema change,
   sequencing must be handled deliberately — expand/contract, or an explicit ordered run.

5. **No dependency or IaC security scanning** anywhere — no `npm audit`, no tfsec/checkov/trivy.

6. **No post-deploy verification** — no health check or smoke test after a Pages deploy or a
   migration. Nothing confirms a release is good beyond the deploy step exiting 0.

7. **No documented rollback.** Cloudflare Pages retains previous deployments, so app rollback
   is redeploying a prior deployment. **Migrations are forward-only with no down migrations** —
   database rollback means writing a new corrective migration. Treat every migration as
   irreversible when assessing risk.

8. **`cancel-in-progress: true` on `deploy.yml`** can cancel an in-flight production deploy if
   another run starts. `database-migration.yml` and `terraform-apply.yml` correctly use `false`.

9. **Long-lived secrets, no OIDC.** `CLOUDFLARE_API_TOKEN`, `SUPABASE_ACCESS_TOKEN`,
   `SUPABASE_DB_PASSWORD`, `TF_API_TOKEN`. Cloudflare and Supabase do not offer the
   GitHub-OIDC federation that AWS/Azure/GCP do, so this is largely a constraint rather than a
   fixable defect. Rotation and least-privilege token scoping are the realistic controls.

10. **No branch protection, and none is wanted.** It is unavailable on the free plan, and the user has confirmed GitHub Pro is not needed. **Work directly on `main`** — pushes go straight to it, which is what triggers the dev deploy. PRs remain available but are not required and are not enforced. Never write a pipeline that assumes a PR gate exists.

## Identity separation (current, and correct in principle)

| Pipeline | Credential | Scope |
|---|---|---|
| Infrastructure | `TF_API_TOKEN` (HCP) | Terraform-managed resources |
| Application | `CLOUDFLARE_API_TOKEN` + `CLOUDFLARE_ACCOUNT_ID` | Pages deploy only |
| Database | `SUPABASE_ACCESS_TOKEN` + `SUPABASE_DB_PASSWORD` | migrations + edge functions |

The app pipeline holds no Terraform credentials and Terraform holds no Pages credentials.
Preserve that. The database credential is the broadest of the three — do not widen it further.
