---
name: ngm-standing-rules
description: The standing rules every NGM specialist works under — cost, deployment authority, ownership, secrets, verification and reporting. Preloaded into every specialist agent; the Orchestrator's copy is in CLAUDE.md. Load manually only if you are acting as a specialist without the preload.
---

# NGM standing rules (specialists)

`NGM_ROOT` = `C:/Users/nagaj/git/ngm.app`, branch `main`. Architecture summary:
`.agent-context/project.md` — read it before touching the repo; do not re-derive it.

1. **Cost is a hard requirement.** NGM runs entirely on free tiers; the only recurring cost is
   the domain. Never add a paid plan, add-on, billable resource, commercial service, larger
   runner or paid dependency. If the task genuinely cannot be met for free, report the cost
   and the free alternative and stop — do not adopt the cost yourself.
2. **You do not commit, push or deploy.** Leave your work in the working tree and report.
   The Orchestrator integrates (commits, pushes, watches the DEV pipeline) after review.
   Never dispatch any workflow, never `terraform apply`, `wrangler`, `supabase db push`, or
   force-push. **PROD is the user's decision, always** — never target
   https://nextgenmaher.com or `environment: prod`; only the Orchestrator releases to prod,
   and only after asking the user "Shall I deploy this to prod?" and getting an explicit yes.
   A hook blocks these for you; if it fires, stop and report rather than working around it.
3. **Ownership is exclusive and hook-enforced.** Edit only the paths your handoff assigns to
   you. Cross-cutting files (`app/src/types/index.ts`, `app/src/contexts/AuthContext.tsx`,
   `app/src/integrations/supabase/types.ts`) are edited only by the agent the handoff names.
   If you need a change outside your ownership, put it in your report as a request.
4. **Secrets.** Never read, print or commit `.env` files, `SUPABASE_SERVICE_ROLE_KEY`, API
   tokens or passwords. Never echo a secret into a log, report or commit.
5. **Smallest reasonable change.** Follow the existing neighbouring pattern; no unrequested
   refactors, no reformatting untouched lines, no mass lint fixes, no new dependency without
   a stated reason. Do not "fix" the known constraints listed in `project.md`.
6. **Authorization lives in the database or an edge function.** Route guards and hidden
   buttons are UX. RLS today distinguishes only admin from any-authenticated user; a real
   mentor-only or participant-only rule needs a new database-level check.
7. **Verify before you report.** Run `bash "$CLAUDE_PROJECT_DIR/.claude/scripts/check-app.sh"`
   after any change under `app/`, `supabase/` or that affects the build; paste its summary
   line. It compares lint against the recorded baseline (lint does not pass cleanly on
   `main`; the bar is *no new problems*). Migrations cannot be applied locally — review them
   by reading and say they are unapplied.
8. **Return to the Orchestrator instead of deciding** when: an acceptance criterion is
   ambiguous; the task needs an architectural or authorization decision the handoff did not
   make; you would have to edit a file you do not own; the free option does not exist; or a
   verified fact contradicts the handoff or `project.md`. Report status `BLOCKED` or
   `NEEDS-DECISION` with the specific question. Do not guess and do not widen scope.
9. **Report honestly.** State what you ran and the real result. Never claim verification you
   did not perform; list what is unverified. If you could not finish, say exactly what is done
   and what is not.
