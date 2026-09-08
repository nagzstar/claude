# 01 — Refuse to launch a headless run while the workspace is untrusted (A)

**Finding.** H2: 16/16 runs start with `Ignoring 32 permissions.allow entries … this workspace has
not been trusted`; `~/.claude.json` has `hasTrustDialogAccepted=false` for `c:/Users/nagaj/git/ngm.app`
and `C:/Users/nagaj/git/ngm.app`. Every call was adjudicated by the auto classifier; 9 denials.

**Expected effect.** Allow list active in every run; `.env` and prod controls unchanged (deny list
and hooks). Fewer classifier denials (≈ 3 per 14 runs) and no classifier latency on allowed calls.
One-time action for the user: open `claude` interactively in `C:/Users/nagaj/git/ngm.app` once and
accept the trust dialog (the pre-flight prints exactly this).

```diff
--- a/.claude/scripts/pm-run-issue.sh
+++ b/.claude/scripts/pm-run-issue.sh
@@ -182,6 +182,20 @@ fi
 [ -n "$claude_bin" ] && [ -x "$claude_bin" ] || die "claude CLI not found (set CLAUDE_CODE_EXECPATH or put claude on PATH)"
 
 [ -d "$NGM_ROOT/.git" ] || die "NGM_ROOT is not a git checkout: $NGM_ROOT"
+# The allow list in .claude/settings.json is ignored unless the workspace has been trusted once
+# interactively; every headless call is then adjudicated by the permission classifier (16/16 runs on
+# 2026-09-07 logged "Ignoring 32 permissions.allow entries"). Refuse to burn a session on that.
+trusted="$(node -e '
+  const fs=require("fs"),p=process.env.HOME+"/.claude.json";
+  try{const j=JSON.parse(fs.readFileSync(p,"utf8"));const P=j.projects||{};const want=process.argv[1].toLowerCase();
+    for(const k of Object.keys(P)) if(k.replace(/\\/g,"/").toLowerCase()===want && P[k].hasTrustDialogAccepted){console.log("yes");process.exit(0)}
+  }catch(e){} console.log("no")' "$NGM_ROOT" 2>/dev/null)"
+if [ "$trusted" != "yes" ] && [ "${PM_ALLOW_UNTRUSTED:-0}" != "1" ]; then
+  die "$NGM_ROOT has not been trusted, so the allow list would be ignored and every tool call classified.
+  Once: open 'claude' interactively in $NGM_ROOT, accept the trust dialog, then re-run.
+  (PM_ALLOW_UNTRUSTED=1 overrides — not recommended.)"
+fi
 gh auth status >/dev/null 2>&1 || die "gh is not authenticated"
```

`validate.sh` case (section 6): `grep -q hasTrustDialogAccepted .claude/scripts/pm-run-issue.sh && ok
|| bad "pm-run-issue lacks the trust pre-flight"`.
