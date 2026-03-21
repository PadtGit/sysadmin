# sysadmin-main Skill Entry

Use the canonical script tree under `PowerShell Script/`.

## Core Rules

- `PowerShell Script/V7/*` is the primary implementation surface.
- `PowerShell Script/V5/*` is the compatibility/backport surface.
- Keep `Set-StrictMode -Version 3.0`, `$ErrorActionPreference = 'Stop'`, and `SupportsShouldProcess` behavior intact unless the task explicitly changes them.
- Preserve usable `-WhatIf` behavior wherever the script already supports safe preview without elevation.
- Write generated validation output to `artifacts/validation/`, not to tracked repo files.

## Validation Entry Points

- Nested V5 validator: `PowerShell Script\Invoke-V5-WhatIfValidation.ps1`
- Root wrapper: `Invoke-V5-WhatIfValidation.ps1`
- Pester tests: `tests/`
- Analyzer runner: `tools\Invoke-PSScriptAnalyzer.ps1`

## Detailed Workflow

For the repo-specific maintenance workflow, agent roles, and PowerShell rules, use `.agents/skills/maintain-windows-admin-powershell/SKILL.md`.
