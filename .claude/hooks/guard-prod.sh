#!/usr/bin/env bash
# PreToolUse hook (matcher: Bash). Deterministic enforcement of the NGM deployment boundary.
#
# Blocks, regardless of which agent or model issued the command:
#   - any GitHub workflow dispatch / API dispatch / rerun that targets prod — UNLESS the
#     Orchestrator (main session, never a subagent) holds a fresh prod approval recorded with
#     .claude/scripts/prod-approval.sh after the user answered "Shall I deploy this to prod?"
#     with an explicit yes
#   - terraform apply / destroy, wrangler deploys, supabase db push / reset / functions deploy
#     (these must go through the pipelines; the dev pipelines are triggered by pushing main)
#   - force pushes
#
# Exit 2 = block (message on stderr is shown to the model). Exit 0 = allow.
# Runs under Git Bash on Windows; uses node for JSON parsing because jq is not installed.
#
# Why a token file and not permissionDecision "ask": an "ask" from a hook is ignored in auto
# and bypass modes and by any matching allow rule (gh workflow run is allowed for dev), so it
# cannot gate anything. Exit 2 blocks in every mode. The token is written only after the
# user's yes, expires, is never valid inside a subagent, and logs every command it admits.

set -u
input="$(cat)"

parsed="$(printf '%s' "$input" | node -e '
  let d = ""; process.stdin.on("data", c => d += c);
  process.stdin.on("end", () => {
    try {
      const j = JSON.parse(d);
      const cmd = String((j.tool_input && j.tool_input.command) || "");
      const agent = String(j.agent_id || j.agent_type || "");
      process.stdout.write(JSON.stringify([cmd, agent]));
    } catch (e) { process.stdout.write("[\"\",\"\"]"); }
  });
' 2>/dev/null)"
cmd="$(printf '%s' "$parsed" | node -e 'let d="";process.stdin.on("data",c=>d+=c);process.stdin.on("end",()=>process.stdout.write(JSON.parse(d)[0]))')"
agent="$(printf '%s' "$parsed" | node -e 'let d="";process.stdin.on("data",c=>d+=c);process.stdin.on("end",()=>process.stdout.write(JSON.parse(d)[1]))')"

[ -z "$cmd" ] && exit 0

approval_file="${PROD_APPROVAL_FILE:-${CLAUDE_PROJECT_DIR:-$PWD}/.agent-context/.prod-approval}"
approval_ttl="${PROD_APPROVAL_TTL:-3600}"   # seconds a recorded approval stays valid

block() {
  echo "BLOCKED by guard-prod hook: $1" >&2
  echo "Command: $cmd" >&2
  echo "PROD is the user's decision. DEV changes ship by pushing main; the Orchestrator does that after review." >&2
  exit 2
}

# A prod release is allowed only from the main session, with a fresh recorded approval.
# The approval file is written by .claude/scripts/prod-approval.sh grant, only after the
# user has answered "Shall I deploy this to prod?" with an explicit yes.
prod_release() { # reason
  if [ -n "$agent" ]; then
    block "$1 — specialists never release to prod; only the Orchestrator does, after the user's yes"
  fi
  if [ ! -f "$approval_file" ]; then
    block "$1 — no prod approval recorded. Report READY FOR PROD, ask the user \"Shall I deploy this to prod?\", and on an explicit yes run: bash .claude/scripts/prod-approval.sh grant <sha> \"<the user's words>\""
  fi
  granted="$(grep -E '^granted_epoch=' "$approval_file" 2>/dev/null | head -1 | cut -d= -f2)"
  now="$(date +%s)"
  case "$granted" in
    ''|*[!0-9]*) rm -f "$approval_file"; block "$1 — prod approval file is malformed; removed. Ask the user again." ;;
  esac
  if [ $((now - granted)) -gt "$approval_ttl" ]; then
    rm -f "$approval_file"
    block "$1 — the recorded prod approval is older than $((approval_ttl / 60)) minutes and has expired. Ask the user again."
  fi
  printf 'admitted_epoch=%s command=%s\n' "$now" "$cmd" >> "$approval_file"
  echo "guard-prod: prod release admitted under the approval recorded in $approval_file" >&2
  exit 0
}

lc="$(printf '%s' "$cmd" | tr '[:upper:]' '[:lower:]')"

# 1. Workflow dispatch or API dispatch naming prod.
if printf '%s' "$lc" | grep -Eq '(gh[[:space:]]+workflow[[:space:]]+run|/dispatches|actions/workflows)'; then
  if printf '%s' "$lc" | grep -Eq '(^|[^a-z])prod(uction)?([^a-z]|$)'; then
    prod_release "workflow dispatch targeting prod"
  fi
fi

# 2. Rerunning a run whose jobs targeted prod. Looks the run up; fails closed if it cannot.
if printf '%s' "$lc" | grep -Eq 'gh[[:space:]]+run[[:space:]]+rerun'; then
  run_id="$(printf '%s' "$cmd" | grep -Eo 'rerun[[:space:]]+[0-9]+' | grep -Eo '[0-9]+' | head -1)"
  if [ -z "$run_id" ]; then
    block "gh run rerun without a numeric run id cannot be checked for prod"
  fi
  jobs="$(gh run view "$run_id" -R nagzstar/ngm.app --json jobs --jq '.jobs[].name' 2>/dev/null)"
  if [ -z "$jobs" ]; then
    block "could not verify that run $run_id is not a prod run"
  fi
  if printf '%s' "$jobs" | tr '[:upper:]' '[:lower:]' | grep -Eq 'prod'; then
    prod_release "rerun of run $run_id, which contains a prod job"
  fi
fi

# 3. Direct deploy / destructive infrastructure commands — pipelines only, in every case.
if printf '%s' "$lc" | grep -Eq 'terraform[[:space:]]+(apply|destroy)'; then
  block "terraform apply/destroy is pipeline-only (terraform-apply.yml, dispatched per environment)"
fi
if printf '%s' "$lc" | grep -Eq '(^|[[:space:]])(npx[[:space:]]+)?wrangler[[:space:]]+(pages[[:space:]]+)?deploy'; then
  block "wrangler deploy is pipeline-only (deploy.yml)"
fi
if printf '%s' "$lc" | grep -Eq 'supabase[[:space:]]+(db[[:space:]]+(push|reset)|functions[[:space:]]+deploy)'; then
  block "supabase db push/reset and functions deploy are pipeline-only (database-migration.yml)"
fi

# 4. Force pushes.
if printf '%s' "$lc" | grep -Eq 'git[[:space:]]+push[[:space:]].*(--force|-f([[:space:]]|$)|--force-with-lease)'; then
  block "force push"
fi

exit 0
