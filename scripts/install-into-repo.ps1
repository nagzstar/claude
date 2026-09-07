# Deploy the NGM agent system into the NGM repo, so you can run Claude Code from inside
# NextGenMaher and have every agent, skill, hook, script and context file resolve naturally.
#
#   powershell -File scripts/install-into-repo.ps1
#
# This repo stays the source of truth. Re-run after changing anything under .claude/ or
# .agent-context/. The install is idempotent. It is additive for context and tasks (your
# per-task records in .agent-context/tasks/ are never deleted), but .claude/agents, hooks,
# scripts and skills are SYNCED: files that no longer exist here are removed there, so a
# renamed or deleted agent cannot linger as a duplicate.

param(
  [string]$Target = "$HOME\git\ngm.app"
)

$ErrorActionPreference = 'Stop'
$Source = Split-Path -Parent $PSScriptRoot

if (-not (Test-Path $Target)) { throw "Target repo not found: $Target" }

function Sync-Dir([string]$From, [string]$To, [string]$Filter = '*') {
  New-Item -ItemType Directory -Force -Path $To | Out-Null
  $wanted = @{}
  Get-ChildItem -Path $From -File -Filter $Filter | ForEach-Object {
    Copy-Item $_.FullName (Join-Path $To $_.Name) -Force
    $wanted[$_.Name] = $true
  }
  Get-ChildItem -Path $To -File -Filter $Filter | Where-Object { -not $wanted.ContainsKey($_.Name) } | ForEach-Object {
    Write-Host "  removing stale $($_.FullName)"
    Remove-Item $_.FullName -Force
  }
}

# Synced directories (source of truth wins, stale files removed).
Sync-Dir "$Source\.claude\agents"  "$Target\.claude\agents"  '*.md'
Sync-Dir "$Source\.claude\hooks"   "$Target\.claude\hooks"   '*.sh'
Sync-Dir "$Source\.claude\scripts" "$Target\.claude\scripts" '*.sh'
Get-ChildItem -Path "$Source\.claude\skills" -Directory | ForEach-Object {
  Sync-Dir $_.FullName (Join-Path "$Target\.claude\skills" $_.Name) 'SKILL.md'
}
Get-ChildItem -Path "$Target\.claude\skills" -Directory | Where-Object {
  -not (Test-Path (Join-Path "$Source\.claude\skills" $_.Name))
} | ForEach-Object { Write-Host "  removing stale skill $($_.FullName)"; Remove-Item $_.FullName -Recurse -Force }

# Additive: context files, baseline, templates. Task records are never removed. lessons.md is
# NOT installed at all: ngm.app owns and tracks it (decision 2026-09-07, ngm.app#28).
New-Item -ItemType Directory -Force -Path "$Target\.agent-context\tasks" | Out-Null
Get-ChildItem "$Source\.agent-context" -File -Filter '*.md' | Where-Object { $_.Name -ne 'lessons.md' } | ForEach-Object {
  Copy-Item $_.FullName "$Target\.agent-context\" -Force
}
Copy-Item "$Source\.agent-context\*.json" "$Target\.agent-context\" -Force
Copy-Item "$Source\.agent-context\tasks\TEMPLATE.md" "$Target\.agent-context\tasks\" -Force
Copy-Item "$Source\.agent-context\tasks\EXAMPLE-*.md" "$Target\.agent-context\tasks\" -Force
Copy-Item "$Source\CLAUDE.md" "$Target\CLAUDE.md" -Force

# settings.json is rewritten rather than copied: additionalDirectories is only needed when
# driving the repo from outside it, and would be dead weight here. Hooks carry over unchanged
# because they resolve through $CLAUDE_PROJECT_DIR. The session model is deliberately
# different per repo: this repo pins Fable because changes to the agent system compound
# across every future session, while the Orchestrator working on NGM itself runs on Opus and
# escalates per task through the tier ladder. The installer enforces that split.
# Written via .NET with UTF8Encoding($false) because Set-Content -Encoding utf8 emits a BOM
# on Windows PowerShell 5.1, and a BOM makes the file unparseable to strict JSON readers.
$settings = Get-Content "$Source\.claude\settings.json" -Raw | ConvertFrom-Json
$settings.permissions.PSObject.Properties.Remove('additionalDirectories')
$settings.model = 'claude-opus-5'
$json = $settings | ConvertTo-Json -Depth 10
[System.IO.File]::WriteAllText(
  "$Target\.claude\settings.json",
  $json,
  (New-Object System.Text.UTF8Encoding $false)
)

# Shell scripts must keep LF endings under Git Bash. Normalise in case the source checkout
# converted them.
Get-ChildItem -Path "$Target\.claude\hooks", "$Target\.claude\scripts" -Filter '*.sh' | ForEach-Object {
  $text = [System.IO.File]::ReadAllText($_.FullName) -replace "`r`n", "`n"
  [System.IO.File]::WriteAllText($_.FullName, $text, (New-Object System.Text.UTF8Encoding $false))
}

$agentCount = (Get-ChildItem "$Source\.claude\agents" -Filter '*.md').Count
Write-Host "Installed the NGM agent system into $Target"
Write-Host ""
Write-Host "  .claude/agents/         $agentCount specialists (synced)"
Write-Host "  .claude/skills/         $((Get-ChildItem "$Source\.claude\skills" -Directory).Name -join ', ') (synced)"
Write-Host "  .claude/hooks/          guard-prod, guard-paths (synced)"
Write-Host "  .claude/scripts/        check-app, check-dev, context-drift, prod-approval, pm-issue, pm-run-issue (synced)"
Write-Host "  .claude/settings.json   permissions + hooks (additionalDirectories stripped; model pinned to claude-opus-5)"
Write-Host "  .agent-context/         project, security-model, delivery, handoff, baseline, tasks (additive; lessons.md is owned by ngm.app, not installed)"
Write-Host "  CLAUDE.md               orchestrator contract"
Write-Host ""
Write-Host "Start a new console in $Target and give it an outcome."
