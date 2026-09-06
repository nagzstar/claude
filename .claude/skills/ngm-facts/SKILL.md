---
name: ngm-facts
description: Authoritative NextGenMaher (NGM) project facts — environments, dev/prod URLs, hosting, source control, CI/CD, database, and the deployment authority boundary between Claude and the user. Load when working on NGM deployment, environments, hosting, pipelines, releases, or when you need to confirm who is allowed to deploy what. The compact fact table lives in CLAUDE.md; this is the full policy detail behind it.
---

# NextGenMaher (NGM) — Core Project Facts

Source of truth for NGM environment and deployment facts. Do not rediscover these
unless there is evidence they have changed. If repository code conflicts with a fact
here, **flag the discrepancy** rather than silently revising this understanding.

Project: **NextGenMaher**, short name **NGM**.

| Item | Value |
|---|---|
| Environments | local, dev, prod |
| DEV URL | https://dev.nextgenmaher.com |
| PROD URL | https://nextgenmaher.com |
| Hosting | Cloudflare (Pages, direct-upload) |
| Source control | GitHub — repo `nagzstar/ngm.app` |
| Working branch | **`main`** (direct commit/push; no PR required) |
| CI/CD | GitHub Actions |
| Database | Supabase |
| DEV deployment authority | **Claude** |
| PROD deployment authority | **User** |
| Deployment approach | Pipelines |
| App / Terraform pipelines | Separate |
| Cost posture | **Free or as close to free as possible** |

## Cost — free or as close to free as possible

**This is a hard requirement, not a preference.** NGM runs on free tiers by design. Never
introduce a paid tool, paid plan, paid add-on or billable cloud resource without asking
the user first — and when you ask, say what it costs and what the free alternative gives up.

Verified posture (2026-09-06). The **only recurring cost in the entire stack is the
`nextgenmaher.com` domain registration**:

| Component | Plan | Relevant limit |
|---|---|---|
| GitHub | Free (confirmed via API) | Private repo; limited monthly Actions minutes |
| GitHub Actions | Free allowance | Minutes are the scarcest resource in the stack |
| HCP Terraform | Free tier | 500 managed resources |
| Supabase | Free plan | **2 projects** (dev + prod — already both), nano compute |
| Cloudflare | Free | Pages + DNS only; no Workers/R2/KV/D1/WAF/Argo in use |

The repository already encodes this. `terraform/modules/supabase/main.tf` deliberately
leaves `instance_size` unset with the comment that the free plan only offers nano compute
and naming a size would select a **paid compute add-on**. Do not set it.
`terraform/README.md` states the free-tier design goal directly. Treat both as binding.

### What this rules out

- **A third Supabase project is impossible on the free plan** — dev and prod already consume
  both. This is a second, independent reason never to add a test/staging/UAT environment.
- **Paid GitHub features are out**, including GitHub Pro for branch protection and
  environment required-reviewers. That is why the production gate is policy rather than a
  technical control: the free alternative to paying is discipline, and discipline is the
  choice that has been made. Do not propose a paid plan as the fix.
- **Paid Cloudflare products are out** — Workers paid tiers, R2, KV, D1, Argo, WAF — unless
  the user approves the cost.
- **Supabase paid add-ons are out** — larger compute, additional projects, point-in-time
  recovery, custom domains on the API.

### How to work within it

- Prefer what is already paid for or free: an existing table over a new service, a
  GitHub-hosted runner over a self-hosted one, an OSS Action over a commercial one.
- **Be frugal with Actions minutes.** They are the binding constraint on CI ambition. This is
  a further reason the path-based triggers matter: never widen a filter so unrelated changes
  burn minutes, and prefer one well-targeted job over several broad ones.
- Free tooling exists for most gaps — `npm audit`, Dependabot, and OSS scanners such as
  tfsec/checkov/trivy all run free on GitHub-hosted runners. Reach for these rather than
  commercial scanning products.
- Free tiers have **operational** consequences, not just financial ones: Supabase free
  projects pause after a period of inactivity, so a dev validation failure may simply mean the
  dev project is paused rather than the code being broken. Check before debugging. (Verify the
  current pause window against Supabase's docs rather than trusting a remembered number.)
- When comparing approaches, treat cost as a **first-class evaluation criterion** alongside
  correctness and security — a cheaper approach that meets the requirement wins.
- If the only viable solution costs money, do not quietly adopt it and do not silently drop
  the requirement. Present the trade-off and let the user decide.

## Environments

**local, dev and prod. These three only.** Never create or assume test, staging, UAT,
pre-production or preview environments unless the user explicitly asks. Local is a
developer machine, not a deployment target.

## DEV — Claude acts autonomously

Claude has broad autonomy in DEV and **does not need permission for normal DEV work**.
Claude may modify application, infrastructure and database code; create branches; commit;
push to GitHub; trigger, rerun and monitor DEV pipelines;
read pipeline logs; investigate and fix pipeline failures; redeploy DEV; change DEV
infrastructure and configuration where required; and run testing, QA and defensive
security testing.

**Do not stop at "the code is ready."** The normal DEV loop runs all the way through:

```
CODE → COMMIT → PUSH → PIPELINE → DEV DEPLOYMENT → VALIDATION
```

Iterate until DEV genuinely works. Do not ask for approval between intermediate DEV steps.

**Work directly on `main`.** Commit and push straight to it — that push is what triggers the
dev deploy. There is no branch protection, none is wanted, and a pull request would only delay
the dev deploy. Do not invent a branch/PR workflow. Use a branch and PR only when the user asks
for one, or when a change is risky enough that the plan should be reviewed before it lands.

## PROD — the user decides

**Claude must never independently deploy to production**, and must never bypass or weaken
production approval controls to make a deployment succeed.

Claude may: prepare and push production-ready code; inspect production pipelines and
deployment configuration; assess whether a release is ready; explain exactly what would be
deployed; identify production risks; monitor a production deployment **once the user starts
it**; investigate production pipeline failures; assist with rollback; and fix issues found
during a production release.

Claude must not: trigger the production deployment, dispatch a workflow with
`environment: prod`, bypass approval controls, remove production protections, or deploy to
nextgenmaher.com without the user's authorisation.

The boundary:

```
DEV VALIDATED → PRODUCTION READY → USER DEPLOYS/AUTHORISES → CLAUDE MAY MONITOR
```

When a change clears DEV, say plainly that it is **READY FOR PROD** and give the user the
release notes and risks they need to make the call.

## CI/CD principle

Everything deployed goes through pipelines: `CODE → GITHUB → PIPELINE → ENVIRONMENT`.
Avoid manual deployment where CI/CD can do the same job. If a needed deployment step is
currently manual, prefer building or improving a pipeline over repeating it by hand.

Application and infrastructure pipelines stay **separate**. An application-only change must
not run Terraform; an infrastructure-only change must not rebuild the application. See
`.agent-context/delivery.md` for the workflow-by-workflow detail.

## Supabase

Inspect the existing project before assuming anything about schemas, tables, auth, RLS,
migrations, functions, storage or APIs. Schema changes are **migrations**, version
controlled and pipeline-deployed — never reproduced by hand between environments. Test in
DEV before PROD.

Always consider RLS, authentication, authorization, user ownership, the participant /
mentor / admin permission split, service-role usage and secret handling. Frontend
restrictions are never sufficient security; enforce access control at the database or
backend. Never expose the service-role key to a frontend client.

## Safety — applies even with full DEV autonomy

Never commit secrets, expose passwords or API keys, or publish service-role credentials.
Never destroy data unnecessarily, bypass authentication, weaken Row Level Security without
justification, make unexplained destructive Terraform changes, or disable a security
control to make a deployment succeed. Investigate unexpected destructive changes before
proceeding rather than pushing through them.

## Verified infrastructure detail (2026-09-06)

Confirmed against the repository and the live GitHub/Cloudflare state:

- **Hosting is Cloudflare Pages in direct-upload mode.** `terraform/modules/cloudflare`
  creates the Pages project, attaches the custom domain (`cloudflare_pages_domain`) and
  creates a **proxied CNAME** to the project's `pages.dev` subdomain — proxying is what
  lets a CNAME sit at the zone apex via CNAME flattening. GitHub Actions builds and pushes
  the site with `wrangler`, which is why no `build_config` or git source is declared.
- Pages projects are `ngm-dev` and `ngm-prod`; the module's `site_url` output is
  `https://<domain>`. Both URLs return HTTP 200.
- **GitHub Environments `dev` and `prod` exist** and scope secrets, so both environments use
  the same secret names with different values.
- `gh` CLI is installed and authenticated as `nagzstar`, so DEV pipeline triggering,
  monitoring and log reading all work.

## Known discrepancies — do not silently "correct" these

1. **The GitHub repository is `nagzstar/ngm.app`** — renamed from `ngm.terraform`. The local
   `origin` was corrected to point at it directly on 2026-09-06, so the rename redirect is no
   longer relied on. The local directory is still `~/git/ngm.terraform`; that is just a folder
   name and is expected.
2. **`main` has no branch protection, and it cannot have any — this is accepted.** The repo is private on a
   free plan, so the protection API returns 403 ("Upgrade to GitHub Pro or make this
   repository public"). Environment *protection rules* — required reviewers on `prod` — are
   unavailable for the same reason. The user has confirmed GitHub Pro is not wanted, and that
   working directly on `main` is the intended workflow.
3. **Therefore the production gate is policy, not a technical control.** Nothing in GitHub
   prevents a `workflow_dispatch` with `environment: prod`. The `terraform-apply.yml` comment
   says as much: a human choosing to run the workflow *is* the authorisation. Treat the PROD
   boundary in this document as a hard rule precisely because no system will enforce it.
   GitHub Pro would technically enable branch protection and required reviewers, but that is a
   **paid plan and therefore ruled out** by the cost requirement above. Policy is the gate.
