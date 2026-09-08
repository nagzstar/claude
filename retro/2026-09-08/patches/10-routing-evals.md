# 10 — Routing eval cases from the real tickets (B)

**Finding.** H7: the routing eval set (14 synthetic cases) has no case shaped like the tickets that
were actually mis-routed: #56 (UI consolidation → architect dispatched), #4/#12/#13 (frontend on
Opus without a stated tier), #33 (backend-only security fix, correctly no architect), #55 (small
two-sided change on an existing trigger), #68 (new tables + edge function with an unsettled source
decision → should stop at NEEDS-USER, not design).

**Expected effect.** `evals/run-routing-evals.sh` catches the same mistakes before they cost a run;
the guard in patch 02 enforces the model part at run time.

Append to `evals/routing-cases.json` (before the closing `]`):

```json
  {
    "id": "ui-consolidation-56",
    "prompt": "Admin moderation hub: one page with a tab per queue (messages, stories, resources), pending counts in the sidebar and on the dashboard; legacy admin routes redirect. No new tables, no RLS change. Pattern: P4.",
    "expect": { "tier": 2, "agents": ["Explore", "frontend-engineer", "qa-engineer"], "parallel": false, "must_not_invoke": ["researcher-architect", "security-reviewer", "backend-engineer"], "models": { "frontend-engineer": "claude-sonnet-5" }, "stops_at": "READY FOR PROD" },
    "why": "Cross-cutting pages but a catalogued pattern and no security surface: Explore maps the pages, Sonnet builds, QA verifies. #56's first run spent an architect on this and lost the run."
  },
  {
    "id": "backend-security-fix-33",
    "prompt": "Deactivated members: the avatar stays readable while is_approved() requires is_active. Make deactivation hide the avatar and the directory entry, in the two security-definer functions.",
    "expect": { "tier": 3, "agents": ["backend-engineer", "security-reviewer", "qa-engineer"], "parallel": true, "must_not_invoke": ["researcher-architect", "frontend-engineer"], "models": { "backend-engineer": "claude-opus-5", "security-reviewer": "claude-opus-5" } },
    "why": "Edits definer functions: Opus backend and mandatory security review; the contract is derivable, so no architect; QA and security run in parallel."
  },
  {
    "id": "moderated-table-pattern-8",
    "prompt": "Success Stories: members submit a story with an optional photo, admins moderate, approved stories are public, author can be anonymous. Pattern: P1 + P2 + P3, no deviation.",
    "expect": { "tier": 3, "agents": ["backend-engineer", "frontend-engineer", "qa-engineer", "security-reviewer"], "parallel": true, "must_not_invoke": ["researcher-architect"], "models": { "backend-engineer": "claude-opus-5", "frontend-engineer": "claude-sonnet-5" } },
    "why": "Three catalogued patterns and no deviation: the Orchestrator writes the contract from patterns.md; new RLS means Opus backend + security; frontend stays Sonnet."
  },
  {
    "id": "small-two-sided-55",
    "prompt": "Auto-moderation: profanity and threat matches are rejected outright instead of held; the admin queue shows 'Auto-rejected'. One trigger function changes, one admin page changes.",
    "expect": { "tier": 3, "agents": ["backend-engineer", "frontend-engineer", "qa-engineer", "security-reviewer"], "parallel": true, "must_not_invoke": ["researcher-architect"], "models": { "backend-engineer": "claude-opus-5", "frontend-engineer": "claude-sonnet-5" } },
    "why": "A trigger on a member-writable table is tier 3 for the backend half only; the UI half is routine Sonnet work; no design needed."
  },
  {
    "id": "unsettled-source-decision-68",
    "prompt": "Career pathways: pick a job, see routes, qualifications and resources. The data source is still being discussed (scraped GOV.UK pages vs a curated seed vs an API).",
    "expect": { "tier": 3, "agents": [], "orchestrator_does_it": false, "must_not_invoke": ["researcher-architect", "backend-engineer", "frontend-engineer"], "stops_at": "NEEDS-USER" },
    "why": "A product decision that changes the data model is open: stop at NEEDS-DECISION before spending a design. #68 was designed twice and paused twice."
  }
```

`validate.sh` section 5 already validates agent names and tiers; add `"Explore"` is accepted (it
is). Run `bash evals/run-routing-evals.sh --only ui-consolidation-56` etc. once with the models the
orchestrator uses (Opus for a lone ticket, Fable for a batch); results go to `evals/results/`.
