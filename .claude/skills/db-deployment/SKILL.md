---
name: db-deployment
description: How NGM database changes reach an environment — writing a migration under supabase/migrations/, changing an edge function under supabase/functions/, RLS policy replacement, backfills, the database-migration.yml pipeline, verification and rollback. Load before creating or editing anything under supabase/, before changing an RLS policy or a security-definer function, and when diagnosing a Database Migration pipeline run.
---

# NGM database deployment

## Precedence

**The repo overrides this skill.** `.github/workflows/database-migration.yml`,
`.agent-context/delivery.md`, `.agent-context/security-model.md`, `supabase/config.toml` and
the existing files under `supabase/migrations/` are the source of truth. Where they disagree
with anything here, they win — re-read them, then fix this skill. Everything below is a
snapshot, not an authority. Never trust a command quoted here without checking the workflow
still runs it.

`.claude/skills/ngm-standing-rules/SKILL.md` governs; this skill only adds detail.

## Prerequisites

- Ownership of `supabase/` — that is `backend-engineer`. Do not edit `app/` or `terraform/`.
- Names only, never values: `SUPABASE_ACCESS_TOKEN`, `SUPABASE_DB_PASSWORD` (GitHub
  environment secrets, used only by the pipeline). `SUPABASE_SERVICE_ROLE_KEY` exists only
  inside edge functions and must never appear in `app/`, a bundle, a log or a report.
- **There is no local Supabase and no Supabase CLI on this machine.** Migrations cannot be
  applied or tested locally. They are reviewed by reading. Say so explicitly in your report.

## Procedure

1. **Read before writing.** Read every existing migration in `supabase/migrations/` in
   filename order. Later migrations supersede earlier ones, so the *current* policy set is
   only knowable from the whole sequence. `.agent-context/security-model.md` summarises it but
   may lag the migrations — the files win.

2. **New file, never an edit.** `supabase/migrations/<UTC timestamp>_<description>.sql`.
   **Never edit a migration that has already been applied**, including one applied only to
   dev. Correcting an applied migration means writing a new forward migration.

3. **Replacing an RLS policy: `DROP POLICY IF EXISTS` + `CREATE POLICY` using the EXACT
   existing name.** Verify every name against the migration that created it. A mismatched name
   makes the DROP a silent no-op and leaves the old permissive policy OR'd beside the new
   strict one — policies are permissive and OR together, so a single survivor defeats the
   whole gate. Never add a second policy alongside one you meant to replace.

4. **RLS cannot express column limits.** To stop a user writing a specific column, use
   `REVOKE UPDATE ... FROM authenticated` plus `GRANT UPDATE (col, col, ...)`. Audit every
   column the app actually writes *before* revoking, or you will silently 403 a working
   feature. Grants apply to admins too, because admins also connect as `authenticated` —
   confirm admin paths go through an edge function on `service_role`, which bypasses both RLS
   and column grants.

5. **A trigger on `auth.users` collides with any edge function that inserts the same row.**
   The trigger runs first, so a plain insert becomes a duplicate-key error. Convert those
   functions to upsert on `id` **in the same commit**, and check what the function does on
   failure — `admin-create-user` deletes the freshly created auth user, so the failure mode is
   worse than an error message.

6. **Additive and backwards-compatible, always.** `database-migration.yml` and `deploy.yml`
   are separate workflows with disjoint path filters, so a push touching both starts them
   **concurrently with no ordering guarantee** (`delivery.md` gap 4). The migration must not
   break the currently deployed frontend if it lands first. A column `DEFAULT` can serve as
   the backfill and the compatibility guard at once. For a genuinely breaking change, use
   expand/contract across two releases.

7. **Hand back to the Orchestrator.** You do not commit, push or deploy. The Supabase CLI
   push/reset and function-deploy commands are denied in `.claude/settings.json` and blocked
   by `.claude/hooks/guard-prod.sh`; they run only inside the pipeline. If the hook fires,
   stop and report rather than working around it.

8. **Delivery.** The Orchestrator pushes to `main`; a change under `supabase/migrations/**` or
   `supabase/functions/**` triggers `database-migration.yml` against **dev automatically**.
   That job links the project, pushes the migrations, then deploys the edge functions,
   sequentially in one job — so migrations and functions are ordered *relative to each other*.
   **PROD is dispatch-only and is the user's decision**: the Orchestrator asks "Shall I
   deploy this to prod?" and dispatches only on an explicit yes.

## Verification

- `bash "$CLAUDE_PROJECT_DIR/.claude/scripts/check-dev.sh" --sha <sha>` — waits for that
  commit's runs to finish and checks dev returns 200. Paste its summary line.
- Confirm the migration actually applied rather than assuming a green run means the right
  thing happened: `gh run view <id> --log | grep -i "Applying migration"`.
- **Prove the gate empirically, not by reading SQL.** Sign in as a real low-privilege account
  and call PostgREST directly, bypassing the frontend entirely. Expect empty results or
  `42501`. Test accounts and the environment variables holding their credentials are
  documented in `TEST-ACCOUNTS.md` at the repo root.
- **Prove a positive case too.** A gate that denies everything, including legitimate writes,
  is also broken. Check that a granted column still updates.
- **A free Supabase project pauses after inactivity.** A failed dev check may be a paused
  project rather than broken code. Check that before debugging.

## Rollback

**Migrations are forward-only. There are no down migrations. Treat every migration as
irreversible when assessing risk.** Recovery means a new corrective migration, reviewed and
shipped the same way. Prefer changes that are safe to leave in place if the next step is
abandoned — another reason additive beats destructive.

## Lessons learnt

From `user-signup-approval` (2026-09-06). All confirmed from the migrations and run logs
unless marked inferred.

- Verifying all ten `DROP POLICY` names against their source migrations was the single
  highest-value review step in the task. A typo would have left the gate wide open while
  looking entirely correct in review.
- `ADD COLUMN ... NOT NULL DEFAULT 'approved'` did three jobs at once: created the column,
  backfilled every existing row atomically so no current user was locked out, and covered the
  window where the migration had landed but the new edge functions had not.
- Auditing every direct write to `profiles` across `app/src` *before* the `REVOKE UPDATE` is
  what stopped the column grants breaking `updateMentorProfile`. Do that grep first, always.
- The trigger/edge-function collision was caught at design time. Left alone it would have
  broken admin user creation outright, with the function deleting the new auth user.
- A second, tiny migration to correct a role-seeding decision was cheaper and safer than
  reworking the first one. Small forward migrations are the idiom here.
- Verifying with a real low-privilege session found what reading SQL could not: it proved the
  gate is re-evaluated **per request** rather than baked into the JWT, because revoking
  approval changed the answer for the same unexpired token.
- The order that actually worked: read all migrations → write one migration → fix colliding
  edge functions in the same commit → push → confirm the pipeline applied it → probe live with
  a real token → only then call it done.

## Known problems

- **OPEN — `has_role(uid, role)` and `is_approved(uid)` are approval/role oracles.** Both take
  a caller-supplied uuid and are executable by any authenticated user, disclosing "is user X an
  admin / approved". The `GRANT EXECUTE` is genuinely required for the policies to work, so
  this is not simply removable; a zero-argument wrapper hardcoding `auth.uid()` would fix the
  client-facing case. *Confirmed by live probe.* Also tracked in `.agent-context/lessons.md`.
- **OPEN — `profiles.email` is user-writable with no UNIQUE constraint.** `authenticated`
  retains `UPDATE (email)` because the app writes it, so a user can set their displayed email
  to another user's address — and that address is what an admin sees when deciding to approve
  them. Pre-existing; this work re-granted rather than introduced it. *Confirmed.*
- **OPEN — `.agent-context/security-model.md` predates the approval gate.** Its policy matrix
  no longer matches the migrations. Re-derive from the files, never from that document.
  *Confirmed.*
- **OPEN (constraint) — no down migrations and no automated schema rollback.** *Confirmed.*
- **RESOLVED — deactivated accounts could have been locked out.** `is_approved()` requires
  `is_active`, and the count of `is_active = false` rows had never been checked before the
  gate shipped. It was run afterwards and returned **zero rows on dev**, so nobody was
  affected. The rule it became: run the impact query *before* shipping a gate that reads an
  existing column, not after. *Confirmed.*
- **RESOLVED — edge functions colliding with the new trigger.** Fixed by upsert in the same
  commit; proven live when an admin account was successfully created through the app UI.
  *Confirmed.*

## Open questions

- The `is_active = false` count has **not** been run against **prod**. It must be checked
  before or immediately after the prod migration.
- Whether Supabase realtime withholds payloads from an unapproved subscriber was never proven
  empirically. A subscription connected and received nothing, but no authorised write occurred
  during the window to force a payload. RLS strongly implies it is filtered; that is an
  inference, not evidence.
- `supabase/config.toml` sets `verify_jwt = false`, and every function re-checks the Bearer
  token in code instead. Whether that is a deliberate standing decision for all future
  functions, or inherited from scaffolding, is not recorded anywhere.

## Last synced

`C:\Users\nagaj\git\claude` @ `6a946f1862e21ae4ea80ff7faa02e6919172de5b` (2026-09-06).
