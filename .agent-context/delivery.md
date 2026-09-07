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
want a stronger gate, propose it, do not silently rewire it. Claude may dispatch it for
**dev** freely, and for **prod** only after asking the user "Shall I deploy this to prod?"
and recording their explicit yes; the `guard-prod` hook blocks any other prod dispatch.

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
names with different values**. Because tests run inside this job, the dev deploy *is* the
application's CI.

**`database-migration.yml`** — push to `main` under `supabase/migrations/**` or
`supabase/functions/**` migrates dev automatically; dispatch for prod.
Steps: `supabase link` → `supabase db push` → `supabase functions deploy`.
Migrations are therefore **application-owned**, not Terraform-owned — the file's own comment
explains the Supabase Terraform provider cannot manage migrations or edge functions. Keep it
that way.

## Live state — verified 2026-09-06

| Fact | Value |
|---|---|
| GitHub repo | `nagzstar/ngm.app` — `origin`, repo name and local folder `~/git/ngm.app` all agree |
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

**Deployment authority: DEV is Claude's, PROD is the user's — asked for every time.** When
DEV is validated the Orchestrator reports READY FOR PROD and asks "Shall I deploy this to
prod?"; on an explicit yes it records the approval with `.claude/scripts/prod-approval.sh`,
dispatches the prod workflows the change needs in order (`terraform-apply.yml` →
`database-migration.yml` → `deploy.yml`), watches each, validates https://nextgenmaher.com
read-only, revokes the approval and records the release in the task file. Nothing in GitHub
prevents a `workflow_dispatch` with `environment: prod` on this plan. The production gate is
therefore **policy plus the local `guard-prod` hook** (which admits a prod dispatch only from
the main session under a fresh recorded approval), and must be treated as absolute precisely
because GitHub does not enforce it. GitHub Pro would enable branch protection and required
reviewers but is a **paid plan and therefore ruled out**.

**Tooling:** `bash .claude/scripts/check-dev.sh [--sha <sha>]` reports the runs for a commit
and the dev HTTP status; `gh run view <id> --log-failed` for diagnosis. `--sha` takes any git
revision (a short sha is resolved to the full one it needs). With `--sha`, finding **no runs
is a FAIL** — absence of evidence is not evidence of success — as is a run still in progress
when the wait expires. Add `--allow-no-runs` only for a commit that genuinely matches no path
filter (a docs- or task-file-only commit), and say so in the task file.

## Cost constraint — free or as close to free as possible

**Hard requirement.** The whole stack is on free tiers and the only recurring cost is the
`nextgenmaher.com` domain. Delivery-specific consequences:

- **GitHub Actions minutes are the scarcest resource in the stack** and the binding
  constraint on CI ambition. Never widen a path filter so unrelated changes burn minutes;
  prefer one well-targeted job over several, and a step in an existing job over a new job.
- **No self-hosted or larger runners.** GitHub-hosted `ubuntu-latest` only.
- **No commercial scanning or deployment products.** The gaps below close with free tooling —
  `npm audit`, Dependabot, and OSS Actions such as tfsec/checkov/trivy.
- **HCP Terraform free tier is capped at 500 managed resources.**
- **Supabase free plan allows 2 projects, and dev + prod already use both.** No third
  environment is possible even if one were wanted.
- Free Supabase projects **pause after inactivity**. A failed dev validation may mean the dev
  project is paused rather than the code being broken — check that before debugging.

## Known gaps and constraints — read before "improving" anything

1. **Build-once-promote is not currently possible.** Vite inlines `VITE_SUPABASE_*` at
   **build time**, so the artefact is environment-specific and dev and prod are separate
   builds. Moving to promote-one-artefact requires **runtime** configuration — an application
   change (tier 4) with its own risks. Raise it as a decision; do not half-implement it.

2. **There is no pre-merge pipeline for application code.** Work goes straight to `main`,
   so app tests run at deploy time. The local gate (`check-app.sh`, run by every engineer and
   by the Orchestrator before pushing) is the pre-push equivalent. A PR-triggered job is only
   worth its minutes if the user ever adopts a PR workflow.

3. **`npm run build` typechecks as of 2026-09-07** (`tsc -b && vite build`, ngm.app#43), so the
   Deploy workflow now fails on a TypeScript error instead of shipping a bundle esbuild produced
   by stripping the types unchecked. `check-app.sh` reports it as its own `typecheck=` stage.
   There is no baseline for it and there must never be one: zero is the only acceptable count.

4. **Do NOT add `npm run lint` as a blocking step** without first clearing the baseline.
   Lint fails on untouched `main` (see `.agent-context/baseline.json`). Adding it as a gate
   would red-build every run. Either fix the baseline first as its own task, or add it
   non-blocking.

5. **Migration and app deploy ordering is unmanaged.** They are independent workflows with
   disjoint path filters. A single push touching both `app/**` and `supabase/migrations/**`
   starts both **concurrently**, with no guarantee migrations land first. Backwards-compatible,
   additive migrations are what currently makes this safe. For any breaking schema change,
   sequencing must be handled deliberately — expand/contract, or an explicit ordered run.

6. **No dependency or IaC security scanning** — no `npm audit`, no tfsec/checkov/trivy, no
   Dependabot config. All free; each costs minutes only when it runs, so scope triggers narrowly.

7. **No post-deploy verification** — nothing confirms a release beyond the deploy step exiting
   0. A `curl -f` of the site after `pages deploy` is a free, seconds-long smoke check.

8. **No documented rollback.** Cloudflare Pages retains previous deployments, so app rollback
   is redeploying a prior deployment. **Migrations are forward-only with no down migrations** —
   database rollback means writing a corrective migration. Treat every migration as
   irreversible when assessing risk.

9. **`cancel-in-progress: true` on `deploy.yml`** can cancel an in-flight production deploy if
   another prod run starts. `database-migration.yml` and `terraform-apply.yml` correctly use `false`.

10. **Long-lived secrets, no OIDC.** `CLOUDFLARE_API_TOKEN`, `SUPABASE_ACCESS_TOKEN`,
   `SUPABASE_DB_PASSWORD`, `TF_API_TOKEN`. Cloudflare and Supabase do not offer GitHub-OIDC
   federation, so this is a constraint rather than a defect. Rotation and least-privilege
   token scoping are the realistic controls.

11. **No branch protection, and none is wanted.** Work directly on `main`. Never write a
    pipeline that assumes a PR gate exists.

12. **Actions are pinned to major tags, not commit SHAs** (`actions/checkout@v4`,
    `supabase/setup-cli@v1`, `cloudflare/wrangler-action@v3`, …), and `supabase/setup-cli`
    uses `version: latest`, so a migration run is not reproducible and a compromised tag
    would flow straight into deploys. SHA-pinning plus a fixed Supabase CLI version is free.

13. **Edge functions are deployed with `verify_jwt = false`** (`supabase/config.toml`) and
    verify the Bearer token in code instead. That is the established pattern and works, but
    every new function must replicate the in-code check — the platform will not do it.

## Identity separation (current, and correct in principle)

| Pipeline | Credential | Scope |
|---|---|---|
| Infrastructure | `TF_API_TOKEN` (HCP) | Terraform-managed resources |
| Application | `CLOUDFLARE_API_TOKEN` + `CLOUDFLARE_ACCOUNT_ID` | Pages deploy only |
| Database | `SUPABASE_ACCESS_TOKEN` + `SUPABASE_DB_PASSWORD` | migrations + edge functions |

The app pipeline holds no Terraform credentials and Terraform holds no Pages credentials.
Preserve that. The database credential is the broadest of the three — do not widen it further.
