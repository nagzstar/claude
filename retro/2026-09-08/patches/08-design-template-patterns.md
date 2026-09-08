# 08 — Capped design template, review mode, pattern catalogue (B)

**Finding.** H9/H7: five designs of 62–81 KB (950–1,364 lines, 18–42 code fences) written in one
shot, read 3–7× per run; the same shape ("moderated member-submitted table + private bucket + push")
designed in #13, #8 and #12; an architect ran on a tier-2 UI ticket (#56, lost run) and the rerun
delivered without one. The Orchestrator reads the whole design (#4: 67 KB in 6 chunks).

**Expected effect.** ≈ −50 K output and ≈ −100 K cache-create per designed issue; the architect is
skipped for a catalogued pattern (≈ −$4.4, −16 min); the Orchestrator reads only `## 1 Decisions`.
The cap is enforced by patch 06.

## `researcher-architect.md` — replace the `## Output` section (lines 70–103) with:

```markdown
## Output — the design file (hard cap 28 KB / ≈ 400 lines, hook-enforced)

Write `.agent-context/tasks/<slug>-design.md` in exactly this shape and return only its
`## 1 Decisions` section plus Status. Never restate `project.md`/`security-model.md`; never paste
SQL or TSX beyond a 10-line shape — the engineers write the code from the contract.

1. **Decisions** — ≤ 15 numbered lines: what was decided and the one reason. This is the section
   the Orchestrator and the reviewers read.
2. **Contract** — tables/columns (name · type · nullable · default, one line each), RPC/edge
   function signatures, storage buckets and key shapes, push events. ≤ 80 lines.
3. **Authorization** — one line per verb and role: who may create/read/update/delete/approve, and
   the enforcement point (policy name or function). ≤ 20 lines.
4. **Pattern** — which catalogued pattern from `.agent-context/patterns.md` this follows, and every
   deviation from it. "None" only with a reason.
5. **Migration and compatibility** — order, backfill, what the deployed frontend sees mid-deploy.
   ≤ 15 lines.
6. **backend-engineer section** — files to create/change, numbered acceptance criteria it owns.
7. **frontend-engineer section** — the same. Cross-cutting files: named owner.
8. **AC mapping** — ticket AC number → section that satisfies it.
9. **Risks / NEEDS-DECISION** — ≤ 10 lines.
Delete any section that is genuinely empty. Findings that only support a decision go in a
one-line "Basis:" note under that decision, not in a findings chapter.

## Review mode

When the handoff says `MODE: review`, you do not design. Read the existing design and the files it
names; return ≤ 40 lines: decisions you would change (with the reason), authorization gaps, missing
AC mappings, and PASS | FAIL. Write nothing.
```

Delete the current `## Output` block and the "Return exactly this shape" template (Findings /
Relevant files / Current architecture / … / Status): that shape produced the 60–80 KB documents.

## New file `.agent-context/patterns.md` (installed; ≤ 3 KB; the architect and the Orchestrator cite it)

```markdown
# NGM pattern catalogue — cite by name in tickets ("Pattern: P1") and designs
Each pattern names the reference implementation; a new instance copies it and lists deviations.
Skip the architect when a ticket names one pattern and lists no deviation that changes authorization.

**P1 Moderated member submission** (ref: success stories `20260907200000_success_stories.sql`,
`SuccessStoriesPage.tsx`, `AdminSuccessStories.tsx`): table with `status pending|approved|rejected`,
`author_id`, `is_anonymous`; SELECT policy = own rows OR approved OR admin; INSERT own with
`status = pending`; UPDATE own while pending; admin UPDATE/DELETE; `auto_moderation_*` hook;
public read via a security-definer `get_public_<x>()` that withholds author fields when anonymous.
**P2 Private bucket with signed URLs** (ref: avatars/story photos, `profile_specialties_avatar_bio`
migration, `SafeExternalLink`, `createSignedUrls`): bucket private; key `<entity_id>/<uuid>.<ext>`
(never the author id); storage policies mirror the table's SELECT; per-member object cap.
**P3 Admin push fan-out** (ref: `supabase/functions/send-push`): one event name per feature; the
function is the only writer; pending-count push to admins on submission; member push on approval.
**P4 Admin queue page** (ref: `app/src/components/admin/moderation/*Queue.tsx`): tab in the
moderation hub; pending count in the sidebar via `AuthContext`; approve/reject/edit inline.
**P5 Directory RPC over member data** (ref: `get_mentor_directory()`): security-definer returning
only approved, active members; role-specific columns withheld fail-closed.
```

## CLAUDE.md — PLAN and REVIEW lines

```diff
@@ -54,9 +54,11 @@
 - **PLAN.** Restate the outcome as numbered acceptance criteria. Classify the tier (below).
   Decide the smallest team. Write the contract (data model, authorization rule and where it
-  is enforced, frontend/backend split, file ownership) — from `project.md` if you can, via
-  `researcher-architect` if you cannot. Create `.agent-context/tasks/<slug>.md` from
+  is enforced, frontend/backend split, file ownership) — from `project.md` and
+  `.agent-context/patterns.md` if the ticket names a pattern; via `researcher-architect` only
+  when no pattern fits or a decision must be agreed (then read only its `## 1 Decisions`; never
+  the whole design). Create `.agent-context/tasks/<slug>.md` from
```
