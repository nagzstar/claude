# NGM — Security & Authorization Model

Last verified: 2026-09-07 against all 22 files in `supabase/migrations/*` (read in filename
order, through `20260906230000_more_approved_family_names.sql`), all six functions in
`supabase/functions/*`, and `supabase/config.toml`.
Read this before ANY task touching auth, roles, permissions, user data, or admin functionality.

## The single most important fact: there are TWO role systems

| | `profiles.role` | `user_roles.role` |
|---|---|---|
| Type | `TEXT CHECK IN ('admin','mentor','participant')` | enum `app_role` = `('admin','moderator','user')` |
| Read by | The **UI** (`AuthContext`, `ProtectedLayout`, `RoleBadge`, sidebar), `get_user_counts`, and the **unauthenticated `setup-admin` function** (it decides "is first-run admin creation still open?" from `profiles.role = 'admin'`) | **RLS policies**, via `public.has_role(uid, role)`, and every admin edge function's server-side caller check |
| Drives | What the user sees | What the database actually permits |

`has_role()` is `SECURITY DEFINER, STABLE, SET search_path = public` — correctly written to avoid RLS recursion. Do not "simplify" it into a plain subquery. `EXECUTE` is granted to `authenticated` only (not `anon`, not `PUBLIC`).

**Consequence: RLS only ever distinguishes `admin` from "any authenticated user".**
No RLS policy anywhere checks for `moderator`, `user`, mentor or participant. Every policy uses `auth.uid()` ownership, `has_role(auth.uid(), 'admin')`, or `is_approved(auth.uid())` (below).

Therefore:
- Mentor-vs-participant separation is currently **UI-only** and is NOT an authorization boundary. Any feature that must be genuinely mentor-only (or participant-only) needs a **new database-level check**; say so explicitly at design time.
- **How the two systems are written.** Self-signup (`handle_new_user` trigger) writes the *requested* role (`mentor|participant`, clamped; `admin` unreachable) into `profiles.role` and **always** seeds `user_roles` with `'user'`, regardless of the request. Only `admin-update-user` (service_role) sets the real role: it rewrites `profiles.role` and deletes-then-inserts `user_roles` with the mapping `admin→admin`, `mentor→moderator`, `participant→user`. Any new feature that mutates roles must update **both** systems, or document why not.
- Because `setup-admin` reads `profiles.role`, emptying *either* set of admins is dangerous: no `user_roles` admin means no one passes RLS; no `profiles.role='admin'` re-opens `setup-admin` to the internet. `admin-delete-user` refuses a delete that would empty either set.

## The second gate: authenticated ≠ approved

`profiles.approval_status` is `pending | approved | rejected` (default `approved`, so pre-existing rows were backfilled approved). `public.is_approved(uuid)` (`SECURITY DEFINER, STABLE, search_path = public`; `EXECUTE` to `authenticated` only) returns true for an admin, or for a profile that is `approved` **and** `is_active`. Every content policy is gated on it, so:

- A pending, rejected or deactivated user can sign in, read **only their own `profiles` row** (needed for the awaiting-approval page) and manage their own `push_subscriptions`. They see no messages, responses, tags, resources, announcements or member directory.
- "Deactivate" (`is_active = false`) is therefore a real control, not cosmetic.
- Approval is written only by `admin-update-user` (service_role) or by the trigger at signup (family-name auto-approval, below). `authenticated` has no column grant on `approval_status`.

## Column-level protection on `profiles`

RLS cannot restrict columns, so `UPDATE` on `profiles` is `REVOKE`d from `authenticated` and re-granted column by column. **The authoritative list is restated in full in `20260906180000`**: `full_name, first_name, last_name, email, contact_phone, date_of_birth, parent_name, parent_email, parent_phone, expertise_tags, bio, linkedin, industry_id, job_title_id`.
**Deliberately absent (not writable by any authenticated user, including admins via PostgREST):** `role`, `is_active`, `approval_status`, `display_name`, `is_anonymous`, `maher_family_name`. Admins change those through the edge functions on service_role.
A column added after a column-level GRANT is not covered by it. When a task adds a `profiles` column that users must edit, the migration must **restate the whole REVOKE + GRANT list**; when it must not be user-editable, leave the list alone and say so.

## Effective policy matrix (all policies `TO authenticated` unless stated; all permissive)

| Table | SELECT | INSERT | UPDATE | DELETE |
|---|---|---|---|---|
| `profiles` | own row, or admin (**not** approval-gated) | admin (in practice only the `handle_new_user` trigger inserts) | own row or admin, `WITH CHECK` the same, **plus the column grant list above** | **none** — only `admin-delete-user` on service_role |
| `user_roles` | own rows, or admin | admin | — | — |
| `messages` | approved AND (`status='approved'` OR author OR admin) | `author_id=auth.uid()` AND `status='pending'` AND approved | USING approved AND (author OR admin); WITH CHECK approved AND (**admin**, OR author AND `status='pending'`) | admin |
| `responses` | approved AND (`status='approved'` OR responder OR admin) | `responder_id=auth.uid()` AND approved AND (`status='pending'` OR **admin**) | USING approved AND (responder OR admin); WITH CHECK approved AND (**admin**, OR responder AND `status='pending'`) | admin |
| `tags` | approved | admin | admin | admin |
| `resources` | approved | admin | admin | admin |
| `announcements` | `is_active` AND approved | admin (one `FOR ALL` policy) | admin | admin |
| `industries`, `job_titles` | **`anon` + authenticated**, `is_active` rows (sign-up form is unauthenticated; deliberate, harmless lists) | admin | admin | admin |
| `approved_family_names` | admin | admin | admin | admin — `anon` holds **nothing**; this list is the auto-approval secret |
| `push_subscriptions` | own rows | own rows | own rows | own rows — **not** approval-gated (pending users may subscribe); no admin policy; service_role bypasses |

`profiles` and `user_roles` additionally have `FOR ALL TO service_role USING(true)` policies — correctly scoped, used by edge functions. Intentional; do not flag it.

**Moderation is DB-enforced (`20260906220000`).** Through the API, only an admin may write a content `status` other than `pending`. Everyone else creates content as `pending` and can only rewrite their own row back to `pending` (edit-and-resubmit). The frontend's `addResponse` sets `approved` only for admins; the policy is what makes that true. **Reuse this `WITH CHECK ... AND status = 'pending'` shape** for any new user-submitted, moderated content, and never add a status-less UPDATE policy beside it.

**There is a second, DB-internal writer of content `status`: `auto_moderation_promote()`** (`20260907160000`, extended by `20260907230000`). It is `SECURITY DEFINER` on an `AFTER INSERT` trigger, so it bypasses RLS — there is no `FORCE ROW LEVEL SECURITY` anywhere in this repo — and it writes `approved` (a clean auto-moderated post) or `rejected` (a first matching rule in category `profanity` or `threat`). Both writes carry `AND status = 'pending'`, so a machine can never override a human's decision. It is unreachable from the API: its trigger fires on the stamp column, which `auto_moderation_stamp()` nulls on every INSERT and restores from `OLD` on every UPDATE, and neither content table has a column-level GRANT. The rule of thumb to carry forward is **"only an admin, or a SECURITY DEFINER trigger the API cannot reach"** — verified live on DEV 2026-09-07, where a non-admin `PATCH` of `status` still returns `42501` and a forged stamp is discarded.

**The reason a piece of content was held or rejected is admin-only and must stay off the content row.** It lives in `public.moderation_decisions` (`SELECT` to `authenticated`, narrowed to admins by policy, no other verb granted to anyone — the only writer is the SECURITY DEFINER trigger). It deliberately has **no foreign key** to `messages`/`responses`, because a FK would make it reachable by PostgREST resource embedding — the same rule this file states for `profiles`. Never move a category, rule id or matched word onto a content row: every approved member can read a content row once its status is `approved`, and `AuthContext` fetches these tables with `select('*')`.

**Table privileges are the outer wall.** New tables since 2026-09-06 use `REVOKE ALL ... FROM PUBLIC, anon, authenticated` **before** granting exactly the verbs needed, because Supabase's default privileges otherwise leave `TRUNCATE` and `REFERENCES` in place — and `TRUNCATE` is not filtered by RLS. Copy that shape (`20260906200000` / `20260906210000`) for every new table.

## Anonymity and names

The community sees **one** name: `profiles.display_name` (NOT NULL, derived, never caller-supplied). `first_name`/`last_name`/`full_name` are the real name and are admin-visible only. `trg_profiles_sync_names` (`sync_profile_names()`, SECURITY DEFINER, BEFORE INSERT OR UPDATE) reconciles the three real-name columns and sets `display_name`: a generated "Adjective Noun" handle when `is_anonymous`, the real name otherwise; a handle, once minted, is immutable while the user stays anonymous. `generate_anonymous_display_name()` has `EXECUTE` revoked from everyone — only the trigger calls it.

`get_public_profiles()` is the **only** way a non-admin reads another member. It returns `display_name` under **both** the `full_name` and `display_name` column names (so no real name can leak even to a regressed client), withholds `bio` and `linkedin` for anonymous members with a fail-closed `COALESCE(is_anonymous, true)`, never returns `maher_family_name`, and returns only approved rows to approved callers. If a feature needs another user's data, extend this function; never loosen the `profiles` SELECT policy.

## Sign-up path (`handle_new_user`, AFTER INSERT ON `auth.users`, SECURITY DEFINER)

Fires for every creation path (self-signup and `admin-create-user`) and must **never raise** — an exception aborts the `auth.users` insert and breaks all sign-up. It: clamps `requested_role` to `mentor|participant`; regex-guards `date_of_birth`; validates `industry_id`/`job_title_id` as UUIDs that name active rows with a consistent pairing (else NULL); treats `is_anonymous` as true only for JSON `true` or string `"true"`, wrapped in `COALESCE(..., false)` (three-valued-logic bug, `20260906190000`); sets `approval_status` to `approved` **only** when `normalize_family_name(maher_family_name)` matches an active row of `approved_family_names` (`COALESCE(v_status,'pending')` is load-bearing — `SELECT ... INTO` on zero rows yields NULL), otherwise `pending`; stores the family name as typed; and seeds `user_roles` with `'user'`. `approved_family_names` is read only inside this SECURITY DEFINER function; there is deliberately **no FK from `profiles` to it** (a FK would make it reachable through PostgREST embedding).

## Security-definer functions (bypass RLS by design — audit any change)

| Function | Purpose | Callable by |
|---|---|---|
| `has_role(uuid, app_role)` | RLS role check | `authenticated` |
| `is_approved(uuid)` | RLS approval gate (admin bypass; honours `is_active`) | `authenticated` |
| `admin_exists()` | boolean for the first-run setup flow | `anon`, `authenticated` |
| `get_public_profiles()` | the sanctioned member directory (see above) | `authenticated` |
| `get_user_counts()` | login-page stats; counts approved + active only | `anon`, `authenticated` |
| `handle_new_user()` | trigger on `auth.users` (see above) | trigger only |
| `sync_profile_names()` / `generate_anonymous_display_name()` | trigger on `profiles`; handle generation | trigger only / **nobody** |
| `enforce_push_subscription_limit()` | AFTER-statement trigger capping a user at 10 subscriptions | trigger only |
| `notify_push_event()` | AFTER triggers on `messages`/`responses`/`profiles`: reads Vault, `net.http_post` to `send-push`. **Fail-open** (everything inside `EXCEPTION WHEN OTHERS`, `SET LOCAL lock_timeout='1s'`) so push can never break a write. Admin-actor guard for UPDATE-fired content events lives **inside** the function, not in the trigger `WHEN` — do not move it | trigger only |

`normalize_family_name(text)` is `IMMUTABLE`, not security definer; `EXECUTE` to `authenticated` (a generated column needs it), not `anon`. `update_updated_at_column()` is a plain trigger function (no SECURITY DEFINER).

Triggers that exist (`grep "CREATE TRIGGER"` is the whole list): `on_auth_user_created` (auth.users), `trg_profiles_sync_names`, `trg_push_profile_pending`, `trg_push_profile_moderated` (profiles), `trg_*_updated_at` (tags/messages/responses/resources), `trg_push_message_pending`, `trg_push_message_moderated` (messages), `trg_push_response_pending`, `trg_push_response_approved`, `trg_push_response_insert_approved`, `trg_push_response_moderated` (responses), `trg_push_subscriptions_limit`.

## Edge functions (all Deno, `supabase/functions/`; all `verify_jwt = false` in `config.toml`, each authenticates itself)

`admin-change-password`, `admin-create-user`, `admin-update-user`, `admin-delete-user` follow the **user-Bearer pattern** — replicate it exactly in any new admin function:
1. Handle `OPTIONS` for CORS.
2. Require `Authorization: Bearer <token>`; 401 if absent.
3. Anon client bound to the caller's JWT, `auth.getClaims(token)`; 401 if invalid. Claims give **identity only**.
4. A **separate** service-role client re-checks `user_roles.role = 'admin'` for the caller; 403 otherwise.
5. Only then perform the privileged action, validating shapes (UUID regex, enums) before they reach Postgres.

Function-specific rules worth knowing:
- `admin-update-user` accepts `approvalStatus` (validated), `role` (rewrites both role systems), `isAnonymous` (literal boolean only) and never accepts `displayName`.
- `admin-delete-user` refuses self-deletion and refuses to delete the last admin in **either** role system; deletes the `auth.users` row (cascades to `profiles` and `user_roles`); `messages.author_id` / `responses.responder_id` have **no FK**, so content survives as "Deleted user".
- `setup-admin` is **unauthenticated by design** and does nothing once any `profiles.role = 'admin'` exists. That is why the last-admin guard above exists.
- `send-push` is **machine-to-machine**: called only by `notify_push_event()` via `pg_net`, authenticated by the `x-push-secret` header compared in constant time against `PUSH_WEBHOOK_SECRET` (fails closed if unset); event allowlist + UUID check; runs as service_role, so it **re-applies the approval gate in code** (`is_active AND approval_status='approved'`, with the single documented exception `profile.moderated` → the profile owner); SSRF host allowlist on endpoints (skip and count, never delete); batches of 10; prunes 404/410; payload bodies carry `messages.title` at most, never a name, email or response text. This is the pattern for any future non-browser caller; do not bolt a Bearer check onto it.

Secrets — **names only**, never values, never in `app/`, a bundle, a log or a transcript: `SUPABASE_SERVICE_ROLE_KEY` (platform-injected, edge functions only), `PUSH_WEBHOOK_SECRET`, `VAPID_PRIVATE_KEY`, `VAPID_SUBJECT`; Vault rows `push_function_url`, `push_webhook_secret`. `VAPID_PUBLIC_KEY` / `VITE_VAPID_PUBLIC_KEY` is public and lives in a GitHub Environment *variable*. Dev and prod use distinct keypairs and secrets.

CORS is `Access-Control-Allow-Origin: *` everywhere. Acceptable because every function authenticates by Bearer token or shared secret, not cookies. If a function is ever changed to trust cookies or an origin, tighten this first.

## Anonymous (`anon`) access — the complete list

- `REVOKE ALL ON public.profiles FROM anon` (`20260730121232`) stands. `profiles` has FKs to `industries`/`job_titles`, so PostgREST *could* embed it from those anon-readable tables — it is denied **only** by that revoke and by every `profiles` policy being `TO authenticated`. **Never re-grant `anon` anything on `profiles`.**
- `anon` may: read active `industries` and `job_titles`; call `get_user_counts()` and `admin_exists()`; call `setup-admin` (inert once an admin exists); POST to `send-push` (rejected 401 without the secret).
- `anon` has nothing on `approved_family_names`, `push_subscriptions`, `user_roles`, content tables, `has_role`, `is_approved`, `get_public_profiles`, `normalize_family_name`.

## Standing rules for every feature

1. Decide and write down, before implementing: who may **create / read / update / delete / approve / moderate**, and whether "authenticated" or "approved" is meant.
2. Authorization is enforced in **RLS or an edge function**. Route guards, `isPendingApproval`, and hidden buttons are UX, never security.
3. New user-generated content visible to others goes through `pending` → admin-approved, pinned by `WITH CHECK ... status = 'pending'` on INSERT **and** UPDATE (non-admin branch).
4. New tables: `ENABLE ROW LEVEL SECURITY`, `REVOKE ALL` from `PUBLIC/anon/authenticated`, then `GRANT` exactly the needed verbs, plus explicit policies — all in the same migration. RLS on with no policy denies all; RLS off is exposed via PostgREST; a table-level `TRUNCATE` grant is not filtered by RLS.
5. Policies are **permissive and OR'd together**. Replace a policy with `DROP POLICY IF EXISTS` + `CREATE POLICY` on the **exact existing name** (a typo leaves the old one alive). Check the full set on a table, not just the policy being added.
6. Later migrations supersede earlier ones. Read migrations in filename order before concluding a policy or function body exists; comments in an older migration may describe a hole that a newer one closed (e.g. `20260906210000` vs `20260906220000`).
7. Anything running inside `handle_new_user()` or another trigger on the sign-up path must be unable to raise: guard casts with regexes, `COALESCE` every boolean built from jsonb lookups and every `SELECT ... INTO`, and exercise the absent-key path live, not by reading.
8. Privacy controls fail closed (`COALESCE(is_anonymous, true)`); notification plumbing fails open (a push failure must never block a write).
9. No FK from `profiles` to a private table; extend `get_public_profiles` rather than exposing `profiles`.

## Known residual gaps (documented, not defects to re-report)

- Mentor-vs-participant is still not an RLS boundary (by design; nothing needs it yet).
- `approved_family_names`, `industries` and `job_titles` have no admin UI; changes are data-only migrations.
- Rate limiting of `send-push` invocations beyond the 10-subscription cap and SSRF allowlist is tracked separately.
- The push admin-actor guard relies on moderation happening under the admin's own JWT via PostgREST; if moderation ever moves into a service_role edge function, `auth.uid()` is NULL there and the approval notifications go quiet (fail-quiet, not broken). Re-check before such a change.
