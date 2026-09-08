# 03 — guard-prod matches the command, not heredoc bodies; large heredoc file writes are refused (A)

**Finding.** H5: 4 heredoc file-write failures in 6 runs — guard-prod false positives (#13
05:18:59, #55 15:04:26) and the Windows command-line limit (#55 14:18:27 "exceeded the
command-length limit"; #56 17:31:49 `ENAMETOOLONG`, the design was lost with the run). The lesson
(`lessons.md:229`) recurred 4× on the day it was written.

**Expected effect.** No false positives on document text; any heredoc body over 2,000 bytes is
refused with "use Write" before it can hit the OS limit or lose a document. Legitimate small
heredocs (commit messages, 5-line files) still pass. Prod matching is unchanged for real commands
(the stripped command still contains `gh workflow run … prod`).

```diff
--- a/.claude/hooks/guard-prod.sh
+++ b/.claude/hooks/guard-prod.sh
@@ -36,6 +36,32 @@ agent="$(printf '%s' "$parsed" | node -e 'let d="";process.stdin.on("data",c=>d+=c);process.stdin.on("end",()=>process.stdout.write(JSON.parse(d)[1]))')"
 
 [ -z "$cmd" ] && exit 0
 
+# Heredocs: a document that QUOTES a pipeline command is not a pipeline command. Strip every
+# heredoc body before matching, and refuse to write a large file through Bash at all — Windows
+# rejects command lines above ~32 K (ENAMETOOLONG lost the #56 design on 2026-09-07) and the Write
+# tool exists for exactly this.
+heredoc_stats="$(printf '%s' "$cmd" | node -e '
+  let d="";process.stdin.on("data",c=>d+=c);process.stdin.on("end",()=>{
+    const re=/<<-?\s*["\x27]?([A-Za-z_][A-Za-z0-9_]*)["\x27]?[^\n]*\n([\s\S]*?)\n\1(?=\n|$)/g;
+    let m,max=0,out=d;while((m=re.exec(d))){max=Math.max(max,m[2].length);}
+    out=d.replace(re,(all,tag)=>"<<"+tag+" (heredoc body stripped)\n"+tag);
+    process.stdout.write(max+"\n"+out);});')"
+heredoc_max="${heredoc_stats%%$'\n'*}"
+cmd_stripped="${heredoc_stats#*$'\n'}"
+if [ "${heredoc_max:-0}" -gt "${HEREDOC_MAX_BYTES:-2000}" ]; then
+  echo "BLOCKED by guard-prod hook: heredoc body of ${heredoc_max} bytes. Write files with the Write tool, never a heredoc: Windows rejects long command lines (ENAMETOOLONG) and the content is lost." >&2
+  exit 2
+fi
+
 approval_file="${PROD_APPROVAL_FILE:-${CLAUDE_PROJECT_DIR:-$PWD}/.agent-context/.prod-approval}"
@@ -72,7 +98,7 @@ prod_release() { # reason
   exit 0
 }
 
-lc="$(printf '%s' "$cmd" | tr '[:upper:]' '[:lower:]')"
+lc="$(printf '%s' "$cmd_stripped" | tr '[:upper:]' '[:lower:]')"
```

Also change the `block()` message line 47 to: `"This guard matches the command with heredoc bodies
removed. To write a file that mentions a pipeline command, use the Write tool."`

`validate.sh` (section 4) — add:

```bash
prod allow "cat > design.md <<'EOF'
Rollback: gh workflow run deploy.yml -f environment=prod
EOF"
prod allow "git commit -F - <<'MSG'
Record the prod release (environment=prod dispatch of deploy.yml)
MSG"
big="$(node -e 'process.stdout.write("x".repeat(2500))')"
prod block "cat > .agent-context/tasks/x-design.md <<'EOF'
$big
EOF"
prod block 'gh workflow run deploy.yml -f environment=prod'   # still blocked without approval
```
