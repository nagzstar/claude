# 02 — Hook on `Agent`: no background delegation in headless runs, no Opus/Fable engineers without a tier (A)

**Finding.** H1/F1: the two fatal losses (#12 09:50, #56 17:21) and the two post-delivery kills
(#3, #8) all involve `run_in_background: true`; the 17:42 prose fix has held for 7 calls, which is
not a guarantee. H7: frontend-engineer ran on Opus in 6/16 invocations with no fewer correction
rounds (1.25 vs 1.0); an architect ran on a tier-2 UI ticket (#56).

**Expected effect.** F-run from background delegation → 0 (mechanical); ≈ $2 per avoided Opus
frontend invocation; the tier must be written in the handoff before an engineer is upgraded, which
is what CLAUDE.md already requires. Hooks see `tool_input` for `Agent` like any other tool.

New file `.claude/hooks/guard-agent.sh`:

```bash
#!/usr/bin/env bash
# PreToolUse hook (matcher: Agent). Two deterministic rules on how the Orchestrator delegates.
#  1. Headless runs (NGM_HEADLESS=1, set by pm-run-issue.sh): run_in_background is refused. A
#     `claude -p` session that ends its turn with agents still running loses them (#12, #56 on
#     2026-09-07) or is killed at the 600 s ceiling (#3, #8). Foreground only.
#  2. Engineers and QA run on their default model unless the handoff states the tier that
#     justifies the upgrade: `model: opus|fable|claude-opus-5|claude-fable-5-1` for backend-engineer,
#     frontend-engineer, deployment-engineer or qa-engineer requires "TIER: 3" or "TIER: 4" (or
#     "tier 3"/"tier 4") in the prompt. Security review and the architect are exempt (their floor
#     is Opus by rule).
# Exit 2 = block (message to the model). Exit 0 = allow.
set -u
input="$(cat)"
read -r bg type model has_tier <<EOF
$(printf '%s' "$input" | node -e '
  let d="";process.stdin.on("data",c=>d+=c);process.stdin.on("end",()=>{try{const j=JSON.parse(d);const t=j.tool_input||{};
    const tier=/\bTIER:\s*[34]\b|\btier[- ]?[34]\b/i.test(String(t.prompt||""));
    console.log((t.run_in_background?1:0)+" "+(t.subagent_type||"-")+" "+String(t.model||"default").toLowerCase()+" "+(tier?1:0));
  }catch(e){console.log("0 - default 0")}})' 2>/dev/null)
EOF
block() { echo "BLOCKED by guard-agent hook: $1" >&2; exit 2; }
if [ "${NGM_HEADLESS:-0}" = "1" ] && [ "$bg" = "1" ]; then
  block "run_in_background is not allowed in a headless session — your turn ending is the session ending. Dispatch $type in the foreground and wait for its result."
fi
case "$type" in
  backend-engineer|frontend-engineer|deployment-engineer|qa-engineer)
    case "$model" in
      opus|fable|claude-opus-5|claude-fable-5-1)
        [ "$has_tier" = "1" ] || block "$type on $model needs the tier in the handoff (TIER: 3 or TIER: 4). Sonnet is the floor for routine work; write the tier or drop the model override." ;;
    esac ;;
esac
exit 0
```

```diff
--- a/.claude/settings.json
+++ b/.claude/settings.json
@@ -59,6 +59,16 @@
             "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/guard-prod.sh\"",
             "timeout": 30
           }
         ]
+      },
+      {
+        "matcher": "Agent",
+        "hooks": [
+          {
+            "type": "command",
+            "command": "bash \"$CLAUDE_PROJECT_DIR/.claude/hooks/guard-agent.sh\"",
+            "timeout": 15
+          }
+        ]
       }
     ]
   }
```

```diff
--- a/.claude/scripts/pm-run-issue.sh
+++ b/.claude/scripts/pm-run-issue.sh
@@ -257,6 +257,7 @@ trap 'rm -f "$lock"' EXIT
 
 cd "$NGM_ROOT" || die "cannot cd to $NGM_ROOT"
-"${cmd[@]}" "$(cat "$base.prompt.md")" 2>>"$base.log" | node -e '
+export NGM_HEADLESS=1   # guard-agent.sh refuses run_in_background under this marker
+"${cmd[@]}" "$(cat "$base.prompt.md")" 2>>"$base.log" | node -e '
```

`validate.sh` (section 4) — add after the `paths` cases:

```bash
agentcall() { # expect headless(0|1) json-input
  local exp="$1" rc; NGM_HEADLESS="$2" bash .claude/hooks/guard-agent.sh <<<"$3" >/dev/null 2>&1; rc=$?
  if { [ "$exp" = block ] && [ $rc -eq 2 ]; } || { [ "$exp" = allow ] && [ $rc -eq 0 ]; }; then ok; else bad "guard-agent: expected $exp (rc=$rc) for $3"; fi
}
agentcall block 1 '{"tool_name":"Agent","tool_input":{"subagent_type":"frontend-engineer","run_in_background":true,"prompt":"TIER: 2"}}'
agentcall allow 0 '{"tool_name":"Agent","tool_input":{"subagent_type":"frontend-engineer","run_in_background":true,"prompt":"TIER: 2"}}'
agentcall allow 1 '{"tool_name":"Agent","tool_input":{"subagent_type":"frontend-engineer","prompt":"TIER: 2"}}'
agentcall block 1 '{"tool_name":"Agent","tool_input":{"subagent_type":"frontend-engineer","model":"opus","prompt":"GOAL: a page"}}'
agentcall allow 1 '{"tool_name":"Agent","tool_input":{"subagent_type":"backend-engineer","model":"opus","prompt":"TIER: 3 — edits an RLS policy"}}'
agentcall allow 1 '{"tool_name":"Agent","tool_input":{"subagent_type":"security-reviewer","model":"fable","prompt":"review"}}'
```
Also in section 3: check that `settings.json` registers `guard-agent.sh` and the file exists.
