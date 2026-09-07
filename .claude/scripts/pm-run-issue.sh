#!/usr/bin/env bash
# Start ONE fresh, headless Claude Code session inside NGM_ROOT to deliver ONE backlog issue,
# then return its final report. This is how the Project Manager mode (skill
# ngm-project-manager) hands a feature to the Orchestrator: a new process per feature, so the
# PM conversation stays small and each feature gets a full, clean context.
#
#   bash .claude/scripts/pm-run-issue.sh <issue-number> [options]
#     --model <id>              session model (default: claude-opus-5; use claude-fable-5-1 for tier-4 work)
#     --permission-mode <mode>  default: $PM_PERMISSION_MODE or "auto"
#     --effort <level>          low|medium|high|xhigh|max (default: the CLI default)
#     --force                   start even if a task file is IN PROGRESS / IN REVIEW / BLOCKED
#     --dry-run                 run the pre-flight checks and print the command; do not launch
#     --print-prompt            print the prompt the session would get and exit (no gh, no git)
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
model="claude-opus-5"
mode="${PM_PERMISSION_MODE:-auto}"
effort=""
force=0; dry=0; print_prompt=0
issue=""

die() { echo "pm-run-issue: $*" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --model) model="${2:-}"; shift 2 ;;
    --permission-mode) mode="${2:-}"; shift 2 ;;
    --effort) effort="${2:-}"; shift 2 ;;
    --force) force=1; shift ;;
    --dry-run) dry=1; shift ;;
    --print-prompt) print_prompt=1; shift ;;
    -h|--help) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) [ -z "$issue" ] && printf '%s' "$1" | grep -Eq '^[0-9]+$' && { issue="$1"; shift; continue; }
       die "unexpected argument: $1" ;;
  esac
done
[ -n "$issue" ] || die "an issue number is required (see --help)"

# ---- the prompt ---------------------------------------------------------------------------
# Reference, never restate: the session reads the issue itself, so nothing here goes stale.
session_id="$(node -e 'process.stdout.write(require("crypto").randomUUID())' 2>/dev/null)"
[ -n "$session_id" ] || die "node is required to generate a session id"

build_prompt() {
  cat <<EOF
You are the NGM Orchestrator (CLAUDE.md) working from the GitHub backlog. This headless
session exists for exactly one issue and ends when that issue is at READY FOR PROD, BLOCKED
or NEEDS-DECISION. Never start another issue in this session. Nobody is reading this
conversation live: every question for the user goes into an issue comment, not the chat.

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
- READY FOR PROD → \`pm-issue.sh status ${issue} ready-for-prod\` and a comment headed
  "✅ READY FOR PROD" containing: commit sha(s), DEV pipeline run ids, what was validated on
  DEV and how, release notes, risks, and the resume command above.
- NEEDS-DECISION → status \`needs-decision\`; BLOCKED → status \`blocked\`. The comment,
  headed "❓ NEEDS DECISION" or "⛔ BLOCKED", lists the numbered questions or the blocker,
  what is already done (commit sha if pushed) and the resume command.
- Every bug, idea or problem spotted that is out of scope becomes its own issue:
  \`pm-issue.sh new <type> "<title>" <body-file> ${issue}\` (labelled \`claude\`). Do not
  append problems to lessons.md; lessons themselves still go there.
- Commit the task file. Never close the issue. Never dispatch environment=prod, never rerun
  a prod run, never weaken a production control. Do not wait for an answer to "Shall I
  deploy this to prod?" — put READY FOR PROD in the comment and end.
- Your final message is the standard report from CLAUDE.md, ending with the Prod line.
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
gh auth status >/dev/null 2>&1 || die "gh is not authenticated"
gh issue view "$issue" -R "$REPO" --json state --jq .state | grep -qx OPEN || die "issue #$issue is not an open issue in $REPO"

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
"${cmd[@]}" "$(cat "$base.prompt.md")" 2>>"$base.log" | node -e '
  // Turn the stream into a readable progress log and capture the final result object.
  const fs = require("fs");
  const [logPath, jsonPath] = process.argv.slice(1);
  const log = fs.createWriteStream(logPath, { flags: "a" });
  let buf = "", result = null;
  const line = s => log.write(new Date().toISOString().slice(11, 19) + " " + s + "\n");
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
echo
echo "resume this session interactively (from $NGM_ROOT): claude --resume $session_id"
exit $rc
