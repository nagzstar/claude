# 15 — Installer manifest, `validate.sh --installed`, RETROSPECTIVE out of the skills tree (B)

**Finding.** H13: the installed copy in ngm.app differs from the source in `RETROSPECTIVE.md` (one
stale line: the installer syncs `SKILL.md` per skill directory and never touches skills-root
files) and `settings.json` (intended). `validate.sh` §5 only checks that the installer *names* each
directory. No record of what was installed from which commit.

**Expected effect.** Drift is detected by a script, not by a retrospective; the installed tree
loses a 15 KB document that is not a skill.

```diff
--- a/scripts/install-into-repo.ps1
+++ b/scripts/install-into-repo.ps1
@@ -79,6 +79,20 @@ Get-ChildItem -Path "$Target\.claude\hooks", "$Target\.claude\scripts" -Filter '*.sh' | ForEach-Object {
   [System.IO.File]::WriteAllText($_.FullName, $text, (New-Object System.Text.UTF8Encoding $false))
 }
 
+# Manifest: what was installed, from which source commit, with a hash per file. validate.sh
+# --installed compares the installed tree against it (and the source against the installed copy).
+$commit = (git -C $Source rev-parse --short HEAD 2>$null)
+$manifest = [ordered]@{ source_commit = $commit; installed_at = (Get-Date).ToString('s'); files = [ordered]@{} }
+Get-ChildItem -Path "$Target\.claude\agents", "$Target\.claude\hooks", "$Target\.claude\scripts", "$Target\.claude\skills" -Recurse -File |
+  Where-Object { $_.Name -ne 'settings.local.json' } | ForEach-Object {
+    $rel = $_.FullName.Substring($Target.Length + 1) -replace '\\', '/'
+    $manifest.files[$rel] = (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower()
+  }
+foreach ($f in 'CLAUDE.md', '.agent-context/project.md', '.agent-context/security-model.md', '.agent-context/delivery.md', '.agent-context/handoff.md', '.agent-context/patterns.md', '.agent-context/decisions.md', '.agent-context/tasks/TEMPLATE.md') {
+  if (Test-Path "$Target\$f") { $manifest.files[$f] = (Get-FileHash "$Target\$f" -Algorithm SHA256).Hash.ToLower() }
+}
+[System.IO.File]::WriteAllText("$Target\.claude\INSTALLED.json", ($manifest | ConvertTo-Json -Depth 5), (New-Object System.Text.UTF8Encoding $false))
+
 $agentCount = (Get-ChildItem "$Source\.claude\agents" -Filter '*.md').Count
```
Also in the installer: sync skills-root files too (`Sync-Dir "$Source\.claude\skills"
"$Target\.claude\skills" '*.md'` after the per-directory loop) — or, with the move below, there are
none to sync.

`validate.sh` — new section "8. installed copy" (runs only when `NGM_ROOT/.claude/INSTALLED.json`
exists; `--installed` makes a mismatch a failure instead of a warning):

```bash
man="$NGM_ROOT/.claude/INSTALLED.json"
if [ -f "$man" ]; then
  node -e '
    const fs=require("fs"),cr=require("crypto"),p=require("path");const [man,src,tgt,strict]=process.argv.slice(1);
    const m=JSON.parse(fs.readFileSync(man,"utf8"));let bad=0;
    const h=f=>cr.createHash("sha256").update(fs.readFileSync(f)).digest("hex");
    for(const [rel,hash] of Object.entries(m.files)){
      const t=p.join(tgt,rel); if(!fs.existsSync(t)){console.log("missing in ngm.app: "+rel);bad++;continue}
      if(h(t)!==hash){console.log("changed in ngm.app since install: "+rel);bad++}
      const s=p.join(src,rel); if(fs.existsSync(s)&&h(s)!==hash&&!/settings\.json$/.test(rel)){console.log("source changed since install (re-run the installer): "+rel);bad++}
    }
    console.log(`installed from ${m.source_commit} at ${m.installed_at}: ${bad} difference(s)`);
    process.exit(bad&&strict==="1"?1:0)' "$man" "$root" "$NGM_ROOT" "${installed_strict:-0}" && ok || bad "installed copy differs from the manifest (see above)"
fi
```
(`installed_strict=1` when `--installed` is passed; parse it next to the existing `set -u` block.)

**RETROSPECTIVE.md**: `git mv .claude/skills/RETROSPECTIVE.md docs/RETROSPECTIVE.md`; update the two
references (`CLAUDE.md` has none; `.claude/skills/*` "Precedence" lines do not cite it; the
`README`/`evals/README.md` may). It is not installed; the ngm.app copy is deleted by the next
install (skills-root sync) — say so in the install summary line.
