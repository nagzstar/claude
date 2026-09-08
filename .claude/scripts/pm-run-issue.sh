#!/usr/bin/env bash
# Start ONE fresh, headless Claude Code session inside NGM_ROOT to deliver ONE backlog issue —
# or ONE batch: an umbrella issue labelled `batch` whose "## Members" section lists the issues
# one session delivers together (one push, one DEV validation, one prod release) — then return
# its final report. This is how the Project Manager mode (skill ngm-project-manager) hands work
# to the Orchestrator: a new process per item, so the PM conversation stays small and each
# item gets a full, clean context. Batches exist because per-session overhead was making the
# backlog grow faster than delivery (.agent-context/decisions.md).
#
#   bash .claude/scripts/pm-run-issue.sh <issue-or-batch-number> [options]
#   bash .claude/scripts/pm-run-issue.sh --queue [options]     # every ready item in the delivery order, in turn
#     --model <id>              session model (default: claude-opus-5 for a single ticket, claude-fable-5-1
#                               for a batch umbrella — see .agent-context/decisions.md)
#     --permission-mode <mode>  default: $PM_PERMISSION_MODE or "auto"
#     --effort <level>          low|medium|high|xhigh|max (default: the CLI default)
#     --force                   start even if a task file is IN PROGRESS / IN REVIEW / BLOCKED
#     --dry-run                 run the pre-flight checks and print the command; do not launch
#     --print-prompt            print the prompt the session would get and exit (no gh, no git)
#
# Refuses a closed issue and any issue labelled `blocked` (no override: the PM lifts the block
# by setting the status back to `ready` on the user's say-so). In a batch, a member that is
# closed or `blocked` is left out with a warning and the rest still run; a batch with no
# eligible member is refused. `--print-prompt` never calls gh, so it shows the single-issue
# prompt; use `--dry-run` to see the batch prompt.
#
# --queue: `pm-issue.sh next` lists the open, `ready` items of the pinned "Delivery order" in
# sequence; each is run as above, one session at a time. The queue stops on the first run that
# ends without a result, hits the subscription limit (the log says so; wait for the reset it
# names, then re-run --queue) or leaves its issue `in-progress`; a `needs-decision` or
# `blocked` outcome is skipped and listed at the end. It can never reach prod.
#
# The session takes as long as the feature takes (typically 20–90 minutes). Run it in the
# background and tail the .log file it names. It can never reach prod: the guard-prod hook
# admits a prod dispatch only under a recorded approval, which is granted only in a live
# conversation after the user's explicit yes.
#
# Files (gitignored in ngm.app): $NGM_ROOT/.agent-context/pm-runs/issue-<n>-<ts>.{prompt.md,log,json}
# Lock: $NGM_ROOT/.agent-context/.pm-run.lock — one feature session at a time (one checkout).

set -u
NGM_ROOT="${NGM_ROOT:-C:/Users/nagaj/git/ngm.app}"
REPO="${NGM_REPO:-nagzstar/ngm.app}"
model="claude-opus-5"; model_set=0
mode="${PM_PERMISSION_MODE:-auto}"
effort=""
force=0; dry=0; print_prompt=0; queue=0
issue=""
passthrough=()

die() { echo "pm-run-issue: $*" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --model) model="${2:-}"; model_set=1; passthrough+=("$1" "$2"); shift 2 ;;
    --permission-mode) mode="${2:-}"; passthrough+=("$1" "$2"); shift 2 ;;
    --effort) effort="${2:-}"; passthrough+=("$1" "$2"); shift 2 ;;
    --force) force=1; passthrough+=("$1"); shift ;;
    --dry-run) dry=1; passthrough+=("$1"); shift ;;
    --print-prompt) print_prompt=1; shift ;;
    --queue) queue=1; shift ;;
    -h|--help) sed -n '2,31p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) [ -z "$issue" ] && printf '%s' "$1" | grep -Eq '^[0-9]+$' && { issue="$1"; shift; continue; }
       die "unexpected argument: $1" ;;
  esac
done

# ---- --queue: run the ready items of the delivery order, one session after another ----------
if [ "$queue" -eq 1 ]; then
  [ -z "$issue" ] || die "--queue takes no issue number"
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  items="$(bash "$here/pm-issue.sh" next 2>/dev/null | awk '{print $1}' | tr -d '#')"
  [ -n "$items" ] || die "the delivery order has no open, ready item"
  echo "pm-run-issue: queue → $(printf '#%s ' $items)"
  skipped=""; run_rc=0
  for n in $items; do
    echo; echo "================ queue: #$n ================"
    bash "$0" "$n" "${passthrough[@]}"; run_rc=$?
    labels="$(gh issue view "$n" -R "$REPO" --json labels --jq '[.labels[].name]|join(",")' 2>/dev/null || echo "")"
    latest_log="$(ls -1t "$NGM_ROOT"/.agent-context/pm-runs/issue-"$n"-*.log 2>/dev/null | head -1)"
    if [ -n "$latest_log" ] && grep -qi "session limit" "$latest_log"; then
      echo "!!! queue stopped: #$n hit the subscription limit — $(grep -m1 -oi 'session limit[^|\"]*' "$latest_log"). Re-run --queue after the reset."
      exit 3
    fi
    case ",${labels}," in
      *,ready-for-prod,*) echo "queue: #$n ready-for-prod" ;;
      *,needs-decision,*|*,blocked,*) skipped="${skipped:+$skipped }#$n"; echo "queue: #$n set aside ($labels)" ;;
      *) echo "!!! queue stopped: #$n ended '${labels:-unknown}' (rc=$run_rc) — check the disk and git log before continuing"; exit 1 ;;
    esac
  done
  echo; echo "queue finished. ${skipped:+needs the user: $skipped — }nothing was released: prod is the user's decision."
  exit 0
fi

[ -n "$issue" ] || die "an issue number is required (see --help)"

# ---- the prompt ---------------------------------------------------------------------------
# Reference, never restate: the session reads the issue itself, so nothing here goes stale.
session_id="$(node -e 'process.stdout.write(require("crypto").randomUUID())' 2>/dev/null)"
[ -n "$session_id" ] || die "node is required to generate a session id"

# Filled in by the pre-flight when #issue is a batch umbrella: the eligible member numbers,
# space-separated, and the block of prompt text that turns one-issue rules into batch rules.
members=""
batch_block=""

build_batch_block() {
  local list="" m
  for m in $members; do list="${list:+$list, }#$m"; done
  cat <<EOF

BATCH — READ THIS FIRST. Issue #${issue} is an umbrella labelled \`batch\`; its members are
${list}, in that order. This session delivers EVERY member. The umbrella's Decisions bind every
member; a member's own Decisions and comments stand unless the umbrella overrides them. Where
the rules below say "the issue", read them as follows:
- Before PLAN, \`pm-issue.sh show\` the umbrella AND every member, and read all of it.
- Set the umbrella to \`in-progress\` (with the "🚧 Started" comment) and set each member to
  \`in-progress\` as you start it.
- ONE task file for the batch: \`.agent-context/tasks/issue-${issue}-batch-<slug>.md\` with
  \`Issue: #${issue}\` and a section per member (its own acceptance criteria and evidence).
- Members whose files are disjoint may be built in PARALLEL by separate instances of the same
  specialist (two frontend-engineers, two backend-engineers) under a written contract naming
  each instance's files; members that touch the same function, table, migration order or
  page run in sequence. CLAUDE.md's parallel rule applies per instance, not per agent type.
- One commit per member on main, referencing that member and #${issue}. Do NOT push after each:
  push ONCE when every member is finished or set aside, so the pipeline runs once; then
  \`check-dev\` once and validate every member on DEV in one pass. QA and security review each
  run ONCE over the whole batch, not per member.
- A member you cannot finish gets its own "❓ NEEDS DECISION" / "⛔ BLOCKED" comment and
  status, and is set aside; carry on with the rest. Never revert a finished member because a
  later one failed. A member whose work turns out to be already done or unnecessary gets a
  comment saying so and \`ready-for-prod\`.
- Finishing: every finished member → \`ready-for-prod\` plus a short comment (commit sha, what
  was validated). Then the umbrella gets the full "✅ READY FOR PROD" report listing each
  member's outcome (READY / NEEDS-DECISION / BLOCKED). The umbrella is READY FOR PROD when at
  least one member is; it is NEEDS-DECISION or BLOCKED only when no member reached
  ready-for-prod. Never close any issue — the umbrella or a member.
- Problems spotted: file an issue only for a genuine defect or risk; fold trivial follow-ups
  into the member they belong to instead of opening a ticket for each.
EOF
}

build_prompt() {
  cat <<EOF
You are the NGM Orchestrator (CLAUDE.md) working from the GitHub backlog. This headless
session exists for exactly one issue and ends when that issue is at READY FOR PROD, BLOCKED
or NEEDS-DECISION. Never start another issue in this session. Nobody is reading this
conversation live: every question for the user goes into an issue comment, not the chat.
${batch_block}

YOUR TURN ENDING IS THE SESSION ENDING. This is a single-shot \`claude -p\` run. Nothing
re-invokes you: the moment you stop producing tool calls, the process exits and every piece
of unfinished work is lost. Therefore:
- NEVER pass \`run_in_background: true\` to the Agent tool. Every specialist you delegate to
  runs in the FOREGROUND, and you wait for its result inside your own turn.
- NEVER launch background Bash (\`run_in_background\`, \`nohup\`, trailing \`&\`) for anything
  whose output you need.
- NEVER end a turn "waiting" for something — a design pass, a review, a pipeline, a rate-limit
  reset. There is no later. Poll it in the foreground instead (\`gh run watch\` for pipelines).
- Keep working, in one continuous turn, until the issue reaches READY FOR PROD, BLOCKED or
  NEEDS-DECISION and you have set the status label and posted the comment.
If you genuinely cannot finish — you are out of context, or blocked on something only the user
can resolve — do NOT just stop. Set the status to BLOCKED or NEEDS-DECISION, post the comment
with what is done so far and the resume command, and say so in your final message. A session
that stops with the issue still labelled \`in-progress\` has failed, and the launcher reports it
as a failure.

Issue: #${issue} in ${REPO} — https://github.com/${REPO}/issues/${issue}
Session id: ${session_id}   (the user can resume you with: claude --resume ${session_id})

Before PLAN
1. Run \`bash .claude/scripts/pm-issue.sh show ${issue}\` and read every word — body AND
   comments. Earlier sessions may have left a task file, a design, decisions, a READY FOR
   PROD report or open questions there. Continue from that state; never redo delivered work.
   If the latest comment already says READY FOR PROD and nothing relevant changed since,
   confirm that on DEV, say so in your final report and stop: the prod release is the user's
   decision and is taken in the Project Manager conversation, never here.
2. Do the normal boot and resume check from CLAUDE.md.
3. \`bash .claude/scripts/pm-issue.sh status ${issue} in-progress\`, then post a comment
   (\`pm-issue.sh comment ${issue} <file>\`) headed "🚧 Started" with the session id, the
   base commit and the task file path.

Delivery
- Treat the issue's Idea, Notes, Acceptance Criteria and Decisions as the outcome and the
  acceptance criteria. Run the full lifecycle from CLAUDE.md: task file
  \`.agent-context/tasks/issue-${issue}-<slug>.md\` with a line \`Issue: #${issue}\`, the
  usual specialists and tiers, check-app, one commit on main whose message references
  #${issue}, push, check-dev, and behaviour validated on https://dev.nextgenmaher.com.
- An "Open questions" section in the issue is not a licence to guess: if a question changes
  product behaviour, cost or security, stop at NEEDS-DECISION and ask it in the comment.

Finishing — before your final message
- READY FOR PROD → \`pm-issue.sh status ${issue} ready-for-prod\` and ONE comment headed
  "✅ READY FOR PROD" in the CLAUDE.md report format (Completed … Prod), ≤ 60 lines: commit
  sha(s), DEV pipeline run ids, what was validated on DEV and how (the per-role status
  matrix), release notes, risks, and the resume command above. That comment IS the report:
  do not repeat it in the chat, the task file or lessons.md (≤ 5 lesson lines, ≤ 2 durable).
- NEEDS-DECISION → status \`needs-decision\`; BLOCKED → status \`blocked\`. The comment,
  headed "❓ NEEDS DECISION" or "⛔ BLOCKED", lists the numbered questions or the blocker,
  what is already done (commit sha if pushed) and the resume command.
- Every bug, idea or problem spotted that is out of scope becomes its own issue:
  \`pm-issue.sh new <type> "<title>" <body-file> ${issue}\` (labelled \`claude\`). Do not
  append problems to lessons.md; lessons themselves still go there.
- Commit the task file. Never close the issue. Never dispatch environment=prod, never rerun
  a prod run, never weaken a production control. Do not wait for an answer to "Shall I
  deploy this to prod?" — put READY FOR PROD in the comment and end.
- Your final message is two lines: "Report: <the comment's URL>" and the Prod line.
EOF
}

if [ "$print_prompt" -eq 1 ]; then build_prompt; exit 0; fi

# ---- pre-flight -----------------------------------------------------------------------------
claude_bin="${CLAUDE_CODE_EXECPATH:-}"
[ -n "$claude_bin" ] && [ -x "$claude_bin" ] || claude_bin="$(command -v claude 2>/dev/null || true)"
if [ -z "$claude_bin" ]; then
  claude_bin="$(ls -1d "$HOME"/.vscode/extensions/anthropic.claude-code-*/resources/native-binary/claude.exe 2>/dev/null | sort -V | tail -1)"
fi
[ -n "$claude_bin" ] && [ -x "$claude_bin" ] || die "claude CLI not found (set CLAUDE_CODE_EXECPATH or put claude on PATH)"

[ -d "$NGM_ROOT/.git" ] || die "NGM_ROOT is not a git checkout: $NGM_ROOT"
# The allow list in .claude/settings.json is ignored unless the workspace has been trusted once
# interactively; every headless call is then adjudicated by the permission classifier (16/16 runs
# on 2026-09-07 logged "Ignoring 32 permissions.allow entries"). Refuse to burn a session on that.
trusted="$(node -e '
  const fs=require("fs"),p=(process.env.USERPROFILE||process.env.HOME)+"/.claude.json";
  try{const j=JSON.parse(fs.readFileSync(p,"utf8"));const P=j.projects||{};const want=process.argv[1].replace(/\\/g,"/").toLowerCase();
    for(const k of Object.keys(P)) if(k.replace(/\\/g,"/").toLowerCase()===want && P[k].hasTrustDialogAccepted){console.log("yes");process.exit(0)}
  }catch(e){} console.log("no")' "$NGM_ROOT" 2>/dev/null)"
if [ "$trusted" != "yes" ] && [ "${PM_ALLOW_UNTRUSTED:-0}" != "1" ]; then
  die "$NGM_ROOT has not been trusted, so the allow list would be ignored and every tool call classified.
  Once: open 'claude' interactively in $NGM_ROOT, accept the trust dialog, then re-run.
  (PM_ALLOW_UNTRUSTED=1 overrides — not recommended.)"
fi
gh auth status >/dev/null 2>&1 || die "gh is not authenticated"
gh issue view "$issue" -R "$REPO" --json state --jq .state | grep -qx OPEN || die "issue #$issue is not an open issue in $REPO"
# A blocked ticket is never started, whatever its place in the delivery order
# (.agent-context/decisions.md). The PM lifts the block by setting the status back to `ready`.
if gh issue view "$issue" -R "$REPO" --json labels --jq '.labels[].name' | grep -qx blocked; then
  die "issue #$issue is labelled 'blocked' — skip to the next ready item in the delivery order;
  only the user can lift the block (pm-issue.sh status $issue ready after their say-so)"
fi

# A batch umbrella: collect its members from "## Members" (first mention of each #n, in order),
# drop closed or blocked ones with a warning, and refuse a batch with nobody left to deliver.
if gh issue view "$issue" -R "$REPO" --json labels --jq '.labels[].name' | grep -qx batch; then
  # Only the #n that LEADS a list item counts ("1. #58 …", "- #58 …"); a #n mentioned later in
  # the same line ("moved because the user is delivering #68 …") is prose, not a member.
  listed="$(gh issue view "$issue" -R "$REPO" --json body --jq .body \
    | sed -n '/^## Members/,/^## /p' | tr -d '\r' \
    | grep -oE '^[[:space:]]*([0-9]+\.|-|\*)[[:space:]]*#[0-9]+' | grep -oE '[0-9]+$' | awk '!seen[$0]++')"
  [ -n "$listed" ] || die "batch #$issue has no '## Members' section listing #n issues"
  for m in $listed; do
    [ "$m" = "$issue" ] && continue
    mlabels="$(gh issue view "$m" -R "$REPO" --json state,labels --jq '[.state] + [.labels[].name] | join(",")' 2>/dev/null || echo MISSING)"
    case ",${mlabels}," in
      *,OPEN,*) ;;
      *) echo "pm-run-issue: batch #$issue: member #$m is not open — left out" >&2; continue ;;
    esac
    case ",${mlabels}," in
      *,blocked,*) echo "pm-run-issue: batch #$issue: member #$m is labelled 'blocked' — left out (only the user lifts a block)" >&2; continue ;;
    esac
    members="${members:+$members }$m"
  done
  [ -n "$members" ] || die "batch #$issue has no open, unblocked member to deliver"
  batch_block="$(build_batch_block)"
  [ "$model_set" -eq 1 ] || model="claude-fable-5-1"
  echo "pm-run-issue: batch #$issue → members: $(printf '#%s ' $members)"
fi

lock="$NGM_ROOT/.agent-context/.pm-run.lock"
if [ -f "$lock" ]; then
  echo "pm-run-issue: a feature session appears to be running already:" >&2; cat "$lock" >&2
  die "one feature at a time — wait for it, or remove the lock if that process is gone"
fi

dirty="$(git -C "$NGM_ROOT" status --short)"
[ -z "$dirty" ] || die "NGM working tree is not clean — an interrupted session left work on disk; resolve it first:
$dirty"
git -C "$NGM_ROOT" fetch -q origin main || die "git fetch failed"
git -C "$NGM_ROOT" pull -q --ff-only origin main || die "cannot fast-forward NGM main; resolve it first"

open_tasks="$(grep -lE '^Status: (IN PROGRESS|IN REVIEW|BLOCKED)' "$NGM_ROOT"/.agent-context/tasks/*.md 2>/dev/null | grep -v -E 'TEMPLATE|EXAMPLE' || true)"
if [ -n "$open_tasks" ] && [ "$force" -eq 0 ]; then
  die "task files still open (the new session would inherit them); close or --force:
$open_tasks"
fi

ts="$(date -u +%Y%m%dT%H%M%SZ)"
run_dir="$NGM_ROOT/.agent-context/pm-runs"; mkdir -p "$run_dir"
base="$run_dir/issue-$issue-$ts"
# A previous abnormal end may have left a draft stash (see the outcome section): tell the
# session so it restores it instead of redoing the work.
draft="$(git -C "$NGM_ROOT" stash list 2>/dev/null | grep -m1 "pm-run-issue draft #$issue " || true)"
[ -n "$draft" ] && batch_block="${batch_block}

A PREVIOUS SESSION LEFT A DRAFT: \`git stash list\` shows \"${draft}\". Read its diff first
(\`git stash show -p <ref>\`), decide what to keep, \`git stash pop\` it before doing new work,
and never redo what it contains."
build_prompt > "$base.prompt.md"

cmd=("$claude_bin" -p --session-id "$session_id" --name "issue-$issue" --model "$model" \
     --permission-mode "$mode" --output-format stream-json --verbose)
[ -n "$effort" ] && cmd+=(--effort "$effort")

echo "pm-run-issue: issue #$issue  model=$model  mode=$mode  session=$session_id"
echo "  prompt: $base.prompt.md"
echo "  log:    $base.log     (tail -f it for progress)"
echo "  result: $base.json"
if [ "$dry" -eq 1 ]; then
  echo "  dry-run: would run (from $NGM_ROOT): ${cmd[*]} \"\$(cat $base.prompt.md)\""; exit 0
fi

# ---- launch -----------------------------------------------------------------------------------
printf 'issue=%s\npid=%s\nsession=%s\nstarted=%s\nlog=%s\n' "$issue" "$$" "$session_id" "$ts" "$base.log" > "$lock"
trap 'rm -f "$lock"' EXIT

cd "$NGM_ROOT" || die "cannot cd to $NGM_ROOT"
export NGM_HEADLESS=1   # guard-agent.sh refuses run_in_background under this marker
"${cmd[@]}" "$(cat "$base.prompt.md")" 2>>"$base.log" | node -e '
  // Turn the stream into a readable progress log and capture the final result object.
  const fs = require("fs");
  const [logPath, jsonPath] = process.argv.slice(1);
  const log = fs.createWriteStream(logPath, { flags: "a" });
  let buf = "", result = null;
  const line = s => log.write(new Date().toISOString().slice(11, 19) + " " + s + "\n");
  line("TZ UTC (git and file times are local)");
  process.stdin.on("data", c => {
    buf += c;
    let i;
    while ((i = buf.indexOf("\n")) >= 0) {
      const raw = buf.slice(0, i).trim(); buf = buf.slice(i + 1);
      if (!raw) continue;
      let j; try { j = JSON.parse(raw); } catch { line("RAW " + raw.slice(0, 300)); continue; }
      if (j.type === "assistant") {
        for (const b of (j.message && j.message.content) || []) {
          if (b.type === "text" && b.text.trim()) line("TEXT " + b.text.replace(/\s+/g, " ").slice(0, 400));
          if (b.type === "tool_use") line("TOOL " + b.name + " " + JSON.stringify(b.input).slice(0, 200));
        }
      } else if (j.type === "result") {
        result = j;
        fs.writeFileSync(jsonPath, JSON.stringify(j, null, 2));
        line("RESULT " + j.subtype + " turns=" + j.num_turns + " cost_usd=" + j.total_cost_usd);
      }
    }
  });
  process.stdin.on("end", () => {
    log.end();
    if (!result) { console.log("pm-run-issue: the session ended without a result object (see the log)"); process.exit(1); }
    const denials = (result.permission_denials || []).length;
    console.log("=== issue result: " + result.subtype + " | turns " + result.num_turns + " | cost_usd " + result.total_cost_usd + " | permission denials " + denials);
    if (denials) console.log("    denied: " + (result.permission_denials || []).map(d => d.tool_name + " " + JSON.stringify(d.tool_input).slice(0, 120)).join("\n            "));
    console.log("=== final report from the session:\n");
    console.log(result.result || "(empty)");
    process.exit(result.subtype === "success" ? 0 : 1);
  });
' "$base.log" "$base.json"
rc=$?

# ---- outcome ----------------------------------------------------------------------------------
ended="$(date -u +%Y%m%dT%H%M%SZ)"
limit_line="$(grep -m1 -oE "hit your session limit[^\"|]*" "$base.log" 2>/dev/null || true)"
final_labels="$(gh issue view "$issue" -R "$REPO" --json labels --jq '[.labels[].name]|join(",")' 2>/dev/null || echo "")"
outcome="incomplete"
case ",${final_labels}," in
  *,ready-for-prod,*) outcome="ready-for-prod" ;; *,needs-decision,*) outcome="needs-decision" ;; *,blocked,*) outcome="blocked" ;;
esac
[ -n "$limit_line" ] && outcome="session-limit"
[ -f "$base.json" ] || outcome="${outcome}/no-result"

# Preserve whatever the session left in the tree: a diff file (readable) plus a stash
# (restorable), so main is clean for the next run and nothing is rescued by hand again
# (#12, #55 and #70 were, on 2026-09-07).
if [ -n "$(git -C "$NGM_ROOT" status --short)" ]; then
  git -C "$NGM_ROOT" add -A -N . 2>/dev/null
  git -C "$NGM_ROOT" diff > "$base.partial.diff"
  if git -C "$NGM_ROOT" stash push -u -q -m "pm-run-issue draft #$issue $ts ($outcome)"; then
    echo "pm-run-issue: uncommitted work preserved in $base.partial.diff and stash 'pm-run-issue draft #$issue $ts' — restore with: git -C \"$NGM_ROOT\" stash pop"
  fi
fi

# One line per run for the retrospective (retro/metrics.js reads it; the PM pastes the row into #31).
node -e '
  const fs=require("fs");const [csv,json,issue,ts,ended,model,outcome,log]=process.argv.slice(1);
  let j={};try{j=JSON.parse(fs.readFileSync(json,"utf8"))}catch{}
  const L=fs.existsSync(log)?fs.readFileSync(log,"utf8").split("\n").filter(l=>/^\d\d:\d\d:\d\d /.test(l)):[];
  const s=t=>{const [h,m,x]=t.split(":").map(Number);return h*3600+m*60+x};
  const wall=L.length?((s(L[L.length-1].slice(0,8))-s(L[0].slice(0,8))+86400)%86400):"";
  const mu=j.modelUsage||{};const sum=k=>Object.values(mu).reduce((a,u)=>a+(u[k]||0),0);
  const row=[issue,ts,ended,model,outcome,j.num_turns??"",wall,j.total_cost_usd??"",sum("outputTokens"),sum("cacheCreationInputTokens"),sum("cacheReadInputTokens"),(j.permission_denials||[]).length,L.filter(l=>/ TOOL Agent /.test(l)).length,Object.keys(mu).join("+")].join(",");
  if(!fs.existsSync(csv))fs.writeFileSync(csv,"issue,ts,ended,model,outcome,turns,wall_s,cost_usd,out_tokens,cache_create,cache_read,denials,agent_calls,models\n");
  fs.appendFileSync(csv,row+"\n");' "$run_dir/metrics.csv" "$base.json" "$issue" "$ts" "$ended" "$model" "$outcome" "$base.log" 2>/dev/null || true

if [ -n "$limit_line" ]; then
  echo
  echo "!!! pm-run-issue: the session hit the subscription limit: $limit_line"
  echo "    Wait for the reset, then: cd \"$NGM_ROOT\" && claude -p --resume $session_id \"Continue issue #$issue from where you stopped; read the task file and git status first.\""
  exit 3
fi

# A zero exit means the process ended cleanly, NOT that the issue was delivered: a session that
# ends its turn while "waiting" for a background agent exits 0 having done nothing. The issue's
# status label is the real outcome — the session must move it off in-progress before finishing.
case ",${final_labels}," in
  *,ready-for-prod,*|*,needs-decision,*|*,blocked,*) ;;
  *)
    echo
    echo "!!! pm-run-issue: issue #$issue is still labelled '${final_labels:-unknown}' — it did NOT reach"
    echo "    ready-for-prod, needs-decision or blocked. The session stopped early and the work is"
    echo "    almost certainly incomplete, whatever its final message said. Check the disk and git log"
    echo "    before believing any claim of delivery:"
    echo "      git -C \"$NGM_ROOT\" status --short && git -C \"$NGM_ROOT\" log --oneline -3"
    echo "    Re-run this issue, or resume the session, rather than moving on."
    rc=1
    ;;
esac

echo
echo "resume this session interactively (from $NGM_ROOT): claude --resume $session_id"
exit $rc
