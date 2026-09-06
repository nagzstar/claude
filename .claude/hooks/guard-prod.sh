#!/usr/bin/env bash
# PreToolUse hook (matcher: Bash). Deterministic enforcement of the NGM deployment boundary.
#
# Blocks, regardless of which agent or model issued the command:
#   - any GitHub workflow dispatch / API dispatch / rerun that targets prod
#   - terraform apply / destroy, wrangler deploys, supabase db push / reset / functions deploy
#     (these must go through the pipelines; the dev pipelines are triggered by pushing main)
#   - force pushes
#
# Exit 2 = block (message on stderr is shown to the model). Exit 0 = allow.
# Runs under Git Bash on Windows; uses node for JSON parsing because jq is not installed.

set -u
input="$(cat)"

cmd="$(printf '%s' "$input" | node -e '
  let d = ""; process.stdin.on("data", c => d += c);
  process.stdin.on("end", () => {
    try { const j = JSON.parse(d); process.stdout.write(String((j.tool_input && j.tool_input.command) || "")); }
    catch (e) { process.stdout.write(""); }
  });
' 2>/dev/null)"

[ -z "$cmd" ] && exit 0

block() {
  echo "BLOCKED by guard-prod hook: $1" >&2
  echo "Command: $cmd" >&2
  echo "PROD deployments are the user's decision. DEV changes ship by pushing main; the Orchestrator does that after review." >&2
  exit 2
}

lc="$(printf '%s' "$cmd" | tr '[:upper:]' '[:lower:]')"

# 1. Workflow dispatch or API dispatch naming prod.
if printf '%s' "$lc" | grep -Eq '(gh[[:space:]]+workflow[[:space:]]+run|/dispatches|actions/workflows)'; then
  if printf '%s' "$lc" | grep -Eq '(^|[^a-z])prod(uction)?([^a-z]|$)'; then
    block "workflow dispatch targeting prod"
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
    block "run $run_id contains a prod job"
  fi
fi

# 3. Direct deploy / destructive infrastructure commands — pipelines only.
if printf '%s' "$lc" | grep -Eq 'terraform[[:space:]]+(apply|destroy)'; then
  block "terraform apply/destroy is pipeline-only (terraform-apply.yml, dev by dispatch; prod by the user)"
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
