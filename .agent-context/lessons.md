# NGM — Lessons learnt and problems spotted

Cumulative across tasks. The Orchestrator reads this at boot and appends at COMPLETE.
Keep entries to one or two lines with the date and task. When a lesson is folded into
`project.md`, `security-model.md` or `delivery.md`, remove it from here. Problems below are
the backlog of outcomes the user can pick from — each with an owner and a tier.

## Lessons learnt

- 2026-09-06 · user-signup-approval · Replacing an RLS policy means `DROP POLICY IF EXISTS` +
  `CREATE POLICY` with the **exact existing name**; a typo silently leaves the old permissive
  policy OR'd next to the new one. Check every name against the migration that created it.
- 2026-09-06 · user-signup-approval · A trigger on `auth.users` collides with any edge function
  that inserts the profile row itself; those functions must upsert on `id` in the same commit.
- 2026-09-06 · user-signup-approval · Sessions get interrupted mid-task. Work on disk survives;
  assess it from the task log before starting anything new (now the boot resume check).
- 2026-09-06 · user-signup-approval · Migration and app deploy run concurrently, so every
  migration must tolerate the currently deployed frontend (`DEFAULT 'approved'` was the
  backfill and the compatibility guard at once).
- 2026-09-06 · agent-system-review · Numbers in prompts rot within a day (lint counts, test
  counts, migration counts). Put facts in a file a script reads, not in prose.
- 2026-09-06 · agent-system-review · Whoever commits owns integration. Engineers committing
  independently produced racing pushes and an empty diff for QA.
- 2026-09-06 · agent-system-review · A dev validation failure may be a paused free-tier
  Supabase project, not broken code. Check the project state before debugging.
- 2026-09-06 · user-signup-approval · **A green pipeline is not a working feature.** Signup was
  deployed, both pipelines green, and completely dead — three times over, each time a Supabase
  auth setting that lived only in the dashboard. Move provider settings into Terraform in the
  same task that depends on them.
- 2026-09-06 · user-signup-approval · When an assumption cannot be verified, build for **both**
  branches. The design assumed email confirmation was off; it was on, and the signup UI already
  handled both outcomes, so the discovery cost nothing instead of a rework.
- 2026-09-06 · user-signup-approval · Map new backend fields **fail-open** in the frontend
  (`approval_status ?? 'approved'`) so an app deployed ahead of its migration degrades safely.
  Security is unaffected because the database is the real gate.
- 2026-09-06 · user-signup-approval · RLS cannot express column limits. Use `REVOKE UPDATE` +
  `GRANT UPDATE (cols)`, and audit every direct write to the table first — grants bind admins
  too, since admins also connect as `authenticated`.
- 2026-09-06 · user-signup-approval · Prove an authorization gate with a live low-privilege
  session, never by reading SQL, and prove a **positive** case too — a gate that also blocks
  legitimate writes is broken. The live probe is what showed the gate is re-evaluated per
  request rather than baked into the JWT.
- 2026-09-06 · user-signup-approval · When automated QA is blocked, **ask the user to test**
  rather than downgrading a criterion to "unverified". A copy-pasteable browser-console script
  run in the user's own session reaches what an agent holding no credentials cannot.
- 2026-09-06 · user-signup-approval · Gate per-environment infrastructure behind flags in
  `env/*.tfvars` so prod can be prepared, pushed and planned at zero risk and reviewed before
  anyone applies. Read **both** legs of the plan; prod should say `No changes`.
- 2026-09-06 · user-signup-approval · Let the next natural plan/run answer an open question
  instead of spending a dedicated run on it. Actions minutes are the scarcest resource.

## Problems spotted (backlog — not yet fixed)

New problems are no longer appended here: at COMPLETE each one is filed as its own GitHub
issue labelled `claude` (`bash .claude/scripts/pm-issue.sh new`). The rows below predate
that; the Project Manager (`ngm-project-manager` skill) offers to migrate them.

| Spotted | Problem | Owner | Tier |
|---|---|---|---|
| 2026-09-06 | `has_role(uid, role)` is callable by any authenticated user with an arbitrary uid, leaking "is user X an admin". Pre-existing, unrelated to signup. | backend-engineer + security-reviewer | 3 |
| 2026-09-06 | **RESOLVED 2026-09-06.** Email confirmation is now unambiguous and in Terraform: confirmation is **ON** for both dev and prod (`mailer_autoconfirm: false`, verified live against both projects), and SMTP, `site_url` and `uri_allow_list` are managed in `terraform/modules/supabase`. `mailer_autoconfirm` is deliberately left out of the managed blob so the dashboard value stands. | — | done |
| 2026-09-06 | **RESOLVED for DEV 2026-09-06.** `SELECT count(*) FROM profiles WHERE NOT is_active` returned **zero rows** on dev, so the approval gate locked nobody out. **Still outstanding for PROD** — must be run before or immediately after the prod migration. | user (before PROD) | 1 |
| 2026-09-06 | `guard-prod.sh` greps the whole Bash command string, so writing a file whose *content* quotes a pipeline-only command (a heredoc documenting `supabase db push`) is blocked as if it were that command. Fails closed, so not a security hole, but it confuses agents and the workaround (use the Write tool) is undocumented. Fix belongs in the agent-system repo. | user / agent-system | 2 |
| 2026-09-06 | `.agent-context/baseline.json` still records `tests.count: 1`; `main` now has 21. `check-app.sh` only fails when tests drop below baseline, so 20 tests could be deleted unnoticed. Needs `check-app.sh --update-baseline` once the user agrees the numbers. | Orchestrator + user | 2 |
| 2026-09-06 | `profiles.email` is user-writable (`GRANT UPDATE (email)`, required by `updateMentorProfile`) with no UNIQUE constraint, so a user can display another user's address — which is what an admin sees when approving them. Pre-existing; the approval work re-granted it. | backend-engineer | 3 |
| 2026-09-06 | Resend free tier is 100 emails per **day** across the whole account, shared by dev and prod, but the Supabase setting it feeds is per **hour**. Dev is set to 100/hour and could spend a day's quota in an hour, silently breaking password resets. Prod is set to 20/hour. | deployment-engineer / user | 2 |
| 2026-09-06 | `security-model.md` policy matrix predates the approval gate; needs re-verification against `20260906013534_user_signup_approval.sql`. | researcher-architect | 3 |
| 2026-09-06 | Workflows pin actions to major tags (`@v4`, `@v3`) and `supabase/setup-cli` to `latest`: non-reproducible migrations, supply-chain exposure. SHA-pin, fix the CLI version. Free. | deployment-engineer | 2 |
| 2026-09-06 | No post-deploy smoke check; a deploy is "good" when the step exits 0. Add `curl -f` of the site after `pages deploy`. Free, seconds. | deployment-engineer | 2 |
| 2026-09-06 | No Dependabot or `npm audit`; dependency vulnerabilities go unnoticed. Dependabot config is free; scope it to monthly to protect minutes. | deployment-engineer | 2 |
| 2026-09-06 | Lint fails on `main` with 22 errors / 14 warnings (baseline). A deliberate clean-up task would let lint become a real gate. | frontend-engineer | 2 |
| 2026-09-06 | `AuthContext` fetches every domain table eagerly for every user; fine at current scale, a cost and latency problem later. Migration to react-query is tier 4 and explicitly deferred. | researcher-architect | 4 |
| 2026-09-06 | Build inlines `VITE_*`, so dev and prod are different artefacts; build-once-promote needs runtime config. Deferred. | researcher-architect | 4 |
| 2026-09-06 | Mobile version wanted; approach (PWA / Capacitor / React Native) undecided. See `project.md` roadmap. | researcher-architect | 4 |
