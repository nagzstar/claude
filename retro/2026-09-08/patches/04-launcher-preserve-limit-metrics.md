# 04 — Launcher: preserve the tree on any abnormal end, detect the session limit, record metrics (A)

**Finding.** F1/H3/F20: three lost runs left uncommitted work that the user rescued by hand (#12
3,848 lines → `47251bf`; #55 `issue-55-partial-*`; #70 → `730df20`); #13's limit death reported
`success` and the rerun waited 69 min; four prompt-only files came from pre-flight refusals after
the prompt was written. Metrics for #31 are copied by hand (2 rows in a day).

**Expected effect.** No hand rescue: the diff and untracked files are saved to
`pm-runs/issue-<n>-partial-<ts>.diff` and stashed as `pm-run-issue draft #n <ts>` (main stays
clean for the next run, which is told about the stash). Limit deaths exit 3 with the reset time and
resume command. One CSV line per run feeds `retro/metrics.js` (see `measurement.md`).

```diff
--- a/.claude/scripts/pm-run-issue.sh
+++ b/.claude/scripts/pm-run-issue.sh
@@ -236,7 +236,6 @@ fi
 ts="$(date -u +%Y%m%dT%H%M%SZ)"
 run_dir="$NGM_ROOT/.agent-context/pm-runs"; mkdir -p "$run_dir"
 base="$run_dir/issue-$issue-$ts"
-build_prompt > "$base.prompt.md"
 
 cmd=("$claude_bin" -p --session-id "$session_id" --name "issue-$issue" --model "$model" \
      --permission-mode "$mode" --output-format stream-json --verbose)
@@ -252,6 +251,11 @@ if [ "$dry" -eq 1 ]; then
 fi
 
 # ---- launch -----------------------------------------------------------------------------------
+# A previous abnormal end may have left a draft stash; tell the session so it can restore it.
+draft="$(git -C "$NGM_ROOT" stash list | grep -m1 "pm-run-issue draft #$issue " || true)"
+[ -n "$draft" ] && batch_block="${batch_block}
+A PREVIOUS SESSION LEFT A DRAFT: \`git stash list\` shows \"${draft}\". Read its diff first (\`git stash show -p <ref>\`), decide what to keep, apply it with \`git stash pop\` before doing new work, and never redo what it contains."
+build_prompt > "$base.prompt.md"
 printf 'issue=%s\npid=%s\nsession=%s\nstarted=%s\nlog=%s\n' "$issue" "$$" "$session_id" "$ts" "$base.log" > "$lock"
 trap 'rm -f "$lock"' EXIT
@@ -297,10 +301,45 @@ rc=$?
 
+# ---- outcome ----------------------------------------------------------------------------------
+ended="$(date -u +%Y%m%dT%H%M%SZ)"
+limit_line="$(grep -m1 -oE "hit your session limit[^\"|]*" "$base.log" || true)"
+final_labels="$(gh issue view "$issue" -R "$REPO" --json labels --jq '[.labels[].name]|join(",")' 2>/dev/null || echo "")"
+outcome="delivered"
+case ",${final_labels}," in *,ready-for-prod,*) outcome="ready-for-prod" ;; *,needs-decision,*) outcome="needs-decision" ;; *,blocked,*) outcome="blocked" ;; *) outcome="incomplete" ;; esac
+[ -n "$limit_line" ] && outcome="session-limit"
+[ -f "$base.json" ] || outcome="${outcome}/no-result"
+
+# Preserve whatever the session left in the tree: a diff file (human-readable) plus a stash
+# (machine-restorable), so main is clean for the next run and nothing is rescued by hand again.
+if [ -n "$(git -C "$NGM_ROOT" status --short)" ]; then
+  git -C "$NGM_ROOT" add -A -N . 2>/dev/null
+  git -C "$NGM_ROOT" diff > "$base.partial.diff"
+  git -C "$NGM_ROOT" stash push -u -q -m "pm-run-issue draft #$issue $ts ($outcome)" && \
+    echo "pm-run-issue: uncommitted work preserved in $base.partial.diff and stash 'pm-run-issue draft #$issue $ts' — restore with: git -C \"$NGM_ROOT\" stash pop"
+fi
+
+# One line per run for the retrospective (retro/metrics.js reads it).
+node -e '
+  const fs=require("fs");const [csv,json,issue,ts,ended,model,outcome,log]=process.argv.slice(1);
+  let j={};try{j=JSON.parse(fs.readFileSync(json,"utf8"))}catch{}
+  const L=fs.existsSync(log)?fs.readFileSync(log,"utf8").split("\n").filter(l=>/^\d\d:\d\d:\d\d /.test(l)):[];
+  const s=t=>{const [h,m,x]=t.split(":").map(Number);return h*3600+m*60+x};
+  const wall=L.length?((s(L[L.length-1].slice(0,8))-s(L[0].slice(0,8))+86400)%86400):"";
+  const mu=j.modelUsage||{};const sum=k=>Object.values(mu).reduce((a,u)=>a+(u[k]||0),0);
+  const row=[issue,ts,ended,model,outcome,j.num_turns??"",wall,j.total_cost_usd??"",sum("outputTokens"),sum("cacheCreationInputTokens"),sum("cacheReadInputTokens"),(j.permission_denials||[]).length,L.filter(l=>/ TOOL Agent /.test(l)).length,Object.keys(mu).join("+")].join(",");
+  if(!fs.existsSync(csv))fs.writeFileSync(csv,"issue,ts,ended,model,outcome,turns,wall_s,cost_usd,out_tokens,cache_create,cache_read,denials,agent_calls,models\n");
+  fs.appendFileSync(csv,row+"\n");' "$run_dir/metrics.csv" "$base.json" "$issue" "$ts" "$ended" "$model" "$outcome" "$base.log"
+
+if [ -n "$limit_line" ]; then
+  echo "!!! pm-run-issue: the session hit the subscription limit: $limit_line"
+  echo "    Wait for the reset, then: claude -p --resume $session_id \"Continue issue #$issue from where you stopped.\""
+  exit 3
+fi
+
 # A zero exit means the process ended cleanly, NOT that the issue was delivered: a session that
 # ends its turn while "waiting" for a background agent exits 0 having done nothing. The issue's
 # status label is the real outcome — the session must move it off in-progress before finishing.
-final_labels="$(gh issue view "$issue" -R "$REPO" --json labels --jq '[.labels[].name]|join(",")' 2>/dev/null || echo "")"
 case ",${final_labels}," in
```

Also: log lines are UTC while git and the task files are local time — add `line("TZ UTC")` as the
first log line in the stream parser so a reader is not misled. `validate.sh` section 6: `grep -q
'metrics.csv' .claude/scripts/pm-run-issue.sh && ok`, `grep -q 'stash push' … && ok`, `grep -q
'session limit' … && ok`.
