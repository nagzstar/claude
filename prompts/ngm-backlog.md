# NGM Backlog — GitHub Project setup prompt

A one-session setup: a GitHub Project on `nagzstar/ngm.app` that becomes the single place
for feature ideas, bugs and improvements, so future sessions can be told "add this idea" or
"pick up #25" without re-explaining anything. Start the session **inside the agent-system
repo** (`C:/Users/nagaj/git/claude`), because the durable part of this work is a skill that
teaches every future session the vocabulary; the issues themselves land in `ngm.app`.

## Facts a fresh session cannot derive

| Fact | Value |
|---|---|
| Existing projects / issues on `ngm.app` | none (verified 2026-09-07) |
| Existing labels worth keeping | `bug` (default set is present; do not delete it) |
| Existing backlog to migrate | `.agent-context/lessons.md` → "Problems spotted" |
| Cost | £0 — GitHub Projects and Issues are free on GitHub Free |

## What only you can do

| Item | Cost | Blocks |
|---|---|---|
| Grant the active `gh` token Projects read/write if `gh project create` is refused. The fine-grained PAT in `GH_TOKEN` can read Projects; write is unverified. Fix at github.com/settings/tokens, or `gh auth refresh -s project` for the keyring token. | £0 | project creation only; labels and issues work with `repo` scope |

Nothing else is blocked on you.

## The prompt

```
Set up the NGM backlog: one GitHub Project plus Issues on nagzstar/ngm.app that is the
source of truth for future work, so I can later say "add this idea" or "pick up #25".
Keep it simple; do not over-engineer it.

Project
- User-owned Project named "NGM Backlog", linked to nagzstar/ngm.app, board view.
- Status options exactly: Ideas, Ready, In Progress, Done. Remove the default options.
- No other custom fields, no iterations, sprints, milestones, story points, views or
  Actions workflows (Actions minutes are scarce). Use only the built-in project workflows:
  "item added → Ideas" and "issue closed → Done". Auto-add is a paid feature; Claude adds
  every issue to the project itself when it creates one.

Labels (create if missing, leave the default labels alone): feature, bug, improvement,
infrastructure, security, ui, admin, mobile. Use `feature`/`improvement`, never
`enhancement`.

Issue format — title: short, verb-first, under 70 characters. Body:

  ## Idea
  What I want to add or change.
  ## Notes
  Context, requirements, thoughts. If I gave none, write what I said and nothing more.
  ## Acceptance Criteria
  Only when the task is clear enough to say what done means.

Seed: file each entry under "Problems spotted" in .agent-context/lessons.md as its own
issue in Ideas with the right label, then replace that section with a pointer to the
project. One issue per item; do not merge or reword the substance.

How future sessions use it — write this into a new skill
.claude/skills/ngm-backlog/SKILL.md (project number and URL, status names, labels, the gh
commands that work, and these rules), add one line to CLAUDE.md pointing at it, and change
the COMPLETE step so "Problems Spotted" are filed as Ideas issues instead of appended to
lessons.md:
- "Add this idea / create an issue": create the issue in the format above, label it, add
  it to the project in Ideas, reply with the number and link. Do not ask clarifying
  questions; thin Notes are fine.
- "Show me the ideas / the backlog": list issues by status, newest first, number + title.
- "Move #N to Ready" is my signal only. Claude may suggest an item is Ready, never move it.
- "Pick up #N": read the issue, move it to In Progress, treat the body as the outcome and
  run the normal lifecycle. The task file names the issue, commits reference #N, and Claude
  comments on the issue with the commit sha and DEV validation evidence. READY FOR PROD is
  asked as usual; the issue closes (→ Done) only on RELEASED TO PROD or when I say so.
- "Work through the Ready items": top to bottom, one at a time, each carried to DEV with
  its own commit, then one combined READY FOR PROD unless an item warrants its own release.
- Claude never deletes issues or closes them as not planned unless I say so.

Do it with the GitHub CLI. If project creation is refused for token scope, stop and tell
me exactly which permission to add; do the labels and skill first so nothing is wasted.
Run scripts/validate.sh, install the updated system into ngm.app with
scripts/install-into-repo.ps1, and commit both repos. Nothing here deploys anything; the
existing rule stands — DEV is yours, production deployment is mine to approve.

When done, show me: the project name and link; the statuses; the labels; the exact
phrases I should use to add an idea; and how you retrieve and start an existing one.
```

## Phrases once it exists

- Add this to the NGM backlog: dark mode for the admin pages.
- Show me the backlog.
- Move #12 to Ready.
- Pick up #25 and implement it.
- Work through the Ready items.

## Guardrails that stay in force

- PROD is the user's decision every time; the project changes nothing about that.
- Free tier only: no paid project features, no Actions workflows driving the board.
- The project is a backlog, not a design store — designs and task records stay in
  `.agent-context/`; an issue links to them, never restates them.
