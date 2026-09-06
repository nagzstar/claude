# Feature prompt — NGM mobile app (Apple App Store + Google Play)

A ready-to-paste brief for driving NextGenMaher's mobile work with this agent system.
Start a Claude Code session **inside `ngm.app`** (so task records land with the code) and
paste one phase block. The Orchestrator does the rest: tiering, delegation, review, commit,
push, pipeline, DEV validation.

Background and the ratified design live in the repo, not here — the prompts point at them:

- `.agent-context/tasks/mobile-app.md` — the task record, acceptance criteria, audit, log
- `.agent-context/tasks/mobile-app-design.md` — the ratified technical design
- `.agent-context/project.md` — "Roadmap — mobile version"

---

## What only you can do

Everything below is blocked on your identity or your money. Nothing else in the plan is.
Claude will build, test and validate everything that is not on this list, and stop here.

| # | Action | Cost | Blocks |
|---|---|---|---|
| 1 | Enrol in the **Apple Developer Program** (individual or organisation) | **$99/year** | Every iOS step: signing, TestFlight, App Store submission |
| 2 | Register a **Google Play Console** developer account | **$25 one-off** | Play internal testing and release |
| 3 | Supply a **1024×1024 square logo** (PNG, no transparency, no rounded corners) | free | The App Store icon. The repo's best source is `app/src/assets/NextGen.jpg` at 987×1024 — close, but a JPEG and not square, so icons generated from it will be soft |
| 4 | Decide the **published app name and bundle ID** if not `com.nextgenmaher.app` | free | Store listings, deep links, signing |
| 5 | Provide a **privacy policy URL** on a public page | free | Both stores refuse a listing without one for an app with accounts |
| 6 | Confirm the **age rating** and that NGM works with minors | free | Both stores; affects review path and required disclosures |

Item 6 matters more than it looks: NGM is a youth mentorship platform, so both stores apply
their children's-privacy rules, and Apple applies guideline 1.2 (user-generated content) which
requires content filtering, a report mechanism, a block mechanism, and published contact info.
NGM already has admin moderation of every message and response, which is most of the way
there — the design records what is missing.

---

## Phase 1 — foundation (no accounts needed)

> This is the phase Claude can complete alone, and may already be done. Check the task file
> before pasting it.

```
Read .agent-context/tasks/mobile-app.md and .agent-context/tasks/mobile-app-design.md, then
implement Phase 1 of the ratified design: the native shell, the mobile build configuration,
safe-area handling across the app shell, and the app icon and splash assets.

The web app at https://dev.nextgenmaher.com must behave exactly as it does today — same
pipeline, same artefact, no regressions. Do not change AuthContext's data-fetching pattern,
do not add react-query, do not touch RLS.

Carry it to DEV: check-app must pass with no new lint problems, commit and push to main,
watch the pipeline, and validate the web app still works. Report READY FOR PROD or what is
blocking. Do not deploy to production.
```

## Phase 2 — auth and deep links on device

```
Read .agent-context/tasks/mobile-app-design.md and implement the mobile auth phase: session
persistence in the native webview, token refresh when the app is resumed, and the custom-scheme
deep links so password reset and email confirmation return into the app instead of a browser.

This changes terraform/env/*.tfvars uri_allow_list, so backend-engineer owns it and
security-reviewer must sign off that no existing redirect control is weakened. Apply to DEV
only; prepare the prod values but do not dispatch prod.
```

## Phase 3 — Android build in CI

```
Read .agent-context/tasks/mobile-app-design.md and add the Android build to CI per the design:
a manual-dispatch workflow on ubuntu-latest producing a signed-debug APK as an artifact.

Actions minutes are the scarcest free resource — it must not run on every push, and it must
not widen any existing path filter. Keep the infrastructure and application pipelines separate.
Validate by dispatching it for dev and confirming the artifact downloads and installs.
```

## Phase 4 — store submission (needs your accounts)

```
Read .agent-context/tasks/mobile-app-design.md. I have completed the account actions in
prompts/mobile-app.md. Prepare everything for first submission to <Google Play | the App Store>:
store metadata, screenshots at the required sizes, the Data Safety / App Privacy declarations
for an app with user accounts and user-generated content, and the release build configuration.

Tell me exactly which steps I must perform by hand in the console, in order. Do not submit
anything on my behalf.
```

---

## Follow-on prompts

Ordinary outcome statements once the foundation is in place. The Orchestrator tiers them.

```
Make the participant message flow feel native on a phone — pull to refresh and no rubber-band scroll.
Add push notifications for a new response to my message.
The app shows a white flash on launch before the first screen paints. Fix it.
Cut the mobile bundle so the app opens faster on a cold start over 4G.
Prepare a release build and tell me what I need to click to ship it to internal testing.
```

## Guardrails that stay in force

- **PROD is yours.** The team stops at READY FOR PROD with release notes and risks, and a
  store submission is a production act — it will be prepared, never submitted, for you.
- **Free or as close to free as possible.** The only new costs are the two store fees above.
  No paid CI, no paid build service, no paid distribution tooling. macOS runners bill Actions
  minutes at a 10× multiplier, so iOS builds are not free and the design says how they are
  handled.
- **One frontend, one backend.** Supabase stays the single backend and the existing SPA stays
  the single UI codebase. Reject anything that forks them.
