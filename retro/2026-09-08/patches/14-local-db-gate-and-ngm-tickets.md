# 14 — Local migration gate (C) and the ngm.app tickets this retrospective needs (PM mode)

**Finding.** H11: this batch had 0 red pipeline runs, 1 rerun (`supabase/setup-cli@latest` rate
limit, still `@v1` in `database-migration.yml`) and no green-but-dead deployment; the RLS-level
defects were caught by review. Nothing on this PC can run Postgres (no Docker, WSL, `supabase`
CLI or `psql`). The remaining gaps (smoke check, CLI pin, Playwright, lessons split, probe
credentials) all live in ngm.app and must be created as tickets — the agent system never edits
ngm.app from here.

## Options for the local gate (your decision)

| option | what | cost | fidelity | verdict |
|---|---|---|---|---|
| A. Docker Desktop + `supabase start` | full local stack; `supabase db reset` applies every migration; RLS probes via `dev-probe.sh` pointed at localhost | free for personal use; ≈ 3 GB; WSL 2 install; ~2 min per run | full (auth schema, storage, edge runtime) | best fidelity; needs an install you have said nothing about |
| B. `embedded-postgres` (npm) | downloads a Postgres binary, no Docker; a shim SQL creates `auth.uid()`, `auth.jwt()`, the `authenticated`/`anon` roles and `storage.objects`; then applies migrations in order | free; ≈ 150 MB; ~40 s | partial: catches ordering, syntax, missing DROP POLICY names, definer grants; not storage/edge behaviour | cheapest way to catch the "cannot be applied locally" class |
| C. CI job in `database-migration.yml` | a `postgres:16` service container; apply migrations + the shim; run before the DEV push step | ≈ 1.5 min of Actions per migration-touching push (≈ 10 pushes/month → 15 min/month of the 2,000 free) | as B | no local install; costs minutes, states them |

Recommendation: B now (a `check-db.sh` run by `backend-engineer` before COMPLETE), C only if B
misses something in the next ten issues; A only if you want local storage/edge tests.

## Tickets to create through PM mode (exact text)

**T1 — Pin the Supabase CLI in database-migration.yml** (folds #61's item of #21) · type
`infrastructure` · P2 · Idea: `supabase/setup-cli@v1` with `version: latest` resolved a new release
on 2026-09-07 and hit a GitHub API rate limit (run attempt 2 on `f0af477`). AC: (1) `with: version:
<exact>` pinned to the version that applied the last migration; (2) a Dependabot or monthly reminder
to bump it (#23 says Dependabot monthly). Security & cost: none / free.

**T2 — Post-deploy smoke check in deploy.yml** (RETROSPECTIVE item 8, part of #21) · P2 · AC: (1)
after `wrangler pages deploy`, a step curls the environment's URL and fails the job unless it gets
200 and the response HTML names the bundle just built; (2) for `dev` only, one authenticated REST
call as the participant test account returns 200 (secrets by name from the `dev` environment); (3)
cost stated: ≈ 10 s per deploy.

**T3 — Split lessons.md into an index and domain files** (patch 07) · type `improvement` · P1 · AC:
(1) `lessons.md` ≤ 120 lines: header rules + one line per lesson with a pointer; (2)
`.agent-context/lessons/{database,application,delivery,process}.md` hold the detail, grouped by
domain not by task; (3) lessons already turned into gates (check-dev, typecheck, Write-tool,
resume check) are deleted with a pointer to the gate; (4) `check-app.sh`'s lessons gate passes at
`LESSONS_MAX_LINES=120`. Decisions: lessons.md stays ngm.app-owned (#28).

**T4 — `check-db.sh`: apply every migration to an embedded Postgres** (option B) · P2 · AC: (1)
`bash .claude/scripts/check-db.sh` applies `supabase/migrations/*` in filename order to a fresh
embedded Postgres with the auth/storage shim and exits 1 on the first error; (2) prints the
policies per table at the end for the security reviewer; (3) `backend-engineer` runs it before
COMPLETE (agent file line added here, in the agent system). Cost: free, ≈ 150 MB once.

**T5 — Playwright smoke against DEV, run by qa-engineer** · P2 · AC: (1) `npm run smoke:dev` signs
in as each `NGM_DEV_*` role and opens the dashboard, the moderation hub and one member page,
asserting no console error and the expected heading; (2) runs locally in ≤ 2 min; not in CI (no
minutes); (3) `qa-engineer.md` names it as part of DEV validation. Cost: free (dev dependency).

**T6 — `TEST-ACCOUNTS.md`: document the `NGM_DEV_*` variable names `dev-probe.sh` reads** · P3 ·
AC: names only (`NGM_DEV_ADMIN_EMAIL/PASSWORD`, `…MENTOR…`, `…PARTICIPANT…`), where they are set
(user shell profile), never a value in the repo.

**T7 — Re-verify `security-model.md` against the seven migrations since `f5d2540`** (#63 exists:
fold this in) · P1 · security · AC: storage policies, `auto_moderation_*`, events, resources and
success-stories policies described; `context-drift.sh` clean afterwards.
