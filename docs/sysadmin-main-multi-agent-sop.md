# sysadmin-main Multi-Agent SOP

## Why This Shape

- Use a manager pattern: `sysadmin-orchestrator` stays the single user-facing controller and delegates bounded work to specialist agents.
- Use `gpt-5.4` for orchestration and final review, `gpt-5.4-mini` for bounded read-heavy discovery and doc-sync roles, and `gpt-5.3-codex` for coding-heavy implementation and validation specialists.
- Keep this SOP, `AGENTS.md`, `.codex/agents/*.toml`, and `.github/workflows/powershell-validation.yml` aligned whenever the workflow changes.

## Repo Ground Rules

- Canonical scripts live under `PowerShell Script/`.
- `Invoke-WhatIfValidation.ps1` is the branch-level validator entrypoint.
- Generated validation output belongs under `artifacts/validation/`.
- `SKILL.md` at the repo root is the human and agent entrypoint; the deeper repo-specific workflow remains under `.agents/skills/maintain-windows-admin-powershell/SKILL.md`.
- This branch supports PowerShell 7 only.
- Preserve `Set-StrictMode -Version 3.0`, `$ErrorActionPreference = 'Stop'`, and `SupportsShouldProcess`.
- Prefer safe `-WhatIf` preview behavior over hard admin-only preview blocks where the script can truthfully support preview without elevation.
- Keep result objects compact and structured. Avoid noisy transcript-style output by default.

## Agent Matrix

| Agent | Model | Reasoning | Sandbox | Write Scope | Primary Responsibility |
| --- | --- | --- | --- | --- | --- |
| `sysadmin-orchestrator` | `gpt-5.4` | `high` | `workspace-write` | Any surface when acting directly, but prefers delegation | Single controller for sequencing, synthesis, escalation, and final workflow dispatch |
| `repo-explorer` | `gpt-5.4-mini` | `medium` | `read-only` | None | Repo mapping, workflow-surface discovery, and evidence gathering |
| `script-implementer` | `gpt-5.3-codex` | `high` | `workspace-write` | Broad implementation surface | Smallest defensible script, workflow, or documentation patch |
| `validation-runner` | `gpt-5.3-codex` | `medium` | `workspace-write` | Artifacts only; no tracked edits | Local analyzer, Pester, smoke checks, sandbox sanity, and GitHub workflow execution |
| `security-boundary-hardener` | `gpt-5.3-codex` | `high` | `workspace-write` | `PowerShell Script/*` trust-boundary slices only | Publisher, signature, path-trust, ACL, output-root, and reparse-point hardening |
| `behavioral-pester-specialist` | `gpt-5.3-codex` | `high` | `workspace-write` | `tests/*` only | Behavior-focused Pester coverage and WhatIf safety tests |
| `code-critic` | `gpt-5.4` | `high` | `read-only` | None | Final `PASS` or `REVISE` review over code, docs, and validation evidence |
| `playbook-librarian` | `gpt-5.4-mini` | `medium` | `workspace-write` | `AGENTS.md` and `docs/*` | Workflow-doc synchronization and durable repo guidance upkeep |

## Current High-Risk Areas

- Service-control scripts that stop and restart `Spooler` or `wuauserv`
- Network reset/reboot scripts
- Broad Windows cleanup scripts
- Installer orphan move scripts

## Round Order

1. Explore
   - `repo-explorer` maps the exact file or workflow surface, current drift, and required validation commands.
2. Implement
   - `script-implementer` makes the smallest patch while keeping current-state docs and workflow surfaces aligned.
3. Optional security specialist
   - Use `security-boundary-hardener` when the task touches publisher checks, signatures, output roots, ACLs, canonical path enforcement, or reparse-point handling.
4. Optional behavioral Pester specialist
   - Use `behavioral-pester-specialist` when tests, WhatIf behavior, or result contracts change.
5. Validate locally
   - `validation-runner` executes the analyzer command from `AGENTS.md`, the CI-style Pester configuration, the trusted local smoke checks, and a sandbox sanity check against the current `.wsb` file and docs.
6. Critic review
   - `code-critic` returns `PASS` or `REVISE` with only concrete risk-based findings.
7. Playbook sync
   - `playbook-librarian` updates `AGENTS.md` and `docs/*` when workflow wording or durable repo knowledge drifted during the task.
8. Dispatch GitHub workflow
   - Run the repo workflow only after local validation and critic review pass.

## Validation Surface

- Use the repo-wide recursive analyzer command with `tools\Invoke-PSScriptAnalyzer.ps1`, `tools\PSScriptAnalyzerSettings.psd1`, `-EnableExit`, and `-ExitCodeMode AllDiagnostics`.
- Use the CI-style Pester configuration that writes results to `artifacts/validation/pester-results.xml`.
- Keep smoke checks focused on the trusted `-WhatIf` commands documented in `AGENTS.md`.
- Use `sandbox/sysadmin-main-validation.wsb` as the disposable validation shell for risky scripts. The profile maps the repo read-only, disables networking and vGPU, and opens PowerShell at `C:\Users\WDAGUtilityAccount\Desktop\sysadmin-main`.
- Publish validation and test artifacts from `artifacts/validation/`.

