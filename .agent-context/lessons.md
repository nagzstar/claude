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

## Problems spotted (backlog — not yet fixed)

| Spotted | Problem | Owner | Tier |
|---|---|---|---|
| 2026-09-06 | `has_role(uid, role)` is callable by any authenticated user with an arbitrary uid, leaking "is user X an admin". Pre-existing, unrelated to signup. | backend-engineer + security-reviewer | 3 |
| 2026-09-06 | Email confirmation setting is not in Terraform or `config.toml`; the signup flow handles both states but which is live on dev/prod is unverified. Confirm in the Supabase dashboard and record it. | user / backend-engineer | 2 |
| 2026-09-06 | `SELECT count(*) FROM profiles WHERE NOT is_active` was never run before the approval gate landed; deactivated accounts are now genuinely locked out. Check the dev Admin Users page before any prod release. | user (before PROD) | 1 |
| 2026-09-06 | `security-model.md` policy matrix predates the approval gate; needs re-verification against `20260906013534_user_signup_approval.sql`. | researcher-architect | 3 |
| 2026-09-06 | Workflows pin actions to major tags (`@v4`, `@v3`) and `supabase/setup-cli` to `latest`: non-reproducible migrations, supply-chain exposure. SHA-pin, fix the CLI version. Free. | deployment-engineer | 2 |
| 2026-09-06 | No post-deploy smoke check; a deploy is "good" when the step exits 0. Add `curl -f` of the site after `pages deploy`. Free, seconds. | deployment-engineer | 2 |
| 2026-09-06 | No Dependabot or `npm audit`; dependency vulnerabilities go unnoticed. Dependabot config is free; scope it to monthly to protect minutes. | deployment-engineer | 2 |
| 2026-09-06 | Lint fails on `main` with 22 errors / 14 warnings (baseline). A deliberate clean-up task would let lint become a real gate. | frontend-engineer | 2 |
| 2026-09-06 | `AuthContext` fetches every domain table eagerly for every user; fine at current scale, a cost and latency problem later. Migration to react-query is tier 4 and explicitly deferred. | researcher-architect | 4 |
| 2026-09-06 | Build inlines `VITE_*`, so dev and prod are different artefacts; build-once-promote needs runtime config. Deferred. | researcher-architect | 4 |
| 2026-09-06 | Mobile version wanted; approach (PWA / Capacitor / React Native) undecided. See `project.md` roadmap. | researcher-architect | 4 |
