# Deploy the NGM agent system into the NGM repo, so you can run Claude Code from inside
# NextGenMaher and have every agent, skill and context file resolve naturally.
#
#   powershell -File scripts/install-into-repo.ps1
#
# This repo stays the source of truth. Re-run after changing any agent definition.
# The install is additive and idempotent: it only writes the files listed below.

param(
  [string]$Target = "$HOME\git\ngm.app"
)

$ErrorActionPreference = 'Stop'
$Source = Split-Path -Parent $PSScriptRoot

if (-not (Test-Path $Target)) { throw "Target repo not found: $Target" }

New-Item -ItemType Directory -Force -Path "$Target\.claude\agents" | Out-Null
New-Item -ItemType Directory -Force -Path "$Target\.claude\skills\ngm-facts" | Out-Null
New-Item -ItemType Directory -Force -Path "$Target\.agent-context\tasks" | Out-Null

Copy-Item "$Source\.claude\agents\*.md" "$Target\.claude\agents\" -Force
Copy-Item "$Source\.claude\skills\ngm-facts\SKILL.md" "$Target\.claude\skills\ngm-facts\" -Force
Copy-Item "$Source\.agent-context\*.md" "$Target\.agent-context\" -Force
Copy-Item "$Source\.agent-context\tasks\*.md" "$Target\.agent-context\tasks\" -Force
Copy-Item "$Source\CLAUDE.md" "$Target\CLAUDE.md" -Force

# settings.json is rewritten rather than copied: additionalDirectories is only needed when
# driving the repo from outside it, and would be dead weight here.
# Written via .NET with UTF8Encoding($false) because Set-Content -Encoding utf8 emits a BOM
# on Windows PowerShell 5.1, and a BOM makes the file unparseable to strict JSON readers.
$settings = Get-Content "$Source\.claude\settings.json" -Raw | ConvertFrom-Json
$settings.permissions.PSObject.Properties.Remove('additionalDirectories')
$json = $settings | ConvertTo-Json -Depth 10
[System.IO.File]::WriteAllText(
  "$Target\.claude\settings.json",
  $json,
  (New-Object System.Text.UTF8Encoding $false)
)

Write-Host "Installed the NGM agent system into $Target"
Write-Host ""
Write-Host "  .claude/agents/         5 specialists"
Write-Host "  .claude/skills/         ngm-facts"
Write-Host "  .claude/settings.json   permissions (additionalDirectories stripped)"
Write-Host "  .agent-context/         project, security-model, delivery, handoff, tasks"
Write-Host "  CLAUDE.md               orchestrator contract"
Write-Host ""
Write-Host "Start a new console in $Target and give it a task."
