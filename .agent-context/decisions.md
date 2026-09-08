# Standing decisions — the Orchestrator assumes these without asking

One dated line each, in the user's terms. Add a line when the user decides something that will
come up again; delete a line only when the user reverses it. Product decisions specific to one
ticket stay on that ticket under `## Decisions`.

- 2026-09-06 · Environments are local, dev and prod only; no staging/UAT (the Supabase free plan allows two projects).
- 2026-09-06 · DEV is Claude's: code, commit, push, pipelines, redeploy, QA and security testing proceed without asking. PROD is released only on the user's explicit yes to "Shall I deploy this to prod?", asked every time in those words.
- 2026-09-06 · Free tier only. No paid plan, add-on, runner, service or dependency without asking with the cost. GitHub Pro is ruled out. Actions minutes are the scarcest resource.
- 2026-09-06 · `main` only: direct commits and pushes, no PRs, no branch protection. Infrastructure and application pipelines stay separate and are never merged.
- 2026-09-06 · Agents use the DEV admin, mentor and participant test accounts themselves (`NGM_DEV_*` variables; names in `TEST-ACCOUNTS.md`) and delete their own fixtures. Only browser rendering, a real inbox and dashboard settings need the user.
- 2026-09-06 · Every completed job records lessons learnt and problems spotted; problems become `claude` issues, never lines in lessons.md.
- 2026-09-07 · The backlog is GitHub Issues on `nagzstar/ngm.app`. Each item is delivered in a fresh headless session (`pm-run-issue.sh`), never inside the PM conversation, never two at once.
- 2026-09-07 · The batch is the unit of delivery: tickets on the same surface go into one `batch` umbrella with one task file, one commit per member, one push, one validation and one release. Tickets that change the same main function are consolidated, never delivered twice.
- 2026-09-07 · The delivery order is the pinned "Delivery order" issue: one numbered sequence with titles, agreed with the user; `P1`–`P3` are only a summary of it.
- 2026-09-07 · A `blocked` ticket is never started, resumed or deployed, whatever its place in the order; only the user lifts a block, by setting the status back to `ready`. The same for `needs-decision`.
- 2026-09-07 · Work through the ready items: do not ask per item; stop only for a decision only the user can make, or when they asked to be consulted per item.
- 2026-09-07 · Fable goes where judgement is cheap and decisive: the batch Orchestrator and the security review of security-definer, RLS-predicate or trigger changes. Engineers, QA and Explore never move above the tier ladder. Judged on ngm.app #31 after the first two batches.
- 2026-09-08 · The architect writes the capped design on Opus; Fable reviews it (`MODE: review`, ≤ 40 lines) on every tier-3/4 design. The one Fable-written design cost ≈ 2.8× an Opus one.
- 2026-09-08 · A small two-sided change with no new policy goes to one `fullstack-engineer` (Sonnet) instead of two engineers; review stays independent.
- 2026-09-08 · Local migration validation is `check-db.sh` on an embedded Postgres (ngm.app ticket T4), not Docker and not a CI job.
- 2026-09-07 · Member-submitted content is moderated (pattern P1); anonymity is enforced in the database, not the UI. Storage is private buckets with signed URLs and per-member caps (P2); no public buckets.
- 2026-09-07 · Auto-moderation ships inert in prod (`auto_approve_enabled` false) until an admin turns it on; the seeded threat rules are reviewed first (#59).
- 2026-09-08 · The PM conversation runs on the model `settings.json` pins (Opus in `ngm.app`); it is not raised to Fable by hand.
