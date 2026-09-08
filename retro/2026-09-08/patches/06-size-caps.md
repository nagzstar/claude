# 06 — Hard size caps: design docs, lessons index, fixed context (A)

**Finding.** H8/H9/H10: design docs 62–81 KB read 3–7× per run; `lessons.md` +44 lines per task
(750 lines, 64.7 KB, overflows the Bash output cap so it is read twice); CLAUDE.md 15.8 KB, three
deployment skills 10–11 KB each preloaded into engineers; task files up to 45 KB re-read 5×. Prose
caps ("one or two lines per lesson", `lessons.md:4`) did not hold.

**Expected effect.** Growth stops mechanically: a design over the cap cannot be written; a push
with an oversized lessons index fails `check-app.sh`; the fixed context read at boot cannot grow
without `validate.sh` failing. Caps are generous today (design 28 KB vs 62–81 KB observed; index
120 lines vs 750) and are meant to be lowered once patch 07 lands.

```diff
--- a/.claude/hooks/guard-paths.sh
+++ b/.claude/hooks/guard-paths.sh
@@ -13,10 +13,12 @@ set -u
 role="${1:-}"
 input="$(cat)"
 
-path="$(printf '%s' "$input" | node -e '
+read -r path bytes lines <<EOF
+$(printf '%s' "$input" | node -e '
   let d = ""; process.stdin.on("data", c => d += c);
   process.stdin.on("end", () => {
     try {
       const j = JSON.parse(d); const t = j.tool_input || {};
-      process.stdout.write(String(t.file_path || t.notebook_path || ""));
-    } catch (e) { process.stdout.write(""); }
+      const c = String(t.content ?? t.new_string ?? "");
+      process.stdout.write(String(t.file_path || t.notebook_path || "") + " " + c.length + " " + (c ? c.split("\n").length : 0));
+    } catch (e) { process.stdout.write(" 0 0"); }
   });
 ' 2>/dev/null)"
+EOF
@@ -78,6 +80,12 @@ case "$role" in
   researcher)
+    # A design is a decision record, not a book: 28,000 bytes (≈ 400 lines). The five designs of
+    # 2026-09-07 were 62–81 KB, each read 3–7 times per run. Split context out; cut code listings.
+    if printf '%s' "$rel" | grep -Eq -- '-design\.md$' && [ "${bytes:-0}" -gt "${DESIGN_MAX_BYTES:-28000}" ]; then
+      echo "BLOCKED by guard-paths hook (researcher): design is ${bytes} bytes; the cap is ${DESIGN_MAX_BYTES:-28000}. Remove restated context and code listings (the engineers write the SQL); keep decisions, contract, ownership, AC mapping." >&2
+      exit 2
+    fi
     printf '%s' "$rel" | grep -Eq '^\.agent-context/' && exit 0
     deny ;;
```

`check-app.sh` — add before the summary line (it runs in ngm.app before every push; the
Orchestrator has no guard-paths hook, so this is where the index cap bites):

```bash
# Context growth gate: the lessons index must stay short enough to be read once (ngm.app#28/#63).
lessons="$ngm/.agent-context/lessons.md"
if [ -f "$lessons" ]; then
  n="$(wc -l < "$lessons")"; cap="${LESSONS_MAX_LINES:-120}"
  if [ "$n" -gt "$cap" ]; then echo "lessons=FAIL ($n lines > $cap: fold into .agent-context/lessons/<domain>.md, keep one line here)"; fail=1; else echo "lessons=PASS ($n/$cap lines)"; fi
fi
```
(`LESSONS_MAX_LINES=800` until ticket T3 in patch 14 splits the file; then 120.)

`validate.sh` — new section "7. fixed context size":

```bash
cap() { local f="$1" max="$2" n; n="$(wc -c < "$f")"; [ "$n" -le "$max" ] && ok || bad "$f is $n bytes > cap $max (boot context grows with every prose rule; delete before adding)"; }
cap CLAUDE.md 16000
cap .claude/skills/ngm-standing-rules/SKILL.md 4000
for s in app-deployment db-deployment infra-deployment; do cap .claude/skills/$s/SKILL.md 12000; done   # 4000 after patch 07
cap .claude/skills/ngm-project-manager/SKILL.md 16000
cap .agent-context/tasks/TEMPLATE.md 2500
for a in .claude/agents/*.md; do cap "$a" 6500; done
```

`validate.sh` section 4 — guard-paths cases:

```bash
bigdesign="$(node -e 'process.stdout.write("d".repeat(29000))')"
printf '{"tool_name":"Write","tool_input":{"file_path":"%s","content":"%s"}}' "$N/.agent-context/tasks/x-design.md" "$bigdesign" | bash .claude/hooks/guard-paths.sh researcher >/dev/null 2>&1; [ $? -eq 2 ] && ok || bad "guard-paths: oversized design was not blocked"
printf '{"tool_name":"Write","tool_input":{"file_path":"%s","content":"short"}}' "$N/.agent-context/tasks/x-design.md" | bash .claude/hooks/guard-paths.sh researcher >/dev/null 2>&1; [ $? -eq 0 ] && ok || bad "guard-paths: small design blocked"
```
