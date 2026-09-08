# 12 — Facts once, diff-scoped review, QA owns DEV, corrections in the same context (B)

**Finding.** F16/F17/F18 and the parallel-phase check: the Orchestrator does specialist work (40 %
of cache-read); the security reviewer reads whole files (229 KB avg, 400 KB in #12); all 14
correction rounds re-spawned a fresh engineer (≈ 80 K cc each); QA and security are already
parallel in 8/9 runs but #33 serialised them; Explore ran in only 3 runs, all of which delivered
with ≤ 1 correction round and no architect.

**Expected effect.** ≈ −3 M cache-read and −20 K output per issue from the Orchestrator; ≈ −100 K
cc per security review; ≈ −80 K cc per correction round; no wall-time loss.

## CLAUDE.md (rewrite in place; net −1 line)

```diff
@@ -50,3 +50,5 @@
-4. Do not glob or grep NGM broadly yourself (three or four named files is fine): `Explore` (`model: haiku`) locates code; `researcher-architect` understands or designs.
+4. Do not glob, grep or read NGM code yourself beyond three or four named files, and never write
+   a probe or a test. Before PLAN, one `Explore` (`model: haiku`) sweep returns the files, the
+   existing pattern and the migrations in play; forward that list in every handoff as facts.
@@ -73,6 +73,7 @@
 - **VERIFY.** `qa-engineer` for any non-trivial change. `security-reviewer` additionally for
   anything touching auth, roles, permissions, user data, migrations, edge functions, Terraform
-  or workflows. Both are independent and never fix what they review.
+  or workflows. Dispatch both in the same turn (they are independent); give each the base
+  commit and `git diff --name-only <base>..HEAD`. Both never fix what they review.
 - **REVIEW.** Apply the quality gate below yourself. A FAIL goes back to the implementing
-  engineer as numbered corrections — never to QA, and never fixed by you unless trivial.
+  engineer **in the same context** (`SendMessage` to the agent that did the work) as numbered
+  corrections — never to QA, never fixed by you unless trivial, never a fresh spawn while the
+  original context exists (a re-spawn re-reads everything).
@@ -80,3 +81,3 @@
-  `gh run view <id> --log-failed`, route the fix to the owner (deployment-engineer only for pipeline faults), and repeat. Validate the behaviour on
-  https://dev.nextgenmaher.com (via qa-engineer for anything non-trivial).
+  `gh run view <id> --log-failed`, route the fix to the owner (deployment-engineer only for pipeline faults), and repeat. DEV validation is
+  `qa-engineer`'s with `dev-probe.sh` (never yours): it returns the status matrix you record.
```

## `handoff.md` — correction block and facts block

```diff
 ## Returning work for correction
 
-Send the specific findings, not the whole QA report:
+Send the specific findings, not the whole QA report — to the SAME agent, with `SendMessage`
+(its context, design and files are already loaded; a fresh Agent call costs ≈ 80 K tokens of
+re-reading). Spawn fresh only if the agent is gone, or when escalating the model.
@@
 CORRECTION REQUIRED — <task>   (round N of 2)
@@ -22,6 +22,9 @@ RELEVANT FILES:
   - path — read-only, for pattern reference
+
+FACTS (from the Explore sweep; do not re-explore):
+  - pattern in use / files that implement it / migrations touching these tables
+  - base commit <sha>; changed files: `git diff --name-only <sha>..HEAD`
```
The "thin result → re-run on Opus" rule (CLAUDE.md, Tiers) becomes "thin result → `SendMessage`
the same agent with the gap named; escalate the model only on the second thin result".

## `security-reviewer.md` — add under "## Threat model" (3 lines)

```markdown
Scope first: read `git diff <base>..HEAD` for the files in the handoff before any whole file;
open a whole file only to trace a policy or function the diff touches. A review that reads more
than the diff plus the migrations it names is over budget — say so and stop.
```

## `qa-engineer.md` — add to its Method (2 lines)

```markdown
DEV validation is yours: `bash .claude/scripts/dev-probe.sh matrix <method> <path>` per
acceptance criterion with a role dimension; report the status matrix verbatim.
```
