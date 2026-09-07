---
name: app-deployment
description: How NGM application changes are built, gated and released — the check-app.sh quality gate and its baseline, the deploy.yml pipeline, DEV validation against dev.nextgenmaher.com, and rollback via Cloudflare Pages. Load before changing anything under app/, before reporting that an app change is done, and when diagnosing a Deploy pipeline run or a failing build/test/lint gate.
---

# NGM application deployment

## Precedence

**The repo overrides this skill.** `.github/workflows/deploy.yml`,
`.claude/scripts/check-app.sh`, `.agent-context/baseline.json`, `.agent-context/project.md`
and `app/package.json` are the source of truth. Where they disagree with anything here, they
win — re-read them, then fix this skill. Numbers especially rot: **never quote a lint or test
count from this file.** `check-app.sh` reads the live baseline; trust it, not prose.

`.claude/skills/ngm-standing-rules/SKILL.md` governs; this skill only adds detail.

## Prerequisites

- Ownership of `app/src/` — that is `frontend-engineer`. Do not edit `supabase/` or
  `terraform/`.
- Node 20 and `npm`. **`bun` is NOT installed**, despite `bun.lock` being committed. CI uses
  `npm ci`. Run commands from `NGM_ROOT/app`.
- Names only, never values: `CLOUDFLARE_API_TOKEN`, `CLOUDFLARE_ACCOUNT_ID`, and the
  build-time `VITE_SUPABASE_*` variables, all supplied per environment by the pipeline.

## Procedure

1. **Read `.agent-context/project.md` first.** It records the stack, conventions and the
   known constraints you must not "fix" — notably that domain data flows through
   `AuthContext`, not react-query, and that unused scaffolded shadcn components stay.

2. **Make the smallest reasonable change.** Compose existing `app/src/components/ui/`
   primitives; `react-hook-form` + `zod` for forms; `sonner` for toasts. No unrequested
   refactor, no reformatting of untouched lines, no new dependency without a stated reason.

3. **Run the gate before reporting.**
   `bash "$CLAUDE_PROJECT_DIR/.claude/scripts/check-app.sh"`
   It runs typecheck → build → test → lint from `app/` and compares the results against
   `.agent-context/baseline.json`. **Paste its summary line into your report.** Do not
   re-implement it, and do not run the four commands by hand to argue with its verdict.
   - `--skip-build` is available for a fast loop, but never for the final report.
   - `--update-baseline` is **Orchestrator-only, and only after the user has agreed** the new
     numbers are the accepted state of `main`.

4. **The typecheck bar is zero, always.** `typecheck=` runs `npm run typecheck` (`tsc -b`) and
   has **no baseline and never will** — unlike lint, the correct number of TypeScript errors is
   zero, permanently, and a tolerated count would recreate the very weakness this stage exists
   to fix (ngm.app#43: `build` was `vite build`, which strips types without checking them, so
   the gate reported `build=PASS` for "esbuild emitted a bundle"). `npm run build` is now
   `tsc -b && vite build`, so **CI fails on a type error too**, not just the local gate. Fix
   every error properly: `any`, `as unknown as`, `@ts-ignore` and a fresh `@ts-expect-error` all
   defeat the point. This is the check that catches
   `app/src/integrations/supabase/types.ts` drifting from the migrations, so a type error at a
   `.update({...})` or `.from(...)` call site is a signal about the database, not a nuisance.

5. **The lint bar is "no NEW problems", never "lint is clean."** Lint does not pass on
   untouched `main`. `@typescript-eslint/no-explicit-any` is an *error* rule, so introducing
   `any` fails the gate. Never mass-fix the pre-existing problems as a drive-by — that makes
   the diff unreviewable and is its own task.
   - Watch for `react-refresh/only-export-components`: exporting a non-component (a helper, a
     zod schema) from a `.tsx` file adds a new warning. Put such helpers in a plain `.ts`
     module instead — which also gives tests a seam that needs no Supabase mocking.

5. **Hand back to the Orchestrator.** You do not commit, push or deploy. `wrangler` deploys
   are denied in `.claude/settings.json` and blocked by `.claude/hooks/guard-prod.sh`.

6. **Delivery.** The Orchestrator pushes to `main`; a change under `app/**` triggers
   `deploy.yml` to **dev automatically**. The job runs `npm ci` → `npm test` → `npm run build`
   → a wrangler Pages deploy of `dist` to `ngm-<env>`. Because the tests run inside that job,
   **the dev deploy is the application's CI** — there is no pre-merge pipeline.
   **PROD is `workflow_dispatch` with `environment: prod` and is the user's decision**: the
   Orchestrator asks "Shall I deploy this to prod?" and dispatches only on an explicit yes.

## Verification

- `bash "$CLAUDE_PROJECT_DIR/.claude/scripts/check-dev.sh" --sha <sha>` — waits for the
  commit's runs and confirms dev returns 200. A short sha is fine (it is resolved first).
  **No runs found, or a run still running, is a FAIL** — only `--allow-no-runs` accepts an
  empty result, and an app change under `app/**` must never need it.
- **Confirm your code is actually in the deployed bundle**, not merely that a green run
  happened. Fetch the deployed JS and grep it for a string your change introduced:
  `curl -s https://dev.nextgenmaher.com/assets/index-<hash>.js | grep -c "<your string>"`.
  The bundle filename is in the served HTML, and a local `npm run build` emits the same
  filename for the same source — a cheap way to confirm what is live.
- **Grep the bundle for secrets** on any change that touches configuration: a `service_role`
  hit is a critical finding. Exactly one JWT should appear, and it should decode to
  `"role":"anon"`.
- Check the routes your change touched actually respond, and remember the SPA fallback makes
  every path return 200 — a 200 proves routing exists, not that the page renders.
- **Rendering, responsive layout and console errors cannot be verified from here.** There is
  no browser. Say so plainly rather than inferring a pass from Tailwind classes, and ask the
  user to check the few things that genuinely need eyes.

## Rollback

Cloudflare Pages retains previous deployments, so **application rollback is redeploying a
previous Pages deployment** — done by the user in the Cloudflare dashboard, or by dispatching
`deploy.yml` against an earlier commit. This is the one layer of the stack with a real,
non-destructive rollback path; the database has none. If a release pairs an app change with a
migration, rolling back the app does **not** roll back the schema.

## Lessons learnt

From `user-signup-approval` (2026-09-06). Confirmed unless marked inferred.

- **Building for both branches of an unverified assumption paid for itself.** The design
  assumed Supabase email confirmation would be off. It was on. Because the signup UI had been
  told to handle *both* a session and a no-session result, the discovery cost nothing instead
  of forcing a rework.
- **Map new backend fields fail-open.** Reading `approval_status ?? 'approved'` meant a
  frontend deployed ahead of its migration did not show every existing user a "pending" page.
  Security is unaffected because the database is the real gate. This is what makes the
  unordered app/migration pipelines survivable.
- Extracting pure helpers into a plain `.ts` module removed four new lint warnings *and* gave
  the tests a seam needing no Supabase mocking. Both benefits came from the same move.
- Unit tests here only meaningfully cover pure functions. A green suite proves nothing about
  RLS, edge-function authorization or the deployed bundle — say so rather than implying
  coverage the tests do not have.
- The order that actually worked: read `project.md` → change → `check-app.sh` → hand to the
  Orchestrator → push → `check-dev.sh` → grep the deployed bundle → probe live behaviour.

## Known problems

- **OPEN — `.agent-context/baseline.json` records a stale test count.** It says the accepted
  test count is 1, but `main` now carries 21 after this feature. `check-app.sh` only fails when
  tests drop *below* baseline, so 20 tests could be deleted without the gate noticing. Fix with
  `check-app.sh --update-baseline` once the user agrees the numbers. *Confirmed by reading
  `baseline.json` against a live test run.* Not changed here: the script's own rule is that
  the baseline moves only with the user's agreement. Note the installer force-copies
  `.agent-context/*.json`, so the fix must land in the agent-system repo to survive.
- **OPEN — no post-deploy smoke check inside the pipeline.** A deploy is considered good when
  the step exits 0. `check-dev.sh` covers this after the fact, but nothing in `deploy.yml`
  itself verifies the site. A `curl -f` after the Pages deploy is free and takes seconds.
  *Confirmed*; also tracked in `.agent-context/lessons.md`.
- **OPEN — `cancel-in-progress: true` on `deploy.yml`** can cancel an in-flight production
  deploy if another prod run starts. *Confirmed by reading the workflow.*
- **OPEN — lint fails on `main`** (see `baseline.json`), so lint can never become a blocking
  gate until a dedicated clean-up task clears it. *Confirmed.*
- **OPEN — no dependency scanning.** No `npm audit`, no Dependabot. Both free; scope triggers
  narrowly to protect Actions minutes. *Confirmed.*
- **OPEN (constraint) — build-once-promote is impossible.** Vite inlines `VITE_SUPABASE_*` at
  build time, so dev and prod are necessarily different artefacts. Fixing it needs runtime
  configuration, which is a deferred application change. Do not half-implement it. *Confirmed.*
- **RESOLVED — a frontend deployed before its migration.** Handled by the fail-open mapping
  above; no incident occurred. *Confirmed.*

## Open questions

- Desktop and mobile rendering for this feature were verified by code review and by the user
  on a phone, never by an automated browser. Whether the project wants a real browser-based
  check, and whether its Actions-minute cost is acceptable, is undecided.
- There is no component or integration test coverage at all — only pure-function unit tests.
  Whether that is an accepted trade-off or an unfunded gap has not been stated.

## Last synced

`C:\Users\nagaj\git\claude` @ `6a946f1862e21ae4ea80ff7faa02e6919172de5b` (2026-09-06).
