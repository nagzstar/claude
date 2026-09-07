# NGM — Project Knowledge

Last verified: 2026-09-07. Update only when architecture changes, not per task. Run
`bash .claude/scripts/context-drift.sh` to see whether the sources of this file changed since.

## Repository

`NGM_ROOT` = `C:/Users/nagaj/git/ngm.app` (local path), branch `main`.
GitHub repo: **`nagzstar/ngm.app`** (`origin` points there directly). **Work on `main`** —
commit and push straight to it; there is no PR requirement and no branch protection.
Deployed at https://dev.nextgenmaher.com (dev) and https://nextgenmaher.com (prod).
Single monorepo. All paths below are relative to NGM_ROOT.

| Path | Contents | Owner agent |
|---|---|---|
| `app/` | Vite + React 18 SPA, installable PWA | frontend-engineer |
| `supabase/migrations/` | 22 timestamp-prefixed SQL migrations, applied in filename order by CI; forward-only | backend-engineer |
| `supabase/functions/` | Deno edge functions: `admin-change-password`, `admin-create-user`, `admin-update-user`, `admin-delete-user`, `setup-admin`, `send-push` | backend-engineer |
| `terraform/` | main/variables/outputs/providers/versions/imports.tf, plus `modules/supabase` and `modules/cloudflare`; per-env `env/dev.tfvars`, `env/prod.tfvars` (committed, no secrets) | backend-engineer |
| `.github/workflows/` | deploy, database-migration, terraform-plan, terraform-apply | deployment-engineer |
| `app/src/test/` | vitest setup + 10 test files | qa-engineer |
| `.agent-context/tasks/`, `.agent-context/lessons.md` | task records and the cumulative lessons file — **owned and tracked by ngm.app**; the other context files are installed copies (gitignored there) | Orchestrator |
| `TEST-ACCOUNTS.md` | the standing dev/prod test accounts per role; credentials are in workstation environment variables, never in the repo | — |

Branch `feature/mobile-app` exists on origin but is fully merged and stale; nothing lives only there.

## Stack (discovered — do not replace)

- **Build**: Vite 5, `@vitejs/plugin-react-swc`, TypeScript 5.8 (strict off — see `tsconfig.app.json`).
- **PWA**: `vite-plugin-pwa` in `injectManifest` mode; the service worker is `app/src/sw.ts` (Workbox precache of hashed assets + SPA navigation fallback; `/.well-known/` excluded; **no runtime caching of `*.supabase.co`**). Manifest and icons are declared in `app/vite.config.ts` / `app/public/`. `PwaUpdatePrompt` handles updates; `useInstallPrompt` the install affordance.
- **UI**: React 18.3, **shadcn/ui** (49 components in `app/src/components/ui/`, config in `components.json`), Radix primitives, Tailwind 3.4, `lucide-react` icons, `framer-motion`, `sonner` for toasts.
- **Routing**: `react-router-dom` v6 `BrowserRouter`, flat `/role/page` URLs. Routes declared in `app/src/App.tsx`.
- **Server state**: `@tanstack/react-query` v5 is installed — but see "Known constraint" below.
- **Forms/validation**: `react-hook-form` + `zod` + `@hookform/resolvers`. The sign-up schema is `signUpSchema` in `app/src/lib/account.ts`.
- **Backend**: Supabase (Postgres + Auth + RLS + Deno edge functions + `pg_net` + Vault). Client in `app/src/integrations/supabase/client.ts` (the one file holding client options — `storage`, session persistence); generated DB types in `app/src/integrations/supabase/types.ts`.
- **Push**: Web Push (VAPID). DB triggers → `pg_net` → `send-push` edge function → browser. Subscriptions in `public.push_subscriptions`; frontend hook `usePushSubscription`, components `NotificationsPrompt` (first login) and `NotificationsToggle`. `pg_net` is confirmed available on the Supabase free plan.
- **Email**: Supabase Auth email via custom SMTP (Resend, sender `noreply@nextgenmaher.com`), managed in Terraform for both environments; email confirmation is on. Resend's free tier is 100 emails/day **shared across dev and prod**.
- **Infra**: Terraform on HCP (auto-apply off) manages the Supabase project + auth settings (`site_url`, `uri_allow_list`, SMTP), Cloudflare Pages + DNS, and the Resend DNS records (owned by the dev workspace only — the zone is shared). Environments are **local, dev, prod only**. CI/CD is four GitHub Actions workflows split by path filter into an infrastructure pipeline and an application pipeline — details in `.agent-context/delivery.md`, read only for delivery work.
- **Build-time env** (inlined by Vite, set per GitHub Environment in `deploy.yml`): `VITE_SUPABASE_URL`, `VITE_SUPABASE_PUBLISHABLE_KEY`, `VITE_SUPABASE_PROJECT_ID`, `VITE_VAPID_PUBLIC_KEY` (public), optional `VITE_SITE_URL`. Dev and prod are therefore separate builds.
- **Package manager**: `bun.lock` and `package-lock.json` are both committed and CI uses `npm ci`, but **bun is not installed locally — use `npm`**.
- **Tests**: **vitest** + `@testing-library/react` + jsdom. Config `app/vitest.config.ts`, setup `app/src/test/setup.ts`.
- **Lint**: eslint 9 flat config (`app/eslint.config.js`).

There is **no** React Native / Expo / Capacitor / Flutter and no native project on `main`. Mobile today = **responsive web + installable PWA + Web Push**. `app/src/hooks/use-mobile.tsx` is the breakpoint hook.

## Commands and verification

Run from `NGM_ROOT/app` with **`npm`** (`bun` is not installed): `npm run dev`, `npm run build`,
`npm run lint`, `npm run test`.

**Use the gate script rather than running these by hand and eyeballing counts:**

```
bash "$CLAUDE_PROJECT_DIR/.claude/scripts/check-app.sh"          # build → test → lint vs baseline
bash "$CLAUDE_PROJECT_DIR/.claude/scripts/check-dev.sh" --sha X  # pipeline runs for a commit + dev HTTP status
bash "$CLAUDE_PROJECT_DIR/.claude/scripts/context-drift.sh"      # have this file's sources changed?
```

The accepted state of `main` lives in `.agent-context/baseline.json` and is the **only** place
the numbers are recorded. Facts behind it:

- `npm run build` passes, with a pre-existing chunk-size warning (no code splitting). Do not
  "fix" it unasked.
- `npm run lint` **fails on untouched `main`** (mostly `@typescript-eslint/no-explicit-any`,
  `react-hooks/exhaustive-deps`, a `require()` in `tailwind.config.ts`). The gate is therefore
  **no new lint problems**, never "lint passes". Never mass-fix the baseline as a drive-by; a
  deliberate lint clean-up is its own task, after which the Orchestrator runs
  `check-app.sh --update-baseline` with the user's agreement.
- The baseline's test count (1) predates the 2026-09-06 work and is now far below the real
  suite, so the "no fewer tests" half of the gate is currently toothless. Raise it via
  `--update-baseline` when the user agrees. A green run still proves little; treat each new
  test as the first real coverage of its area.

There is no local Supabase instance, so migrations cannot be applied or tested locally —
they are reviewed by reading. CI applies them on push to `main` under `supabase/migrations/**`.
The migration and deploy workflows have **disjoint path filters and run concurrently**, so a
migration must be correct while the previous frontend build is still being served (additive
columns, compatible function signatures), and a frontend must tolerate a backend one step behind
(the `mapProfile` "fail open" defaults).

## Application domain

Three user roles: **participant**, **mentor**, **admin**.

Core flow: a participant (or mentor) posts a *message* (a question) → admin moderates it
(`pending`/`approved`/`rejected`) → mentors post *responses* → admin moderates responses →
approved content is visible on the board. **Every non-admin message and response is born
`pending` and only an admin can set any other status — enforced by RLS, not just the UI.**

**Accounts.** Two creation paths, both running the `handle_new_user` trigger:
- **Self-signup** at `/signup` (`SignUpPage`): first/last name, an *anonymous* toggle, email,
  optional phone, **Maher family name** (free text), industry + job title (from the
  `industries` / `job_titles` reference tables), requested role (`participant | mentor`),
  password. The account is `approved` immediately if the family name matches the private
  `approved_family_names` list; otherwise `pending`, and the user lands on `/pending`
  (`PendingApprovalPage`) until an admin approves via `admin-update-user`. Admins are notified
  by push. A pending user can turn notifications on from that page.
- **Admin-created** via `admin-create-user` (Admin › Users), approved by definition.
Admins also deactivate (`is_active`), change roles, reset passwords and **delete** users
(`admin-delete-user`; the user's content survives as "Deleted user").

**Names.** The community only ever sees `display_name`: the real name for named members, a
generated "Adjective Noun" handle for anonymous ones. Real names and family names are
admin-visible only. See `security-model.md`.

**Notifications.** Web Push on: new message / response / account awaiting moderation (admins);
an approved response on your message (author); another approved response on a message you
answered (mentor); your message / response / account was moderated (owner). Recipient matrix
and guards are in `supabase/functions/send-push/README.md`.

Tables (`public` schema): `profiles`, `user_roles`, `messages`, `responses`, `tags`,
`resources`, `announcements`, `industries`, `job_titles`, `approved_family_names`,
`push_subscriptions`.
Enums: `app_role` (`admin`,`moderator`,`user`), `message_status` / `response_status`
(`pending`,`approved`,`rejected`), `message_category` (`Education`,`Career`,`Advice`,`Other`).
`profiles.approval_status` and `profiles.role` are `TEXT CHECK` columns, not enums.

Shared TS domain types live in `app/src/types/index.ts` (`User`, `ApprovalStatus`, `Industry`,
`JobTitle`, `Message`, `Response`, `MentorProfile`, `Tag`, `Resource`). DB rows are
snake_case; app types are camelCase — the mappers (`mapProfile`, `mapIndustry`,
`mapJobTitle`) and the pure account helpers (`isPendingApproval`, `postAuthRedirectPath`,
`signUpSchema`) live in **`app/src/lib/account.ts`**, unit-tested without the provider.
New optional `User` fields default "fail open" in `mapProfile` so a frontend deployed ahead of
its migration keeps rendering.

Pages are grouped by role: `app/src/pages/admin/`, `app/src/pages/mentor/`,
`app/src/pages/participant/`, plus shared `LoginPage`, `SignUpPage`, `PendingApprovalPage`,
`MessageBoard`, `ResourcesPage`, `ResetPassword`, `Index`, `NotFound`. `ProtectedLayout`
redirects unauthenticated users to `/login`, pending users to `/pending`, and wrong-role users
to their own dashboard.

## Known constraints (respect these; do not "fix" them unasked)

0. **Cost: free or as close to free as possible.** A hard requirement. Every component runs on a free tier and the only recurring cost is the `nextgenmaher.com` domain. Never add a paid plan, add-on, service or billable resource without asking. Detail in the `ngm-facts` skill. Watch the shared limits: Resend 100 emails/day across dev+prod, two Supabase projects total, Actions minutes.
1. **`AuthContext.tsx` is a god-context** (~800 lines). It holds auth *and* all domain data (`users`, `messages`, `responses`, `tags`, `resources`, `mentorProfiles`, `industries`, `jobTitles`) plus ~25 mutation functions, fetched eagerly, with realtime toasts. Despite react-query being installed, **data flows through this context, not through react-query hooks.** Follow the existing pattern: add to the context, do not introduce a parallel react-query layer for one feature. Migrating it is a **tier-4** architectural task, separately approved.
2. **Two parallel role systems** and the **approval gate**. See `security-model.md`. This is the single most important thing to get right.
3. `app/src/data/mockData.ts` still seeds `mentorProfiles` (`mockMentorProfiles`) as the fallback. Check whether a surface is live or mocked before changing it.
4. The app was scaffolded by Lovable; some generated shadcn components are unused. Do not mass-delete them as "cleanup".
5. `.env` files are present locally and gitignored. Never read secrets into a transcript, never commit them, never echo them. Secret *names* are listed in `security-model.md` and `send-push/README.md`.
6. **Mobile-compatibility rules for every web change** (ratified with the mobile design, `tasks/mobile-app-design.md` § Q7): build redirect URLs with `siteOrigin()` (`app/src/lib/siteOrigin.ts`), never `window.location.origin`; no absolute `nextgenmaher.com` URLs in source; keep every Supabase client option in `client.ts` and no auth state in `localStorage` elsewhere; do not enable PKCE; the service worker never caches `*.supabase.co`; never add `app/public/404.html`; `/.well-known/` is reserved; keep `BrowserRouter` and the flat URL scheme; feature-check Chrome-only Web APIs; avoid `100vh` layouts.

## Roadmap — mobile (decided and partly delivered)

**Ratified by the user on 2026-09-06** (design `tasks/mobile-app-design.md`, decision record
`tasks/mobile-app.md`): the sequence **PWA → Web Push → Google Play (Trusted Web Activity) →
iOS via a Capacitor shell only if the user later opts in**. React Native/Expo was rejected.
Supabase stays the single backend; environments stay local/dev/prod; data stays behind
`AuthContext`.

- **Phase 1 (PWA) and Phase 2 (Web Push): DONE and released to prod** (2026-09-06).
- **Phase 3 (Google Play TWA): not started on `main`.** The Bubblewrap scaffold and
  `mobile-android.yml` built on the feature branch were deliberately removed before merge (they
  exist only in history, commit `342e9b9`). It is blocked on the user: the Play account type
  (personal, US$25, needs 12 real closed testers for 14 days; or organisation, needs a D-U-N-S
  number) and a privacy-policy URL. App identity when it happens: name "NextGen Maher", short
  name "NGM", application id `com.nextgenmaher.app` (`.dev` suffix for dev builds), backend
  chosen by the live site's build, not by the binary.
- **Phase 4 (App Store): not bought.** iOS users install the PWA from Safari and receive Web
  Push from iOS 16.4.

Ownership: frontend-engineer owns the client code (and any future `mobile/` shell),
deployment-engineer owns build/release pipelines, backend-engineer owns any API or auth change
(deep links, push tokens) with security review. Starting Phase 3 is its own task with its own
task file, never a side effect of another change.

## Conventions

- Path alias `@/` → `app/src/`.
- Components: PascalCase `.tsx`, one component per file, in `app/src/components/`; route-level components in `app/src/pages/<role>/`; pure helpers in `app/src/lib/`; hooks in `app/src/hooks/`.
- Prefer composing existing `components/ui/*` primitives over new base components.
- Toasts via `sonner` (`toast.success` / `toast.error`), not a bespoke notifier.
- Migrations: new file in `supabase/migrations/` named `<UTC timestamp>_<description>.sql`, later than every existing one. Never edit an applied migration; **forward-only**, with the corrective migration documented in a comment at the foot of the file. Replace a policy or function by dropping and recreating the **same name**; never add a second permissive policy alongside. Restate the `profiles` column-grant list in full when it changes. Idempotent statements (`IF NOT EXISTS`, `DROP ... IF EXISTS`, `ON CONFLICT DO NOTHING`).
- Edge functions: copy the admin-function auth scaffold for user-called functions and the `send-push` shared-secret scaffold for machine-called ones; register each in `supabase/config.toml` with `verify_jwt = false`.
- Every migration and edge-function change gets a `security-reviewer` pass; they are the authorization surface.
