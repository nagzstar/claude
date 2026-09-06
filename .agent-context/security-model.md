# NGM — Security & Authorization Model

Last verified: 2026-09-06 against `supabase/migrations/*` (read in filename order) and `supabase/functions/*`.
Read this before ANY task touching auth, roles, permissions, user data, or admin functionality.

## The single most important fact: there are TWO role systems

| | `profiles.role` | `user_roles.role` |
|---|---|---|
| Type | `TEXT CHECK IN ('admin','mentor','participant')` | enum `app_role` = `('admin','moderator','user')` |
| Read by | The **UI** (`AuthContext`, `ProtectedRoute`, `RoleBadge`, sidebar) | **RLS policies**, via `public.has_role(uid, role)` |
| Drives | What the user sees | What the database actually permits |

`has_role()` is `SECURITY DEFINER, STABLE, SET search_path = public` — correctly written to avoid RLS recursion. Do not "simplify" it into a plain subquery.

**Consequence: RLS only ever distinguishes `admin` from "any authenticated user".**
No RLS policy anywhere checks for mentor or participant. Grep confirms every policy uses either `auth.uid()` ownership or `has_role(auth.uid(), 'admin')`.

Therefore:
- Mentor-vs-participant separation is currently **UI-only** and is NOT an authorization boundary.
- Any new feature that must be genuinely mentor-only (or participant-only) needs a **new database-level check** — it will not be enforced by the existing policies. Say so explicitly at design time.
- Keeping the two systems in sync when a role changes is a real hazard: changing `profiles.role` to `admin` does not grant admin, and inserting into `user_roles` does not change the UI. Any feature that mutates roles must update **both**, or deliberately document why not.

## Effective policy matrix

| Table | SELECT | INSERT | UPDATE | DELETE |
|---|---|---|---|---|
| `profiles` | own row, or admin | admin | own row, or admin | — |
| `user_roles` | own rows, or admin | admin | — | — |
| `messages` | `status='approved'` OR author OR admin | authenticated, `author_id=auth.uid()` AND `status='pending'` | author or admin | admin |
| `responses` | `status='approved'` OR responder OR admin | authenticated, `responder_id=auth.uid()` | responder or admin | admin |
| `tags` | any authenticated | admin | admin | admin |
| `resources` | any authenticated | admin | admin | admin |
| `announcements` | authenticated AND `is_active=true` | admin | admin | admin |

`profiles` and `user_roles` additionally have `FOR ALL TO service_role USING(true)` policies — correctly scoped to `service_role`, used by edge functions. That is intentional; do not flag it.

Note the good pattern in `messages` INSERT: `WITH CHECK (author_id = auth.uid() AND status = 'pending')` forces new content through moderation at the DB level. **Reuse this pattern** for any new user-submitted, moderated content.

## Security-definer functions (bypass RLS by design — audit any change)

`public.has_role`, `public.admin_exists`, `public.get_public_profiles`, `public.get_user_counts`, `public.update_updated_at_column`.
`get_public_profiles` is the sanctioned way to expose limited profile data to non-admins. If a feature needs another user's name/avatar, extend that function rather than loosening the `profiles` SELECT policy.

## Edge functions

`admin-change-password`, `admin-create-user`, `admin-update-user`, `setup-admin` (all Deno, in `supabase/functions/`).

Established auth pattern each admin function follows — **replicate it exactly in any new privileged function**:
1. Handle `OPTIONS` for CORS.
2. Require `Authorization: Bearer <token>`; 401 if absent.
3. Create an anon client bound to the caller's JWT and `auth.getClaims(token)`; 401 if invalid.
4. Create a **separate** service-role client and re-check the caller's admin role server-side.
5. Only then perform the privileged action.

`SUPABASE_SERVICE_ROLE_KEY` is used only inside edge functions. It must never appear in `app/`, in a client bundle, in logs, or in a transcript.

Current CORS is `Access-Control-Allow-Origin: *`. Acceptable because every function authenticates by Bearer token rather than cookies (so CSRF is not the exposure it would be with cookie auth). If a function is ever changed to trust cookies or an origin, this must be tightened first.

## Anonymous access

`anon` had a `profiles` SELECT policy for the first-run admin-setup flow. Migration `20260730121232_...` **dropped it and ran `REVOKE ALL ON public.profiles FROM anon`**. `public.admin_exists()` (security definer, returns boolean only) replaced it. This is already fixed — do not re-report it, and do not reintroduce anon table access.

## Standing rules for every feature

1. Decide and write down, before implementing: who may **create / read / update / delete / approve / moderate**.
2. Authorization is enforced in **RLS or an edge function**. Route guards and hidden buttons are UX, never security.
3. New user-generated content that is visible to others goes through the `pending` → admin-approved flow unless explicitly agreed otherwise.
4. New tables: `ENABLE ROW LEVEL SECURITY` in the same migration that creates them, plus explicit policies. An RLS-enabled table with no policy denies all — a table with RLS *off* is exposed via PostgREST.
5. Policies are **permissive and OR'd together**. One loose policy defeats every strict one on that table. Always check the full set for a table, not just the policy being added.
6. Later migrations supersede earlier ones. Always read migrations in filename order before concluding a policy exists.

## Addendum — 2026-09-06 signup/approval change (NOT yet re-verified above)

Commit `4a149c7` ("Add self-signup with admin account approval", migration
`20260906013534_user_signup_approval.sql`) landed after this document was verified. Per the
ratified design in the task record it: adds `profiles.approval_status`
(`pending|approved|rejected`, default `approved`); adds `public.is_approved(uuid)`
(security definer, admin bypass, also honours `is_active`) and gates the SELECT/INSERT/UPDATE
policies on `messages`, `responses`, `tags`, `resources`, `announcements` with it by
**replacing the policies by name**; adds a `handle_new_user` trigger on `auth.users` that
clamps the requested role to `mentor|participant`; restricts `authenticated` UPDATE on
`profiles` to a column grant list and adds `WITH CHECK` to the profiles UPDATE policy; gates
`get_public_profiles` and `get_user_counts`. The policy matrix above therefore **understates**
current enforcement. Re-verify against the migration and fold it into the matrix at the next
architecture update; until then, `is_approved()` is a fourth security-definer function to
audit on any change.
