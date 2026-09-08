#!/usr/bin/env bash
# PreToolUse hook (matcher: Agent). Two deterministic rules on how the Orchestrator delegates.
#
#  1. Headless runs (NGM_HEADLESS=1, exported by pm-run-issue.sh): run_in_background is refused.
#     A `claude -p` session that ends its turn with agents still running loses them (#12 and #56
#     on 2026-09-07) or is killed at the 600 s background ceiling (#3, #8). Foreground only.
#  2. Engineers and QA run on their default model unless the handoff states the tier that
#     justifies the upgrade: `model: opus|fable|claude-opus-5|claude-fable-5-1` for
#     backend-engineer, frontend-engineer, deployment-engineer or qa-engineer requires
#     "TIER: 3" / "TIER: 4" (or "tier 3" / "tier 4") in the prompt. Security review and the
#     architect are exempt: their floor is Opus by rule.
#
# Exit 2 = block (message on stderr is shown to the model). Exit 0 = allow.
set -u
input="$(cat)"
parsed="$(printf '%s' "$input" | node -e '
  let d="";process.stdin.on("data",c=>d+=c);process.stdin.on("end",()=>{
    try{const j=JSON.parse(d);const t=j.tool_input||{};
      const tier=/\bTIER:\s*[34]\b|\btier[- ]?[34]\b/i.test(String(t.prompt||""));
      process.stdout.write((t.run_in_background?1:0)+" "+(t.subagent_type||"-")+" "+String(t.model||"default").toLowerCase()+" "+(tier?1:0));
    }catch(e){process.stdout.write("0 - default 0")}});' 2>/dev/null)"
bg="${parsed%% *}"; rest="${parsed#* }"; type="${rest%% *}"; rest="${rest#* }"; model="${rest%% *}"; has_tier="${rest#* }"

block() { echo "BLOCKED by guard-agent hook: $1" >&2; exit 2; }

if [ "${NGM_HEADLESS:-0}" = "1" ] && [ "$bg" = "1" ]; then
  block "run_in_background is not allowed in a headless session — your turn ending is the session ending. Dispatch $type in the foreground and wait for its result."
fi
case "$type" in
  backend-engineer|frontend-engineer|deployment-engineer|qa-engineer|fullstack-engineer)
    case "$model" in
      opus|fable|claude-opus-5|claude-fable-5-1)
        [ "$has_tier" = "1" ] || block "$type on $model needs the tier in the handoff (TIER: 3 or TIER: 4). Sonnet is the floor for routine work; write the tier or drop the model override." ;;
    esac ;;
esac
exit 0
