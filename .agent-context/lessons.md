# NGM — Lessons learnt and problems spotted

Cumulative across tasks. The Orchestrator reads this at boot and appends at COMPLETE.
Keep entries to one or two lines with the date and task. When a lesson is folded into
`project.md`, `security-model.md` or `delivery.md`, remove it from here. Problems below are
the backlog of outcomes the user can pick from — each with an owner and a tier.

## Lessons learnt

- 2026-09-06 · user-signup-approval · Replacing an RLS policy means `DROP POLICY IF EXISTS` +
  `CREATE POLICY` with the **exact existing name**; a typo silently leaves the old permissive
  policy OR'd next to the new one. Check every name against the migration that created it.
- 2026-09-06 · user-signup-approval · A trigger on `auth.users` collides with any edge function
  that inserts the profile row itself; those functions must upsert on `id` in the same commit.
- 2026-09-06 · user-signup-approval · Sessions get interrupted mid-task. Work on disk survives;
  assess it from the task log before starting anything new (now the boot resume check).
- 2026-09-06 · user-signup-approval · Migration and app deploy run concurrently, so every
  migration must tolerate the currently deployed frontend (`DEFAULT 'approved'` was the
  backfill and the compatibility guard at once).
- 2026-09-06 · agent-system-review · Numbers in prompts rot within a day (lint counts, test
  counts, migration counts). Put facts in a file a script reads, not in prose.
- 2026-09-06 · agent-system-review · Whoever commits owns integration. Engineers committing
  independently produced racing pushes and an empty diff for QA.
- 2026-09-06 · agent-system-review · A dev validation failure may be a paused free-tier
  Supabase project, not broken code. Check the project state before debugging.
- 2026-09-06 · user-signup-approval · **A green pipeline is not a working feature.** Signup was
  deployed, both pipelines green, and completely dead — three times over, each time a Supabase
  auth setting that lived only in the dashboard. Move provider settings into Terraform in the
  same task that depends on them.
- 2026-09-06 · user-signup-approval · When an assumption cannot be verified, build for **both**
  branches. The design assumed email confirmation was off; it was on, and the signup UI already
  handled both outcomes, so the discovery cost nothing instead of a rework.
- 2026-09-06 · user-signup-approval · Map new backend fields **fail-open** in the frontend
  (`approval_status ?? 'approved'`) so an app deployed ahead of its migration degrades safely.
  Security is unaffected because the database is the real gate.
- 2026-09-06 · user-signup-approval · RLS cannot express column limits. Use `REVOKE UPDATE` +
  `GRANT UPDATE (cols)`, and audit every direct write to the table first — grants bind admins
  too, since admins also connect as `authenticated`.
- 2026-09-06 · user-signup-approval · Prove an authorization gate with a live low-privilege
  session, never by reading SQL, and prove a **positive** case too — a gate that also blocks
  legitimate writes is broken. The live probe is what showed the gate is re-evaluated per
  request rather than baked into the JWT.
- 2026-09-06 · user-signup-approval · When automated QA is blocked, **ask the user to test**
  rather than downgrading a criterion to "unverified". A copy-pasteable browser-console script
  run in the user's own session reaches what an agent holding no credentials cannot.
- 2026-09-06 · user-signup-approval · Gate per-environment infrastructure behind flags in
  `env/*.tfvars` so prod can be prepared, pushed and planned at zero risk and reviewed before
  anyone applies. Read **both** legs of the plan; prod should say `No changes`.
- 2026-09-06 · user-signup-approval · Let the next natural plan/run answer an open question
  instead of spending a dedicated run on it. Actions minutes are the scarcest resource.
- 2026-09-06 · mobile-app · A subagent cut off by an account rate limit keeps its transcript:
  resume it with SendMessage after the reset instead of re-running the handoff cold.
- 2026-09-06 · mobile-app · Present a tier-4 decision as numbered questions with a default;
  say "real people" explicitly where a rule needs humans, or the user will ask for an agent.
- 2026-09-06 · mobile-app · External figures (store fees, CI quotas, guideline text) go in the
  design with URL and read-date; they rot fastest and must be re-read before each store phase.
- 2026-09-06 · mobile-app-build · A BEFORE ROW trigger cannot count rows inserted by the same
  statement and fires before `ON CONFLICT`; a per-user cap needs an AFTER STATEMENT trigger with
  a transition table.
- 2026-09-06 · mobile-app-build · Any user-writable URL column a service-role process later
  fetches is an SSRF surface: CHECK it in the database and allowlist hosts at the sender.
- 2026-09-06 · mobile-app-build · Corrections go back by resuming the same agent (SendMessage),
  and a reviewer resumed per pass keeps its findings in context; both cost a fraction of a fresh agent.
- 2026-09-06 · mobile-app-build · A workflow file GitHub cannot parse creates a failed zero-job run
  on every push, even when dispatch-only; local YAML parsing cannot catch context rules such as
  `runner` being invalid in job-level `env`. Check `gh run list` right after the first push.
- 2026-09-06 · mobile-app-build · Every workflow triggers only on `main` or a PR, so pushing a
  feature branch is free; a PR touching `terraform/**` would run terraform-plan, so never open one by accident.
- 2026-09-06 · mobile-app-build · Parked work lives on `feature/mobile-app`; its task file is
  committed on both branches and holds the merge-time checklist (re-timestamp the migration!).
- 2026-09-06 · signup-industry-job-title · Every FK from `profiles` to an anon-readable table makes
  `profiles` expressible from anon through PostgREST embedding; only the profiles anon revoke
  stops it. Say so in the migration and in security-model.md each time.
- 2026-09-06 · signup-industry-job-title · Supabase default privileges give `anon` table-level
  writes on every new table; RLS alone blocks them. `REVOKE ... FROM anon` explicitly.
- 2026-09-06 · signup-industry-job-title · Agents CAN run live authorization probes on DEV: the
  `NGM_DEV_*` env vars hold the test accounts and the anon key is in the served bundle. Hand QA
  the variable names and a numbered probe list, never values; positive and negative cases in one pass.
- 2026-09-06 · signup-industry-job-title · Put seed data in the contract, not "backend decides":
  QA verified it programmatically and the product decision is visible in one place.
- 2026-09-06 · display-names-and-user-delete · **A comment asserting a behaviour is not evidence
  of it.** `handle_new_user` carried a comment saying an absent `is_anonymous` key means "own
  name"; the SQL actually produced NULL, because `jsonb_typeof(NULL) = 'boolean'` is NULL and
  `NULL OR false` is NULL, not false. Two agents and a security reviewer read past it because
  the comment described the intent. Live probing caught it in one call.
- 2026-09-06 · display-names-and-user-delete · SQL three-valued logic is the trap that reading
  does not catch. Any boolean built from a possibly-absent jsonb key that feeds a NOT NULL
  column must be wrapped in COALESCE. `IF` treats NULL as false, so the same expression is
  harmless in a branch and fatal in an assignment — which is exactly why it survives review.
- 2026-09-06 · display-names-and-user-delete · A database trigger and an edge function that
  creates users are a pair: `admin-create-user` passes NO metadata to `auth.admin.createUser`,
  so a trigger defect on the absent-key path broke admin user creation completely while the
  public sign-up journey stayed green. Probe BOTH creation paths after any change to
  `handle_new_user`, not just the one the feature is about.
- 2026-09-06 · display-names-and-user-delete · Make privacy controls fail closed. A
  `CASE WHEN p.is_anonymous THEN NULL ELSE p.bio END` publishes the bio when the flag is NULL;
  `COALESCE(p.is_anonymous, true)` withholds it. Withholding a named member's bio is a
  cosmetic bug someone reports; publishing an anonymous member's LinkedIn is silent and
  irreversible once seen.
- 2026-09-06 · display-names-and-user-delete · A FK-free author column is what lets content
  outlive its author. `messages.author_id` / `responses.responder_id` have no FK, so deleting
  a user leaves the board intact and the frontend renders "Deleted user". Keep it that way.
- 2026-09-06 · display-names-and-user-delete · Identity fields leak sideways. Splitting the
  name was not enough: `linkedin` (`linkedin.com/in/firstname-lastname`) and a free-text `bio`
  both carry a real name. When a feature hides one identity field, audit every other column
  the same surface publishes.

- 2026-09-06 · family-name-auto-approval · Rename before a migration runs, never after. The user
  changed the domain word mid-task; nothing was committed or applied, so the table, function,
  column, four policy names, index and filename all moved for free. Once applied it is a second
  migration. Check for terminology corrections BEFORE the first push, not after.
- 2026-09-06 · family-name-auto-approval · A placeholder can leak the answer. `e.g. Modhwadia` on
  the sign-up field was a guaranteed-passing value for the auto-approval check, printed on the
  form. It came from copying the neighbouring fields' placeholder style — the habit of matching
  surrounding code needs an explicit exception for any field whose value IS the access control.
  No example, helper text or error message may contain a passing value.
- 2026-09-06 · family-name-auto-approval · `REVOKE ALL FROM PUBLIC` + `FROM anon` does NOT make a
  GRANT authoritative. Supabase default privileges give `authenticated` ALL on every new table, so
  an explicit GRANT adds to that inheritance and leaves TRUNCATE — which RLS does not filter.
  Revoke from `authenticated` too, immediately before the GRANT.
- 2026-09-06 · family-name-auto-approval · Reviewer findings need the same "prove it against the
  repo" treatment as engineer claims. QA reported the new column as anon-exposed via a policy that
  a LATER migration had already dropped alongside `REVOKE ALL ON public.profiles FROM anon`. One
  grep disproved it. Read migrations in filename order or do not cite them.
- 2026-09-06 · family-name-auto-approval · `check-dev.sh --sha` matches the FULL sha; a short sha
  prints "no workflow runs found" and still exits `CHECK-DEV PASS`. Always pass `git rev-parse HEAD`
  and read the per-workflow lines, never just the verdict.
- 2026-09-06 · family-name-auto-approval · Prove a privacy control with a denied request. The live
  probe distinguished anon blocked at the table grant (`42501 permission denied`) from a member
  blocked by RLS (`200 []`, and PATCH/DELETE touching zero rows) — two different denials, which is
  the defence in depth the design claimed and which reading the SQL cannot demonstrate.
- 2026-09-06 · family-name-auto-approval · When a rule auto-grants access, ask which ROLES it
  covers before shipping. Auto-approval silently extended to self-declared mentors, whose role is
  UI-only and not an authorization boundary; that is a product/safeguarding decision, not an
  implementation detail, and it belonged with the user.

## Problems spotted (backlog — not yet fixed)

- 2026-09-06 · family-name-auto-approval · **Agents have a working DEV admin account** — the
  `NGM_DEV_ADMIN_*` variables plus the anon key from the served bundle are enough to sign in and
  call the admin edge functions. Delete your own test fixtures and run admin-only positive paths
  yourself; the user said so directly ("you can do this yourself, you have an admin account").
  Only browser rendering, a real inbox, and dashboard settings genuinely need the user.

## Web Push notifications (2026-09-06, task `web-push-notifications.md`)

- **Check for parked work before planning a feature.** The whole Web Push + PWA stack already
  existed on `feature/mobile-app`, QA-passed and security-reviewed, parked by the user's own
  earlier decision. The boot resume check only looks for task files with an in-progress
  status; work parked as DONE on an unmerged branch is invisible to it. Read the task index
  before assuming a feature is a build.
- **A trigger `WHEN` clause is NOT inside the trigger function's `EXCEPTION` block**, and it is
  evaluated with the *calling role's* privileges. A guard placed there can abort the parent
  write (e.g. `42501` if the caller lacks EXECUTE on the function it calls). Any check that
  must never break the parent write belongs inside the SECURITY DEFINER function. This applies
  to every fail-open trigger in this repo, not just push.
- **A recipient matrix written as state transitions misses rows born in the target state.**
  `AuthContext.addResponse` inserts a mentor reply with `status:'approved'` directly, so an
  UPDATE-only "response approved" trigger never fired on the main reply path. Always ask
  whether a row can be created already in the state the notification keys off.
- **Prove a deliberate security bypass with a control.** Fire a *different* event at the *same*
  subject with the *same* subscription and require zeros. Showing only that the exempt path
  works does not show the exemption is scoped.
- **`pg_net` IS available on the Supabase free plan** (0.20.4, not installed by default).
  This closes an UNVERIFIED risk carried in `mobile-app-design.md`.
- **~~Pre-existing hole, now urgent~~ — FIXED 2026-09-06** by
  `20260906220000_moderation_status_gate.sql`, see `tasks/moderation-self-approval.md`. An author
  could self-approve their own message and a responder their own response, and (found while
  fixing it) the `responses` INSERT policy had no status check at all, so content could be *born*
  approved — which is what the mentor reply path did. Only an admin may now write a status other
  than `pending`. The compensating push guard is retained as defence in depth.
- **DEV self-signup is currently broken** (`/auth/v1/signup` → 500 "Error sending confirmation
  email"). Resend's free quota is 100/day across the whole account and DEV shares it with
  prod. Use `admin-create-user` to make DEV fixtures instead of the signup flow.
- **Prod needs its own VAPID keypair and webhook secret**, generated separately from dev and
  verified distinct; the public key must be set as the `VAPID_PUBLIC_KEY` variable on the
  `prod` GitHub Environment **before** `deploy.yml` runs, because Vite inlines it at build
  time. Set the secrets and Vault entries before dispatching, or the release ships an inert
  toggle.
- **Setting a `prod` GitHub Environment variable is blocked for the Orchestrator by the
  permission classifier** (the `--env dev` equivalent is allowed). Ask the user to run it;
  hold the release rather than dispatching a partial one, and verify the value afterwards.

## Moderation status gate + notifications on by default (2026-09-06, tasks `moderation-self-approval.md`, `notifications-default-on.md`)

- **Read the migrations before trusting the bug report; there may be a second, worse defect.** The
  reported hole was self-approval on UPDATE. Reading `20260906013534` in filename order to write
  the fix revealed that the `responses` INSERT policy had no status check at all — strictly worse,
  because content could be *born* approved rather than flipped, and the frontend was already doing
  exactly that on the main mentor reply path.
- **RLS `WITH CHECK` expresses "only a privileged role may write this column value" whenever the
  unprivileged value is a constant.** No trigger, no column grant, no RPC. Column grants remain
  unavailable for anything an admin writes from the client, for the reason that keeps recurring
  here: admins are `authenticated` too, so a grant binds them as well.
- **Leave `USING` alone when tightening an UPDATE policy.** `USING` decides which rows a statement
  may reach; `WITH CHECK` validates the row written. Narrowing `USING` would have broken
  edit-and-resubmit, which must reach an already-approved row in order to rewrite it as pending.
- **Prove the positive case, not just the denial.** Four passing negative probes say nothing about
  whether the gate also blocks a legitimate flow. Edit-and-resubmit from an approved row was the
  criterion most likely to break, and the only one that would have broken silently.
- **Enumerate `pg_policies` on the live database, not just the migrations.** A permissive policy
  created by hand in the Supabase dashboard exists in no migration and ORs straight through any
  gate while every file in the repo still reads correctly. Standing check for any RLS task.
- **In a deploy window, reason about what the DEPLOYED code does, not what the diff does.** The
  compatibility note claimed the window produced "a failed reply and an error path"; the deployed
  handler was fire-and-forget, so the real outcome was a silently destroyed reply with the textarea
  cleared. Caught by reading the base commit rather than the diff.
- **Splitting one push into two removes a deploy-ordering window at no extra CI cost.** App first,
  then the migration: `deploy.yml` and `database-migration.yml` are path-filtered, so each push
  triggers exactly one pipeline and the total is the same two runs. Verified in both directions.
  **"It has been broken for months" is a legitimate argument about sequencing risk** — the marginal
  risk of a few more minutes on a months-old hole is far smaller than certain user-visible breakage.
- **A comment asserting a live defect outlives the defect.** The push migration's comments
  justified its guard by describing the self-approval hole as open. One migration later that was
  false, and applied migrations cannot be edited — the superseding note has to go in the new one.
  Budget for this whenever a compensating control is documented by its justification.
- **A test whose name asserts a behaviour it does not check is a false witness.** A test called
  "degrades to not-shown when reading storage throws" asserted only that nothing threw, and the
  real behaviour was the opposite of the name. It survived the engineer's review and mine. Same
  failure mode as the `handle_new_user` comment defect: a claim written beside the code gets read
  as evidence about the code. Assert the user-visible outcome.
- **A hook holding `useState` is per-component state, not shared state.** Two mounted consumers of
  the same hook never see each other's updates. Anything describing one browser- or device-level
  fact — a push subscription, a permission, a service-worker registration — needs a module-level
  store read through `useSyncExternalStore`. Reviewing a component in isolation cannot catch this;
  it took a test mounting both consumers together.
- **Verify a file named in your own handoff before making it a constraint.** The handoff named
  `ProtectedLayout.tsx` as the mount point "because it covers the awaiting-approval page". It does
  not, and `App.tsx` says so in a comment two lines above the route. Following the instruction
  would have failed an acceptance criterion silently — the prompt would simply never have appeared
  for pending members.
- **"On by default" for a browser permission means asking well, not asking automatically.** An
  in-app dialog whose button raises the real request, never a bare `Notification.requestPermission()`
  on load: browsers penalise that, and a denial is close to unrecoverable for a member who would
  have to change browser settings to undo it. Where the answer can never be stored (private window,
  blocked site data), suppress the prompt rather than re-asking every login.

## Expanding the pre-approved family-name list (2026-09-06, task `family-names-seed-expansion.md`)

- **Variant breadth on a list that gates access is the user's decision, not the agent's.** "Feel
  free to include some spelling variations" is an invitation that still needs bounding, because
  every spelling seeded approves a sign-up with no admin in the loop. One question, with the
  security consequence stated, turned an open-ended editorial task into a rule the migration, the
  review and every future addition can be checked against (here: internal v↔w, final -ia↔-iya).
- **A missing spelling is the safe failure mode; a wrong one is a permanent unattended hole.** An
  unseeded name falls through to `pending` and an admin decides. Seed narrowly, report the
  uncertain spellings back rather than guessing them.
- **Never apply a mechanical transformation to an initial letter.** The established v↔w swap is
  internal (`Modhwadia`/`Modhvadia`); applied to a first letter it would have invented `Wala`
  from `Vala` — a name nobody supplied, silently granted access. Constrain a mechanical rule's
  position, not just its characters.
- **Confirm a PostgREST `204` actually changed nothing.** A non-admin `DELETE` across a whole
  table returns 204 exactly as a successful delete does; RLS filtering it to zero rows is
  invisible in the status code. Re-count the rows — the count is the evidence, not the status.
- **`python` is not on PATH in this environment; use `node -e` with a stdin reader** for every
  ad-hoc JSON probe against Supabase.
- **Seed a canonical name as its own variant row too.** A family whose canonical label has no
  matching variant row would silently never auto-approve.
- **A data-only seed migration is genuinely tier 2 even on a security-critical table** — one
  `INSERT ... ON CONFLICT DO NOTHING`, no DDL, gate untouched — but it still earns a
  security-reviewer pass, whose value here was the two-way diff against the ratified list and
  confirming no DDL crept in.
Migrated on 2026-09-07 by the Project Manager: every open row above became its own issue,
#14 to #27 on https://github.com/nagzstar/ngm.app/issues?q=label%3Aclaude (has_role probe
#14, profiles.email #15, PROD lockout audit #16, guard-prod hook #17, test baseline #18,
Resend quota #19, security-model re-verify #20, SHA-pin actions #21, smoke check #22,
Dependabot #23, lint clean-up #24, react-query migration #25, build-once config #26,
Google Play TWA #27). Resolved rows were dropped. The backlog is the only list now.
