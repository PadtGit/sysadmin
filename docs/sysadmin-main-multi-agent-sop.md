# sysadmin-main Multi-Agent SOP

## Current State

- Canonical scripts live only under `PowerShell Script/V5` and `PowerShell Script/V7`.
- The repo-root `Invoke-V5-WhatIfValidation.ps1` is a wrapper for `PowerShell Script/Invoke-V5-WhatIfValidation.ps1`.
- Generated validation output belongs under `artifacts/validation/`.
- `SKILL.md` at the repo root is the human/agent entrypoint; the deeper repo-specific workflow remains under `.agents/skills/maintain-windows-admin-powershell/SKILL.md`.

## Working Rules

- Update `PowerShell Script/V7` first, then adapt `PowerShell Script/V5` only where compatibility or parity requires it.
- Preserve `Set-StrictMode -Version 3.0`, `$ErrorActionPreference = 'Stop'`, and `SupportsShouldProcess`.
- Prefer safe `-WhatIf` preview behavior over hard admin-only preview blocks where the script can truthfully support preview without elevation.
- Keep result objects compact and structured. Avoid noisy transcript-style output by default.

## Validation Surfaces

- Direct targeted validation:
  - `pwsh -NoProfile -ExecutionPolicy Bypass -File 'PowerShell Script\V7\<category>\<script>.ps1' -WhatIf`
  - `powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'PowerShell Script\V5\<category>\<script>.ps1' -WhatIf`
- Fixed-list canonical V5 helper:
  - `PowerShell Script\Invoke-V5-WhatIfValidation.ps1`
- Analyzer:
  - `pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PWD 'tools\Invoke-PSScriptAnalyzer.ps1') -Path . -Recurse -SettingsPath (Join-Path $PWD 'tools\PSScriptAnalyzerSettings.psd1') -EnableExit -ExitCodeMode AllDiagnostics`
- Tests:
  - `tests/`
- CI:
  - `.github/workflows/powershell-validation.yml`

## Current High-Risk Areas

- Service-control scripts that stop and restart `Spooler` or `wuauserv`
- Network reset/reboot scripts
- Broad Windows cleanup scripts
- Installer orphan move scripts

## Roadmap

### PSScriptAnalyzer

- Use the repo-wide recursive analyzer command with the canonical settings file as the baseline local and agent validation path.
- Keep workflow expectations aligned with `-EnableExit -ExitCodeMode AllDiagnostics` so CI and local runs fail on any reported diagnostic.

### Pester

- Keep smoke tests focused on preview-safe scripts.
- Use contract tests for result shapes and path conventions.
- Add deeper mocked tests for installer, service, printer, and reboot flows as the harness matures.

### Windows Sandbox

- Use `sandbox/sysadmin-main-validation.wsb` as the disposable validation shell for risky scripts.
- Keep the repo mapped read-only and networking disabled unless a task explicitly requires network access.

### CI

- Use the Windows workflow to run Pester, analyzer checks, and a small set of trusted `-WhatIf` smoke commands.
- Publish validation and test artifacts from `artifacts/validation/`.
