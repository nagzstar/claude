---
name: infra-deployment
description: How NGM infrastructure changes are made and applied — Terraform under terraform/, the HCP workspaces ngm-dev and ngm-prod, per-environment tfvars and feature flags, Cloudflare DNS on a shared zone, Supabase project and auth settings, secret handling (names only), the terraform-plan/terraform-apply pipelines, and teardown. Load before editing anything under terraform/, before changing environment configuration or a workspace variable, and when diagnosing a Terraform Plan or Terraform Apply run.
---

# NGM infrastructure deployment

## Precedence

**The repo overrides this skill.** `.github/workflows/terraform-plan.yml`,
`.github/workflows/terraform-apply.yml`, `terraform/` (including `versions.tf`, `main.tf`,
`imports.tf`, `env/*.tfvars` and `terraform/README.md`) and `.agent-context/delivery.md` are
the source of truth. Where they disagree with anything here, they win — re-read them, then fix
this skill. Everything below is a snapshot, not an authority.

`.claude/skills/ngm-standing-rules/SKILL.md` governs; this skill only adds detail.

## Prerequisites

- Ownership of `terraform/` — that is `backend-engineer`. `.github/workflows/` belongs to
  `deployment-engineer`; if the *pipeline* must change, that is a different owner.
- Names only, never values. Infrastructure secrets live as **sensitive variables on the HCP
  workspace**, not as GitHub secrets, because each workspace supplies its own variables and
  its own `-var-file` through `TF_CLI_ARGS_plan`/`_apply` — which is why no `-var-file` appears
  in the workflows. Relevant names: `TF_API_TOKEN` (GitHub → HCP auth),
  `CLOUDFLARE_API_TOKEN`, `SUPABASE_ACCESS_TOKEN`, `database_password`, `smtp_pass`.
- You may run `terraform fmt`, `validate` and `plan`. **`terraform apply` and `destroy` are
  denied in `.claude/settings.json` and blocked by `.claude/hooks/guard-prod.sh`** — they run
  only through `terraform-apply.yml`.

## Procedure

1. **Adapt to the structure that exists.** There is a single `terraform/` root serving *both*
   HCP workspaces via workspace tags, with local modules `modules/supabase` and
   `modules/cloudflare`. Do not create a parallel directory, do not duplicate the root, and do
   not split the repository. If a proposal arrives assuming a greenfield layout, translate it
   into this one and say what you changed and why.

2. **Never add a workflow that applies automatically.** `terraform-apply.yml` is
   `workflow_dispatch`-only *by design*: branch protection is unavailable on this plan, so a
   human dispatching it is the approval gate. An auto-apply-on-push job would silently remove
   the only production gate that exists. The existing plan/apply workflows already path-filter
   `terraform/**`, so infrastructure work normally needs **zero** pipeline changes.

3. **The Cloudflare zone is shared between dev and prod.** The root config runs once per
   workspace, so any zone-level resource must be owned by exactly one workspace or the two
   fight over the same objects. Gate such resources behind a boolean variable that is true in
   `env/dev.tfvars` and false in `env/prod.tfvars`. Use the same pattern for any
   per-environment feature you do not want a dev change applying to prod as a side effect.

4. **Adopt existing resources, do not recreate them.** Anything created by hand before
   Terraform managed it needs an `import` block in `terraform/imports.tf`. If the resource is
   `count = 0` in one workspace, a static import block there names an address that does not
   exist and errors that plan — use `for_each` on the import block so it stays inert.
   `for_each` on `import` requires Terraform ≥ 1.7; **check the HCP workspace's Terraform
   version before bumping `required_version`**, because the remote runner's version is what
   matters, not the local CLI.

5. **`terraform fmt -check -recursive` is a gate.** `terraform-plan.yml` runs it and the job
   fails otherwise. Run `terraform fmt -recursive terraform/` before handing back.

6. **Never write a secret into the repo.** Add it as a sensitive variable on the workspace and
   reference it as a `variable` with `sensitive = true`. Give the variable a `default = ""`
   plus a `lifecycle` `precondition`, so a missing secret fails the *plan* with a clear message
   rather than applying something broken.

7. **Hand back to the Orchestrator**, who pushes to `main`. A change under `terraform/**`
   triggers `terraform-plan.yml`, which runs a matrix over `[dev, prod]`. **Read both legs of
   that plan before anything is applied.** Applying dev is the Orchestrator's; **applying prod
   is the user's decision** — the Orchestrator asks "Shall I deploy this to prod?" and
   dispatches only on an explicit yes; the `guard-prod` hook blocks any other prod dispatch.

## Verification

- **Read the plan, both legs.** The prod leg should say `No changes` for a dev-only change. If
  it does not, the environment gating is wrong — stop.
- Confirm the counts match intent: `Plan: N to import, N to add, N to change, 0 to destroy`.
  Any unexpected destroy is a stop-and-report.
- **Pre-flight anything that touches a shared or externally visible resource.** Before creating
  DNS records, query the names first — an existing record you did not expect means a conflict
  or a duplicate, and for records like `_dmarc` a duplicate is invalid and affects real mail.
- After apply, verify the effect *outside* Terraform: resolve the DNS names, curl the
  endpoint, read the setting back through the provider's API.
- **The next plan is your drift check.** If a resource shows a diff immediately after a clean
  apply, the configuration and the provider disagree — investigate rather than re-applying.

## Rollback / teardown

- Flag-gated resources are removed by flipping the flag to `false` and applying: the resources
  are destroyed and the gated block leaves state.
- **Removing a settings-style resource from management does NOT revert the live setting.**
  Terraform stops managing it; the last-applied values remain in effect. To actually revert a
  value, set it back and apply.
- `terraform destroy` is denied and hook-blocked. Teardown of anything real is a user decision.
- Treat DNS and auth configuration as production-affecting **even when applied from the dev
  workspace**, because the zone and the domain are shared.

## Lessons and known problems

They live in `NGM_ROOT/.agent-context/lessons.md` (the index) and `lessons/delivery.md` — read the
delivery file before you start; it is the lessons for your files. Nothing is recorded here: a skill
is a procedure, and lessons written into three skills went stale within a day (retro 2026-09-08).
