# EXAMPLE — Save mentor responses as favourites

This is a worked example of the task-file format, produced from a real read of the
repository. It is a design, not implemented work. Delete or ignore it once you have
real tasks; it exists to show the shape.

Status: EXAMPLE (not implemented)
Owner: Orchestrator
Tier: 2 (established pattern: table + RLS + context method + page)
Base commit: n/a (example)
Updated: 2026-09-06

## Goal
A participant reading mentor responses can save one as a favourite and later find all
their saved responses in one place, so useful advice isn't lost in the message list.

## Acceptance Criteria
1. An authenticated user can favourite and unfavourite an approved response.
2. The control shows current state and is reachable by keyboard, on desktop and mobile.
3. A user sees only their own favourites; no user can read or modify another user's.
4. A "Saved" view lists the user's favourites with the response, its parent message
   title, and the responder's name, newest first.
5. Unfavouriting removes it from the Saved view without a page reload.
6. Favouriting the same response twice does not create a duplicate row.
7. If a response is later unapproved or deleted, it disappears from the Saved view
   rather than erroring.
8. Empty state explains how to save a response.
9. `npm run build` and `npm run test` pass, with no new lint problems vs the baseline.

## Architecture Decisions
Decided by the Orchestrator from `project.md` + `security-model.md`. No researcher needed:
the pattern (new table + RLS + AuthContext mutation + page) is already established in
this repo, so there is nothing to investigate.

**Data model** — new table `public.favourites`:
`id uuid pk default gen_random_uuid()`, `user_id uuid not null references auth.users(id) on delete cascade`,
`response_id uuid not null references public.responses(id) on delete cascade`,
`created_at timestamptz not null default now()`, `unique (user_id, response_id)`.
Index on `(user_id, created_at desc)`. The unique constraint delivers criterion 6;
`on delete cascade` delivers half of criterion 7.

**Authorization** — RLS on, four policies, all `TO authenticated`, all ownership-scoped:
- SELECT `USING (user_id = auth.uid())`
- INSERT `WITH CHECK (user_id = auth.uid() AND EXISTS (SELECT 1 FROM public.responses r WHERE r.id = response_id AND r.status = 'approved'))`
- DELETE `USING (user_id = auth.uid())`
- no UPDATE policy — a favourite is created or removed, never edited.

Deliberately **not** admin-readable: favourites are private. This is a departure from the
usual "or admin" clause and is intentional.

The INSERT check on `status = 'approved'` matters: without it a mentor could favourite
their own pending response and the Saved view would surface unmoderated content.

**Note on roles** — the brief says "participants". RLS cannot express that: it only
distinguishes admin from authenticated (see `security-model.md`). Restricting the *button*
to participants would be UI-only and not a real boundary. Decision: any authenticated user
may favourite; ownership is the real control, and it is enforced. Mentors saving useful
responses is harmless. If participant-only is a genuine requirement, it needs a
`profiles.role`-based DB check and should be raised as a separate decision.

**Read path** — the Saved view joins through the existing `responses` SELECT policy, which
already hides non-approved responses. So an unapproved-but-not-deleted response drops out
of the view automatically — the rest of criterion 7.

**Frontend/backend split** — backend owns the migration; frontend owns the context method,
the control and the page. Contract below.

**Contract**
- `favourites` rows as above.
- Frontend calls Supabase directly (the existing pattern — no edge function needed, since
  RLS fully expresses the rule).
- `AuthContext` gains: `favourites: Favourite[]`, `addFavourite(responseId)`,
  `removeFavourite(responseId)` — matching the shape of the existing `addResponse` /
  `updateResponseStatus` methods.
- `app/src/types/index.ts` gains `Favourite { id, responseId, userId, createdAt }`.
  **Assigned to frontend-engineer** (cross-cutting file, single owner).

**Mobile** — the control is an icon button in the response card's action row; it must meet
tap-target size and not push the card into horizontal overflow at 375px. The Saved view
uses the same card list as `ParticipantMessages`, not a table.

## Relevant Files
| Path | Role | Owner |
|---|---|---|
| `supabase/migrations/<new>.sql` | new table + RLS | backend-engineer |
| `supabase/migrations/20260426211214_*.sql` | responses table + RLS, pattern reference | read-only |
| `app/src/contexts/AuthContext.tsx` | add state + two mutations | frontend-engineer |
| `app/src/types/index.ts` | add `Favourite` | frontend-engineer |
| `app/src/pages/participant/ParticipantMessageDetail.tsx` | add the control | frontend-engineer |
| `app/src/pages/participant/SavedResponses.tsx` | new page | frontend-engineer |
| `app/src/App.tsx` | route | frontend-engineer |
| `app/src/components/AppSidebar.tsx` | nav entry | frontend-engineer |
| `app/src/integrations/supabase/types.ts` | regenerated after migration | Orchestrator assigns |

## Agent Assignments
| Agent | Scope | Status |
|---|---|---|
| backend-engineer | migration + RLS | — |
| frontend-engineer | types, context, control, page, route, nav | — |
| qa-engineer | functional verification + tests | — |
| security-reviewer | authorization review | — |

Backend and frontend run **in parallel** — the contract above is fixed, and their file sets
are disjoint. researcher-architect is **not** invoked.

## Status / Log
- 2026-09-06 — example authored; design derived from existing repo patterns.

## Test Results
Not implemented.

## Remaining Risks
- `integrations/supabase/types.ts` regeneration needs a live DB or the Supabase CLI; if
  unavailable, the new table is typed by hand and flagged.
- Criterion 7's "deleted" half relies on `on delete cascade`, which is only exercised once
  the migration is applied in CI — not verifiable locally.
