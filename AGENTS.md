# sysadmin-main Playbook

## Project Snapshot

- This repo contains Windows sysadmin PowerShell scripts only. Keep AutoHotkey automation in a separate repository.
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
- `.agents/skills/*`: repo-local maintenance, security-hardening, and behavioral Pester skills.
- `.codex/agents/*.toml`: repo-local manager and specialist agent configs for workflow execution.
- `tests/*`: Pester smoke and contract tests.
- `tools/Invoke-PSScriptAnalyzer.ps1`: analyzer runner.
- `tools/PSScriptAnalyzerSettings.psd1`: canonical analyzer settings for repo-wide validation.
- `.github/workflows/powershell-validation.yml`: CI entrypoint for analyzer, Pester, trusted `-WhatIf` smoke checks, and validation artifact upload.
- `sandbox/sysadmin-main-validation.wsb`: disposable Windows Sandbox profile that maps the repo read-only into `C:\Users\WDAGUtilityAccount\Desktop\sysadmin-main`, disables networking and vGPU, and opens PowerShell at that path.
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
pwsh -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PWD 'tools\Invoke-PSScriptAnalyzer.ps1') `
  -Path . `
  -Recurse `
  -SettingsPath (Join-Path $PWD 'tools\PSScriptAnalyzerSettings.psd1') `
  -EnableExit `
  -ExitCodeMode AllDiagnostics
```

- Basic Pester helper:

```powershell
Invoke-Pester -Path .\tests
```

- CI-style Pester with NUnit XML output:

```powershell
$resultPath = Join-Path $PWD 'artifacts\validation\pester-results.xml'
New-Item -ItemType Directory -Force -Path (Split-Path -Path $resultPath -Parent) | Out-Null
$config = New-PesterConfiguration
$config.Run.Path = '.\tests'
$config.Output.Verbosity = 'Detailed'
$config.Run.Exit = $true
$config.TestResult.Enabled = $true
$config.TestResult.OutputPath = $resultPath
$config.TestResult.OutputFormat = 'NUnitXml'
Invoke-Pester -Configuration $config
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

- GitHub workflow dispatch:

```powershell
gh workflow run "PowerShell Validation" --repo PadtGit/sysadmin
$runId = gh run list --workflow "PowerShell Validation" --repo PadtGit/sysadmin --limit 1 --json databaseId --jq '.[0].databaseId'
gh run watch $runId --repo PadtGit/sysadmin --exit-status
```

## Workflow Rounds

1. Explore
   - Read this playbook first.
   - Let `repo-explorer` map the exact script pair or workflow surface, validation commands, sandbox expectations, and current drift before editing.
2. Implement
   - Let `script-implementer` make the smallest defensible patch.
   - Edit nested `V7` first, then adapt nested `V5` only where compatibility or parity requires it.
3. Optional security specialist
   - Use `security-boundary-hardener` when work touches trust boundaries, path trust, reparse-point handling, publisher checks, output roots, or ACLs.
   - Keep V7/V5 drift intentional and explicit; do not "normalize" differences that exist for compatibility unless the task calls for it.
4. Optional behavioral Pester specialist
   - Use `behavioral-pester-specialist` when work changes behavior, result objects, WhatIf safety, or test depth.
   - Prefer behavioral Pester coverage over brittle string-output assertions.
5. Validation runner
   - Let `validation-runner` run the standard repo-wide analyzer command, the CI-style Pester configuration, the trusted smoke checks, and the sandbox sanity check without editing tracked files.
   - Keep local validation commands aligned with `.github/workflows/powershell-validation.yml`.
6. Code-quality review
   - Have `code-critic` review correctness, safety, regressions, validation gaps, workflow drift, and V7/V5 drift.
   - Require `PASS` or `REVISE`.
7. Playbook sync
   - Have `playbook-librarian` sync `AGENTS.md` and `docs/*` when workflow wording or durable repo knowledge changed.
8. GitHub workflow dispatch
   - After local validation and review pass, dispatch `PowerShell Validation` with `gh workflow run "PowerShell Validation" --repo PadtGit/sysadmin` and watch the latest run to completion.
9. Change analysis
   - Use Git metadata for recent-commit or last-N-days analysis.
   - Do not substitute file timestamps for commit windows.

## Agent Roles

- `sysadmin-orchestrator` (`gpt-5.4`, `high`, `workspace-write`): manager-pattern controller that sequences exploration, implementation, specialist delegation, local validation, review, documentation sync, and final workflow dispatch.
- `repo-explorer` (`gpt-5.4-mini`, `medium`, `read-only`): gathers canonical paths, workflow surfaces, validation commands, sandbox expectations, and current drift without editing files.
- `script-implementer` (`gpt-5.3-codex`, `high`, `workspace-write`): makes the smallest defensible script, workflow, or documentation change when a narrower specialist does not own that surface.
- `validation-runner` (`gpt-5.3-codex`, `medium`, `workspace-write`): runs analyzer, Pester, smoke checks, sandbox sanity, GitHub workflow dispatch, and result collection without editing tracked files.
- `security-boundary-hardener` (`gpt-5.3-codex`, `high`, `workspace-write`): owns trust-boundary and secure-by-default edits in `PowerShell Script/*`.
- `behavioral-pester-specialist` (`gpt-5.3-codex`, `high`, `workspace-write`): owns `tests/*` and WhatIf or behavior-focused Pester coverage.
- `code-critic` (`gpt-5.4`, `high`, `read-only`): returns `PASS` or `REVISE` with concrete risk-based findings across code, docs, and validation evidence.
- `playbook-librarian` (`gpt-5.4-mini`, `medium`, `workspace-write`): syncs `AGENTS.md` and `docs/*` when workflow wording or durable repo knowledge changes.

## Known Pitfalls and Discoveries

- This repo is PowerShell-only; keep AutoHotkey automation in a separate repository instead of reintroducing an AutoHotkey subtree under this tree.
- The canonical V7 Windows maintenance filenames now use ASCII names to match V5 and operator expectations:
  - `Nettoyage.Avance.Windows.Sauf.logserreur.ps1`
  - `Nettoyage.Complet.Caches.Windows.ps1`
- Imported files may carry `Zone.Identifier`; validation commands should keep `-ExecutionPolicy Bypass` even after local MOTW cleanup.
- In service-control scripts, restart should depend on whether this invocation actually stopped the service, not only on the initial service state.
- Generated validation logs belong in `artifacts/validation/`; do not reintroduce tracked root-level result files.
- The root validator is now only a wrapper. The nested validator is the source of truth.
- The standard analyzer baseline is the repo-wide recursive command using `tools\Invoke-PSScriptAnalyzer.ps1` with `tools\PSScriptAnalyzerSettings.psd1`, `-EnableExit`, and `-ExitCodeMode AllDiagnostics`.
- Pin PSScriptAnalyzer to version `1.25.0` for both local validation and CI; do not float to newer versions without an intentional repo update.
- `tools\Invoke-PSScriptAnalyzer.ps1` writes to `artifacts/validation/psscriptanalyzer.txt` by default.
- CI currently exports Pester results to `artifacts/validation/pester-results.xml` and uploads `artifacts/validation/` as the validation artifact.
- Pester 5 does not support combining `-CI` with `-Configuration`; use `New-PesterConfiguration` for CI-style NUnit XML output.
- `sandbox\sysadmin-main-validation.wsb` maps the repo into `C:\Users\WDAGUtilityAccount\Desktop\sysadmin-main` as read-only with networking and vGPU disabled.
- Workflow-surface changes under `.codex/agents/`, `.agents/skills/`, and `sandbox/` should trigger the PowerShell Validation workflow so docs, agents, and validation stay aligned.
- The preferred validation finish is local analyzer, Pester, smoke, and sandbox checks first, then `gh workflow run "PowerShell Validation" --repo PadtGit/sysadmin` for remote confirmation.
- Some V7 and V5 script pairs still have intentional differences in admin preview behavior or result fields; preserve them unless you are intentionally standardizing both sides.

## Improvement Notes

- 2026-03-20: Consolidated the repo around `PowerShell Script/V5` and `PowerShell Script/V7` and removed the duplicate root script trees.
- 2026-03-20: Standardized the canonical V7 Windows-maintenance cleanup filenames to ASCII.
- 2026-03-20: Moved validation output to `artifacts/validation/`, added repo-root `SKILL.md`, and aligned the playbook/skill surface to the one-tree layout.
- 2026-03-20: Added initial analyzer, Pester, Windows Sandbox, and CI entrypoints for future hardening work.
- 2026-03-22: Added repo-specific security-hardening and behavioral Pester skills and documented the multi-agent operating flow under `docs/`.
- 2026-03-22: Expanded the Windows validation workflow to include analyzer output, NUnit-style Pester results, trusted `-WhatIf` smoke checks, and Windows Sandbox guidance.
- 2026-03-23: Standardized analyzer validation on the repo-wide recursive command with explicit settings and `AllDiagnostics` exit handling.
- 2026-03-23: Removed the tracked AutoHotkey subtree so `sysadmin-main` stays PowerShell-only while AutoHotkey work moves to its own repo.
- 2026-03-23: Expanded the repo-local agent roster to a manager-pattern workflow with dedicated validation, security-boundary, and behavioral Pester specialists.
- 2026-03-23: Extended the PowerShell Validation workflow triggers to cover `.codex/agents/`, `.agents/skills/`, and `sandbox/`, and standardized final remote confirmation via `gh workflow run`.
- Keep this section focused on durable repo guidance, not task-by-task narrative.
