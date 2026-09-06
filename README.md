# NGM Engineering Team

A six-role agent team for the **NextGenMaher** application
(`C:/Users/nagaj/git/ngm.app`). This repo is the configuration source of truth;
the application repo is untouched by it.

## How to use it

Run Claude Code from this directory and state the request plainly:

```
Fix the mentor dashboard crash when a message has no responses.
Add push notifications for new mentor responses.
Review the security of the admin user-management flow.
Add a PR pipeline that runs tests before merge.
Make the participant message list usable on a phone.
```

The Orchestrator is the session you are talking to. It reads `CLAUDE.md` automatically,
loads `.agent-context/project.md`, decides which specialists (if any) are needed,
delegates with scoped handoffs, reviews the results, and reports back.

You should not need to name agents or manage context. If you want to constrain it,
say so in the request ("frontend only", "don't touch the database", "investigate, don't
implement").

## Cost

NGM must stay **free or as close to free as possible** — treated as a hard requirement, not a
preference. The stack is GitHub Free, GitHub Actions free minutes, HCP Terraform free tier,
the Supabase free plan and Cloudflare Pages + DNS; the only recurring cost is the
`nextgenmaher.com` domain. No agent will adopt a paid plan, add-on, runner or service without
asking you first and telling you what the free alternative gives up.

## Deployment authority

**DEV is autonomous.** The team carries work through `CODE → COMMIT → PUSH → PIPELINE →
DEV DEPLOY → VALIDATION` at https://dev.nextgenmaher.com without asking for approval at each
step. Work goes **directly to `main`** (repo `nagzstar/ngm.app`) — that push is what triggers
the dev deploy. No PR flow, no branch protection.

**PROD is yours.** The team stops at **READY FOR PROD** with release notes and risks, and
never dispatches a production deployment. Note this is enforced by policy, not by GitHub —
branch protection and required reviewers are unavailable on a private free-plan repo.

## Layout

```
CLAUDE.md                          Orchestrator contract (always in context — kept short)
.claude/agents/*.md                The five specialists (loaded only when invoked)
.claude/settings.json              Repo access + safety rails
.agent-context/project.md          Architecture summary — read instead of re-exploring
.agent-context/security-model.md   Roles, RLS, the dual-role-system hazard
.agent-context/delivery.md         Pipelines, environments, release gates (delivery work only)
.claude/skills/ngm-facts/          Authoritative NGM environment + deployment facts
.agent-context/handoff.md          Delegation and task-file formats
.agent-context/tasks/              Per-task shared state
scripts/install-into-repo.ps1      Optional: deploy into the NGM repo itself
```

## Maintenance

- `project.md` and `security-model.md` are updated only when the architecture actually
  changes. Keep them short — they are read on every task, so every line costs tokens
  forever. If either drifts from the repo, the repo wins.
- To reduce cost further, set `model: sonnet` in a specialist's frontmatter. They are
  currently `inherit` (they run on whatever model the session uses). `qa-security` is
  the one to leave on the stronger model — a missed authorization bug is the expensive
  failure.
- To run from inside the NGM repo instead, run `scripts/install-into-repo.ps1`.
