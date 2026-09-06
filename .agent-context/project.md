# NGM — Project Knowledge

Last verified: 2026-09-06. Update only when architecture changes, not per task.

## Repository

`NGM_ROOT` = `C:/Users/nagaj/git/ngm.app` (local path), branch `main`.
GitHub repo: **`nagzstar/ngm.app`** (`origin` points there directly). **Work on `main`** —
commit and push straight to it; there is no PR requirement and no branch protection.
Deployed at https://dev.nextgenmaher.com (dev) and https://nextgenmaher.com (prod).
Single monorepo. All paths below are relative to NGM_ROOT.

| Path | Contents | Owner agent |
|---|---|---|
| `app/` | Vite + React 18 SPA | frontend-engineer |
| `supabase/migrations/` | 13 SQL migrations (timestamp-prefixed) | backend-engineer |
| `supabase/functions/` | 4 Deno edge functions | backend-engineer |
| `terraform/` | main/variables/outputs/providers/versions/imports.tf, plus `modules/supabase` and `modules/cloudflare` | backend-engineer |
| `.github/workflows/` | deploy, database-migration, terraform-plan, terraform-apply | deployment-engineer |
| `app/src/test/` | vitest setup + tests | qa-security |

## Stack (discovered — do not replace)

- **Build**: Vite 5, `@vitejs/plugin-react-swc`, TypeScript 5.8 (strict off — see `tsconfig.app.json`).
- **UI**: React 18.3, **shadcn/ui** (49 components in `app/src/components/ui/`, config in `components.json`), Radix primitives, Tailwind 3.4, `lucide-react` icons, `framer-motion`, `sonner` for toasts.
- **Routing**: `react-router-dom` v6. Routes declared in `app/src/App.tsx`.
- **Server state**: `@tanstack/react-query` v5 is installed — but see "Known constraint" below.
- **Forms/validation**: `react-hook-form` + `zod` + `@hookform/resolvers`.
- **Backend**: Supabase (Postgres + Auth + RLS + Deno edge functions). Client in `app/src/integrations/supabase/client.ts`; generated DB types in `app/src/integrations/supabase/types.ts`.
- **Infra**: Terraform on HCP (auto-apply off), deploying Supabase + Cloudflare Pages. Environments are **local, dev, prod only**. CI/CD is four GitHub Actions workflows split by path filter into an infrastructure pipeline and an application pipeline — details in `.agent-context/delivery.md`, which is read only for delivery work.
- **Package manager**: `bun.lock` and `package-lock.json` are both committed and CI uses `npm ci`, but **bun is not installed locally — use `npm`** (see Commands).
- **Tests**: **vitest** + `@testing-library/react` + jsdom. Config `app/vitest.config.ts`, setup `app/src/test/setup.ts`.
- **Lint**: eslint 9 flat config (`app/eslint.config.js`).

There is **no** React Native / Expo / Capacitor / Flutter and no native project. Mobile today = **responsive web only**. `app/src/hooks/use-mobile.tsx` is the breakpoint hook. Do not assume a native app exists.

## Commands — verified 2026-09-06

Run from `NGM_ROOT/app`. **Use `npm`. `bun` is NOT installed on this machine**, despite
`bun.lock` being committed. `package-lock.json` is committed too, and CI uses `npm ci`.

```
npm install
npm run dev        # vite dev server
npm run build      # production build — the real gate
npm run lint       # eslint
npm run test       # vitest run
```

**Verified baselines — do not mistake these for regressions you caused:**

- `npm run build` — **passes.** Emits a chunk-size warning (~1.35 MB JS / 381 kB gzip, no
  code splitting). Pre-existing; do not "fix" it unasked.
- `npm run lint` — **fails with 22 errors and 14 warnings** on untouched `main`. Mostly
  `@typescript-eslint/no-explicit-any`, plus `react-hooks/exhaustive-deps` warnings and a
  `require()` import in `tailwind.config.ts`. The gate is therefore **"no NEW lint problems"**,
  not "lint passes". Compare counts before and after; never mass-fix the pre-existing ones
  as a drive-by.
- `npm run test` — **passes: 1 test file, 1 trivial placeholder** (`src/test/example.test.ts`).
  There is effectively **no test coverage**. A green suite proves almost nothing; treat any
  new test as the first real coverage of that area.

There is no local Supabase instance, so migrations cannot be applied or tested locally —
they are reviewed by reading. CI applies them on push to `main` under `supabase/migrations/**`.

## Application domain

Three user roles: **participant**, **mentor**, **admin**.

Core flow: a participant posts a *message* (a question) → admin moderates it (`pending`/`approved`/`rejected`) → mentors post *responses* → admin moderates responses → approved content is visible on the board.

Tables (`public` schema): `profiles`, `user_roles`, `messages`, `responses`, `tags`, `resources`, `announcements`.
Enums: `app_role` (`admin`,`moderator`,`user`), `message_status` / `response_status` (`pending`,`approved`,`rejected`), `message_category` (`Education`,`Career`,`Advice`,`Other`).

Shared TS domain types live in `app/src/types/index.ts` (`User`, `Message`, `Response`, `MentorProfile`, `Tag`, `Resource`). DB rows are snake_case; app types are camelCase — mapping happens in `AuthContext.tsx` (`mapProfile` and siblings).

Pages are grouped by role: `app/src/pages/admin/`, `app/src/pages/mentor/`, `app/src/pages/participant/`, plus shared `LoginPage`, `MessageBoard`, `ResourcesPage`, `ResetPassword`, `Index`, `NotFound`.

## Known constraints (respect these; do not "fix" them unasked)

0. **Cost: free or as close to free as possible.** A hard requirement. Every component runs on a free tier and the only recurring cost is the `nextgenmaher.com` domain. Never add a paid plan, add-on, service or billable resource without asking. Detail in the `ngm-facts` skill.

1. **`AuthContext.tsx` is a god-context.** It holds auth *and* all domain data (`users`, `messages`, `responses`, `tags`, `resources`, `mentorProfiles`) plus ~20 mutation functions, fetched eagerly. Despite react-query being installed, **data flows through this context, not through react-query hooks.** Follow the existing pattern: add to the context, do not introduce a parallel react-query layer for one feature. Propose migration only as an explicit, separately-approved task.
2. **Two parallel role systems.** See `security-model.md`. This is the single most important thing to get right.
3. Some mock data still exists in `app/src/data/mockData.ts` (e.g. `mockMentorProfiles`). Check whether a surface is live or mocked before changing it.
4. The app was scaffolded by Lovable; some generated shadcn components are unused. Do not mass-delete them as "cleanup".
5. `.env` files are present locally and gitignored. Never read secrets into a transcript, never commit them, never echo them.

## Conventions

- Path alias `@/` → `app/src/`.
- Components: PascalCase `.tsx`, one component per file, in `app/src/components/`; route-level components in `app/src/pages/<role>/`.
- Prefer composing existing `components/ui/*` primitives over new base components.
- Toasts via `sonner` (`toast.success` / `toast.error`), not a bespoke notifier.
- Migrations: new file in `supabase/migrations/` named `<UTC timestamp>_<description>.sql`. Never edit an applied migration.
