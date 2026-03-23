# sysadmin-main Playbook

## Project Snapshot

- This repo contains Windows sysadmin PowerShell scripts with mirrored PowerShell 7 and Windows PowerShell 5.1 variants.
- Treat `PowerShell Script/*` as the canonical working tree.
- The only supported script trees are `PowerShell Script/V7/*` and `PowerShell Script/V5/*`.
- Git metadata and `git.exe` are available in this workspace.
- The repo-root `SKILL.md` is the human/agent entrypoint; the deeper repo-specific workflow lives under `.agents/skills/maintain-windows-admin-powershell/SKILL.md`.
- Generated validation output belongs under `artifacts/validation/`, not tracked repo result files.
- Prefer small, reversible changes over bulk rewrites.

## Canonical Layout

- `PowerShell Script/V7/*`: primary implementation surface.
- `PowerShell Script/V5/*`: compatibility and backport surface after a V7 change.
- `PowerShell Script/Copy-V7ToV5.ps1`: bulk copy helper for the nested tree.
- `PowerShell Script/Invoke-V5-WhatIfValidation.ps1`: fixed-list validator for the canonical V5 tree.
- `Invoke-V5-WhatIfValidation.ps1`: thin wrapper for the nested validator.
- `SKILL.md`: repo-root entrypoint that points agents to the deeper workflow skill.
- `tests/*`: Pester smoke and contract tests.
- `tools/Invoke-PSScriptAnalyzer.ps1`: analyzer runner.
- `.github/workflows/powershell-validation.yml`: CI entrypoint for analyzer, Pester, trusted `-WhatIf` smoke checks, and validation artifact upload.
- `sandbox/sysadmin-main-validation.wsb`: disposable Windows Sandbox profile with the repo mapped read-only and networking disabled.
- `docs/windows-sandbox-validation.md`: manual validation flow for risky scripts in Windows Sandbox.
- `docs/sysadmin-main-multi-agent-sop.md`: current operating notes for agent roles, validation surfaces, and repo workflow expectations.

## Safety Invariants

- Preserve truthful `#Requires -Version ...` declarations for each script variant.
- Preserve `[CmdletBinding(SupportsShouldProcess = $true)]` on scripts that change system state.
- Preserve `Set-StrictMode -Version 3.0` and `$ErrorActionPreference = 'Stop'` unless the task explicitly changes them.
- Keep admin-only work gated so `-WhatIf` remains usable wherever the script already supports safe preview without elevation.
- Keep exit-code behavior and structured result objects stable unless the task explicitly changes contract.
- Prefer summary-style output and optional logging over noisy item-by-item transcript behavior by default.

## Validation Commands

- V7 targeted validation:

```powershell
& (Get-Command pwsh.exe).Source -NoProfile -ExecutionPolicy Bypass -File 'PowerShell Script\V7\<category>\<script>.ps1' -WhatIf
```

- V5 targeted validation:

```powershell
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File 'PowerShell Script\V5\<category>\<script>.ps1' -WhatIf
```

- Canonical V5 helper:

```powershell
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File 'PowerShell Script\Invoke-V5-WhatIfValidation.ps1'
```

- Root wrapper helper:

```powershell
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File 'Invoke-V5-WhatIfValidation.ps1'
```

- V7-to-V5 bulk copy helper:

```powershell
& (Get-Command pwsh.exe).Source -NoProfile -ExecutionPolicy Bypass -File 'PowerShell Script\Copy-V7ToV5.ps1'
```

- Analyzer helper:

```powershell
& (Get-Command pwsh.exe).Source -NoProfile -ExecutionPolicy Bypass -File '.\tools\Invoke-PSScriptAnalyzer.ps1'
```

- Basic Pester helper:

```powershell
Invoke-Pester -Path .\tests
```

- CI-style Pester with NUnit XML output:

```powershell
$resultPath = Join-Path $PWD 'artifacts\validation\pester-results.xml'
New-Item -ItemType Directory -Force -Path (Split-Path -Path $resultPath -Parent) | Out-Null
Invoke-Pester -Path .\tests -Output Detailed -CI -Configuration @{
  TestResult = @{
    Enabled = $true
    OutputPath = $resultPath
    OutputFormat = 'NUnitXml'
  }
}
```

- Trusted local smoke checks aligned with CI:

```powershell
& (Get-Command pwsh.exe).Source -NoProfile -ExecutionPolicy Bypass -File '.\PowerShell Script\V7\Printer\Restart.Spool.DeletePrinterQSimple.ps1' -WhatIf
& (Get-Command pwsh.exe).Source -NoProfile -ExecutionPolicy Bypass -File '.\PowerShell Script\V7\windows-maintenance\Reset.Network.RebootPC.ps1' -WhatIf
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File '.\PowerShell Script\V5\Printer\Restart.Spool.DeletePrinterQSimple.ps1' -WhatIf
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File '.\PowerShell Script\V5\windows-maintenance\Nettoyage.Avance.Windows.Sauf.logserreur.ps1' -WhatIf
```

- Windows Sandbox launch:

```powershell
Start-Process '.\sandbox\sysadmin-main-validation.wsb'
```

## Workflow Rounds

1. Maintenance
   - Read this playbook first.
   - Map the exact script pair or helper surface before editing.
   - Edit nested `V7` first, then adapt nested `V5` only where compatibility or parity requires it.
   - Validate the changed scripts directly with `-WhatIf`.
2. Security and behavioral coverage
   - If work touches trust boundaries, path trust, reparse-point handling, publisher checks, output roots, or ACLs, apply the secure-by-default hardening patterns already used in this repo.
   - If work changes behavior or test depth, prefer behavioral Pester coverage over brittle string-output assertions.
   - Keep V7/V5 drift intentional and explicit; do not "normalize" differences that exist for compatibility unless the task calls for it.
3. Tooling validation
   - Run `tools\Invoke-PSScriptAnalyzer.ps1` when editing script logic, helpers, or validation tooling.
   - Run focused or full `Invoke-Pester` coverage when behavior, result objects, or helper surfaces change.
   - Keep local validation commands aligned with `.github/workflows/powershell-validation.yml`.
4. High-risk manual validation
   - Use `sandbox\sysadmin-main-validation.wsb` for risky manual validation of network reset/reboot, installer orphan move, broad cleanup, and similar scripts.
   - Run `-WhatIf` first inside the Sandbox and inspect any output under `artifacts/validation/`.
   - Only perform non-`WhatIf` execution when you are intentionally testing inside the disposable Sandbox environment.
5. Code-quality review
   - Have a critic review correctness, safety, regressions, and V7/V5 drift.
   - Require `PASS` or `REVISE`.
6. Change analysis
   - Use Git metadata for recent-commit or last-N-days analysis.
   - Do not substitute file timestamps for commit windows.

## Subagent Roles

- `sysadmin-orchestrator`: coordinates exploration, implementation, critique, and final reporting.
- `repo-explorer`: gathers canonical paths, validation commands, and script patterns without editing files.
- `script-implementer`: makes the smallest defensible code change, V7 first and V5 second.
- `code-critic`: returns `PASS` or `REVISE` with concrete risk-based findings.
- `playbook-librarian`: updates only the librarian-managed sections below.

## Known Pitfalls and Discoveries

- The canonical V7 Windows maintenance filenames now use ASCII names to match V5 and operator expectations:
  - `Nettoyage.Avance.Windows.Sauf.logserreur.ps1`
  - `Nettoyage.Complet.Caches.Windows.ps1`
- Imported files may carry `Zone.Identifier`; validation commands should keep `-ExecutionPolicy Bypass` even after local MOTW cleanup.
- In service-control scripts, restart should depend on whether this invocation actually stopped the service, not only on the initial service state.
- Generated validation logs belong in `artifacts/validation/`; do not reintroduce tracked root-level result files.
- The root validator is now only a wrapper. The nested validator is the source of truth.
- `tools\Invoke-PSScriptAnalyzer.ps1` writes to `artifacts/validation/psscriptanalyzer.txt` by default and only exits non-zero for error-severity findings.
- CI currently exports Pester results to `artifacts/validation/pester-results.xml` and uploads `artifacts/validation/` as the validation artifact.
- `sandbox\sysadmin-main-validation.wsb` maps the repo into `C:\Users\WDAGUtilityAccount\Desktop\sysadmin-main` as read-only with networking and vGPU disabled.
- Some V7 and V5 script pairs still have intentional differences in admin preview behavior or result fields; preserve them unless you are intentionally standardizing both sides.

## Improvement Notes

- 2026-03-20: Consolidated the repo around `PowerShell Script/V5` and `PowerShell Script/V7` and removed the duplicate root script trees.
- 2026-03-20: Standardized the canonical V7 Windows-maintenance cleanup filenames to ASCII.
- 2026-03-20: Moved validation output to `artifacts/validation/`, added repo-root `SKILL.md`, and aligned the playbook/skill surface to the one-tree layout.
- 2026-03-20: Added initial analyzer, Pester, Windows Sandbox, and CI entrypoints for future hardening work.
- 2026-03-22: Added repo-specific security-hardening and behavioral Pester skills and documented the multi-agent operating flow under `docs/`.
- 2026-03-22: Expanded the Windows validation workflow to include analyzer output, NUnit-style Pester results, trusted `-WhatIf` smoke checks, and Windows Sandbox guidance.
- Keep this section focused on durable repo guidance, not task-by-task narrative.
