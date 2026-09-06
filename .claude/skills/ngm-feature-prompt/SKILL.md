---
name: ngm-feature-prompt
description: Write a reusable, pasteable feature prompt that briefs the NGM Orchestrator on a new piece of work — used when the user asks for "a prompt I can use to start X", a brief for a multi-phase feature, or any feature too large to hand over as a single outcome sentence. Produces prompts/<slug>.md in the agent-system repo. Do not load for ordinary tasks: a normal outcome sentence needs no prompt document.
---

# Writing an NGM feature prompt

A feature prompt is a **document the user pastes into a future session** to start a large or
multi-phase feature. It exists to save the next session from re-deriving scope, cost and
sequencing. It is not a design, not a task file, and not a plan — those live in
`.agent-context/`.

Write one only when the work is genuinely multi-session or partly blocked on the user.
For anything the Orchestrator can take from a single outcome sentence, say so and stop.

## Where it goes

`prompts/<slug>.md` in the agent-system repo (`C:/Users/nagaj/git/claude`). One file per
feature. It is committed there; it is **not** installed into `ngm.app` by
`scripts/install-into-repo.ps1`, so the prompt document does not need to survive a sync.

## The one rule that matters

**Reference, never restate.** The prompt points at `.agent-context/tasks/<slug>.md` and
`<slug>-design.md` and lets the future session read them. Never paste the design, the
architecture, file contents, or `project.md` into the prompt — that is the token cost this
skill exists to avoid. The prompt carries only what a fresh session cannot derive from the
repo: the phase split, what is blocked on the user, and the guardrails.

## Structure

Follow this order. Drop any section that is genuinely empty; never pad.

1. **Title + one-paragraph orientation.** What the feature is, and that the user should start
   the session inside `ngm.app` so task records land with the code.
2. **Pointers.** The three or four repo paths holding the real detail.
3. **"What only you can do".** A table of every item blocked on the user's money, identity,
   accounts or a decision only they can make — with a **real cost figure** for each and what
   it blocks. This is the most valuable section: it is what lets the user unblock the work in
   one sitting. If nothing is blocked on them, say so explicitly.
4. **Phases**, each a fenced block the user pastes verbatim. **Order by what is blocked**:
   every phase needing nothing from the user comes first. Each block must state the outcome,
   what must not regress, the patterns not to change, and end with the DEV-to-PROD boundary.
5. **Follow-on prompts.** Three to six plain outcome sentences for once the foundation lands —
   these show the user the system's normal mode and that the prompt document is scaffolding,
   not a permanent requirement.
6. **Guardrails that stay in force.** PROD authority, the free-tier rule, and any
   feature-specific invariant (e.g. one frontend, one backend).

## Writing the phase blocks

Each fenced block is read by an Orchestrator with no memory of this session. It must:

- open by telling it which task and design files to read;
- state the outcome in user terms, not a task list;
- name what must **not** change — the usual suspects are `AuthContext`'s data-fetching
  pattern, RLS policies, pipeline separation, and existing path filters;
- carry the work to DEV explicitly ("check-app must pass, commit, push, watch the pipeline,
  validate on dev.nextgenmaher.com") because the non-negotiable is that DEV is autonomous;
- end with "ask me before any production deployment" whenever the phase touches anything
  deployable — the Orchestrator asks "Shall I deploy this to prod?" by default, and the
  phrase keeps that visible to the user reading the prompt.

Do not put tier or agent names in the block. The Orchestrator classifies the tier itself; a
prompt that hardcodes the team will be wrong as soon as the design changes.

## Cost discipline

Every cost the feature implies must appear as a figure in the "What only you can do" table —
store fees, paid runners, paid services, anything. The free-tier rule is a hard requirement,
so a prompt that quietly implies spending is a defect. If a phase can only be done at cost,
state the cost, state the free alternative and what it gives up, and leave the choice to the
user rather than assuming it.

## Checklist before you hand it over

- [ ] Nothing in the document restates the design, architecture or file contents.
- [ ] Every user-blocked item has a real cost figure and names what it blocks.
- [ ] Unblocked phases come before blocked ones.
- [ ] Every deployable phase ends at DEV and asks before prod; none deploys prod unasked.
- [ ] Each phase block is pasteable standing alone, with no reference to "this conversation".
- [ ] The task file `.agent-context/tasks/<slug>.md` exists and the prompt points at it.
- [ ] Under about 150 lines. If it is longer, detail has leaked in from the design.
