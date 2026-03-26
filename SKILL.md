# sysadmin-main Skill Entry

Use the canonical script tree under `PowerShell Script/`.

## Core Rules

- This branch supports Windows PowerShell 5.1 only.
- `PowerShell Script/*` is the primary implementation surface.
- Keep `Set-StrictMode -Version 3.0`, `$ErrorActionPreference = 'Stop'`, and `SupportsShouldProcess` behavior intact unless the task explicitly changes them.
- Preserve usable `-WhatIf` behavior wherever the script already supports safe preview without elevation.
- Write generated validation output to `artifacts/validation/`, not to tracked repo files.

## Validation Entry Points

- Root validator: `Invoke-WhatIfValidation.ps1`
- Pester tests: `tests/`
- Analyzer runner: `& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PWD 'tools\Invoke-PSScriptAnalyzer.ps1') -Path . -Recurse -SettingsPath (Join-Path $PWD 'tools\PSScriptAnalyzerSettings.psd1') -EnableExit -ExitCodeMode AllDiagnostics`

## Detailed Workflow

For the repo-specific maintenance workflow, agent roles, and PowerShell rules, use `.agents/skills/maintain-windows-admin-powershell/SKILL.md`.
