# NGM pattern catalogue

Cite a pattern by id in tickets (`## Pattern: P1 + P2`) and designs. Each names the reference
implementation in `NGM_ROOT`; a new instance copies it and lists its deviations. **The architect is
skipped when a ticket names one or more patterns and no deviation changes authorization** — the
Orchestrator writes the contract from the reference files. Three of the five designs written on
2026-09-07 (#13, #8, #12) were P1 + P2 + P3 designed from scratch; that is what this file replaces.

**P1 — Moderated member submission.** Reference: success stories —
`supabase/migrations/20260907200000_success_stories.sql`, `app/src/pages/SuccessStoriesPage.tsx`,
`app/src/pages/admin/AdminSuccessStories.tsx`. Table with `status pending|approved|rejected`,
`author_id`, optional `is_anonymous`; SELECT policy = own rows OR approved OR admin; INSERT own
with `status = 'pending'`; UPDATE own while pending; admin UPDATE/DELETE; the `auto_moderation_*`
trigger path applies; public read through a security-definer `get_public_<x>()` that withholds
author fields fail-closed when anonymous (anonymity is enforced in the database, never the UI —
#8 round 1). Policies are replaced by exact name (`DROP POLICY IF EXISTS` + `CREATE POLICY`).

**P2 — Private bucket with signed URLs.** Reference: avatars and story photos —
`supabase/migrations/20260907120000_profile_specialties_avatar_bio.sql`, `SafeExternalLink`,
`createSignedUrls` call sites. Bucket private; object key `<entity_id>/<uuid>.<ext>` (never the
author id); storage policies mirror the owning table's SELECT; a per-member object cap; signed
URLs minted client-side for the current session only.

**P3 — Admin push fan-out.** Reference: `supabase/functions/send-push/` and its README. One event
name per feature; the edge function is the only writer of push rows; pending-count push to admins
on submission; member push on approval; never a push from a trigger directly.

**P4 — Admin queue page.** Reference: `app/src/components/admin/moderation/*Queue.tsx` and the
moderation hub (#56). A tab in the hub; pending count in the sidebar via `AuthContext`;
approve / reject / edit inline; legacy route redirects to the hub tab.

**P5 — Directory RPC over member data.** Reference:
`supabase/migrations/20260907140000_get_mentor_directory.sql` (`get_mentor_directory()`).
Security-definer returning only approved, active members; role-specific columns withheld
fail-closed (`CASE WHEN … THEN NULL`); no direct table read from the client.

Adding a pattern: only after it has shipped twice; one paragraph, reference files, the
authorization rule, the known deviations. Keep this file under 4 KB.
