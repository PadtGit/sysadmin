# sysadmin-main Playbook

## Project Snapshot

- This repo contains Windows sysadmin PowerShell scripts with mirrored PowerShell 7 and Windows PowerShell 5.1 variants.
- Treat `PowerShell Script/*` as the canonical working tree.
- Treat the root-level `V5/*` and `V7/*` folders as duplicate trees unless a task explicitly targets them.
- There is currently no `.git` directory, no `git.exe` on `PATH`, and no automated test harness in this workspace.
- Prefer small, reversible changes over bulk rewrites.

## Canonical Layout

- `PowerShell Script/V7/*`: primary implementation surface.
- `PowerShell Script/V5/*`: compatibility and backport surface after a V7 change.
- `PowerShell Script/Copy-V7ToV5.ps1`: bulk copy helper for the nested tree.
- `PowerShell Script/Invoke-V5-WhatIfValidation.ps1`: fixed-list validator for nested-tree V5 scripts.
- `Invoke-V5-WhatIfValidation.ps1`: recursive validator for the root-level duplicate `V5/*` and `V7/*` trees.

## Safety Invariants

- Preserve truthful `#Requires -Version ...` declarations for each script variant.
- Preserve `[CmdletBinding(SupportsShouldProcess = $true)]` on scripts that change system state.
- Preserve `Set-StrictMode -Version 3.0` and `$ErrorActionPreference = 'Stop'` unless the task explicitly changes them.
- Keep admin-only work gated so existing `-WhatIf` behavior remains usable without elevation when the script already follows that pattern.
- Keep exit-code behavior and structured result objects stable unless the task explicitly changes contract.
- Prefer minimal edits that preserve operator expectations.

## Validation Commands

- V7 targeted validation:

```powershell
& (Get-Command pwsh.exe).Source -NoProfile -File 'PowerShell Script\V7\<category>\<script>.ps1' -WhatIf
```

- V5 targeted validation:

```powershell
& "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File 'PowerShell Script\V5\<category>\<script>.ps1' -WhatIf
```

- Nested-tree helpers:
  - `PowerShell Script\Copy-V7ToV5.ps1` bulk-copies nested `V7` into nested `V5`; inspect the result before trusting it.
  - `PowerShell Script\Invoke-V5-WhatIfValidation.ps1` validates a fixed set of nested-tree V5 scripts.
- Duplicate-tree helper:
  - Root `Invoke-V5-WhatIfValidation.ps1` validates root-level `V5/*` and `V7/*`, not the canonical nested tree.

## Workflow Rounds

1. Maintenance
   - Read this playbook first.
   - Map the exact script pair.
   - Edit nested `V7` first, then adapt nested `V5` only where compatibility or parity requires it.
   - Validate the changed scripts directly with `-WhatIf`.
2. Code-quality review
   - Have a critic review correctness, safety, regressions, and V7/V5 drift.
   - Require `PASS` or `REVISE`.
3. Change analysis
   - Only available after Git metadata and `git.exe` are present.
   - Block last-48h and last-4-day commit-window requests until then.

## Subagent Roles

- `sysadmin-orchestrator`: coordinates exploration, implementation, critique, and final reporting.
- `repo-explorer`: gathers canonical paths, validation commands, and script patterns without editing files.
- `script-implementer`: makes the smallest defensible code change, V7 first and V5 second.
- `code-critic`: returns `PASS` or `REVISE` with concrete risk-based findings.
- `playbook-librarian`: updates only the librarian-managed sections below.

## Git-Dependent Workflows

- Disabled until a real Git checkout exists and `git.exe` is available.
- Do not substitute file timestamps for commit windows.
- The following requests should currently block with a Git-required explanation:
  - review recent commits from the last 48 hours
  - compare all changes from the last 4 days
  - benchmark or performance analysis anchored to recent commits

The playbook-librarian may update only the two sections below during normal task runs. Other sections change only when repo structure or workflow policy changes.

## Known Pitfalls and Discoveries

- Duplicate script trees exist at repo root and under `PowerShell Script/`; treat the nested tree as canonical.
- In service-control scripts, restart should depend on whether this invocation actually stopped the service, not only on the initial service state.
- The root-level duplicate V7 printer cleanup script can still carry stale operator guidance. Do not fix duplicate trees unless the task explicitly targets them.
- The repo has two validator scripts with different scopes. Confirm that the validator matches the tree you edited before trusting its result.
- Windows PowerShell 5.1 validation may require `-ExecutionPolicy Bypass` in this environment even for `-WhatIf` runs.
- Some V7 and V5 script pairs have minor drift in returned object fields or messages; preserve behavior unless you are intentionally standardizing both sides.

## Improvement Notes

- 2026-03-20: Added repo-local skill and project-scoped subagent role files for staged maintenance, critic review, and Git-gated change analysis.
- 2026-03-20: Standardized the canonical printer cleanup result shape and guarded service restart on actual stop, not initial state.
- Keep this section focused on durable repo guidance, not task-by-task narrative.
