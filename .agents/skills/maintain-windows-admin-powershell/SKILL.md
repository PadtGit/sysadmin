---
name: maintain-windows-admin-powershell
description: Maintain and review this repository's Windows system administration PowerShell scripts. Use when Codex needs to edit or audit files under PowerShell Script/*, adapt a PowerShell 7 change back to PowerShell 5.1, preserve WhatIf and admin-safe behavior, coordinate implementation and critic passes, delegate security hardening to $powershell-admin-security-hardening, delegate behavioral test design to $behavioral-pester-admin-scripts, or update AGENTS.md with stable repo discoveries after meaningful work.
---

# Maintain Windows Admin Powershell

## Overview

Maintain this repo with a staged workflow that starts from the canonical nested script tree, keeps PowerShell 7 and PowerShell 5.1 variants aligned, validates WhatIf-safe behavior, and records lasting repo knowledge in `AGENTS.md`.

## Start Here

1. Read `AGENTS.md` before making changes.
2. Treat `PowerShell Script/*` as canonical.
3. Prefer narrow, behavior-preserving edits over bulk rewrites.

## Delegated Skills

1. Use `$powershell-admin-security-hardening` when work touches trust boundaries:
- Authenticode/publisher validation.
- Secure output roots and ACL hardening.
- Canonical path enforcement and reparse-point defense.

2. Use `$behavioral-pester-admin-scripts` when work touches test depth:
- Converting string/presence checks to behavioral mocks.
- Verifying WhatIf safety and side-effect suppression.
- Keeping V7 and V5 behavioral tests aligned.

## Workflow

### Round 1: Maintenance

- Map the exact category and script pair before editing.
- Update `PowerShell Script/V7` first.
- Adapt `PowerShell Script/V5` second only where compatibility or parity requires it.
- Preserve `#Requires`, `[CmdletBinding(SupportsShouldProcess = $true)]`, `Set-StrictMode -Version 3.0`, `$ErrorActionPreference = 'Stop'`, admin gating, and current result-object shape unless the task explicitly changes them.
- Keep `-WhatIf` usable whenever the existing script already supports that pattern.
- Validate the changed scripts directly with the commands from `AGENTS.md`. Use the standard analyzer command with `tools\Invoke-PSScriptAnalyzer.ps1`, `-ExecutionPolicy Bypass`, `-Path .`, `-Recurse`, `tools\PSScriptAnalyzerSettings.psd1`, and `-ExitCodeMode AllDiagnostics` when analyzer coverage is part of the task. Use helper scripts only when their target tree matches the files you changed.

### Round 2: Security and Behavioral Tests

- If security boundaries changed, run the `$powershell-admin-security-hardening` checklist before finishing edits.
- If tests are added or modified, run the `$behavioral-pester-admin-scripts` checklist before final validation.
- Keep changes minimal and reversible; avoid broad rewrites unless explicitly requested.

### Round 3: Code-Quality Review

- Hand the changed files or diff to the critic agent after implementation.
- Require a top-line `PASS` or `REVISE`.
- Treat correctness, safety, regressions, V7/V5 drift, and broken validation as review blockers.
- If the critic returns `REVISE`, fix only the concrete issues with behavioral or safety impact, then rerun focused validation.

### Round 4: Change Analysis

- Use Git metadata for recent-commit or last-N-days analysis.
- Do not substitute file timestamps for commit windows.

## Follow-On Roadmap

1. `v7-v5-parity-and-backporting`
2. `validation-and-ci-design-for-powershell-ops`
3. `path-trust-filesystem-boundaries` (split out when security-boundary guidance becomes too large)

## Agent Handoffs

- Let the orchestrator sequence exploration, implementation, critique, and playbook maintenance.
- Let `repo-explorer` gather canonical paths, validation commands, and existing script patterns without editing files.
- Let `script-implementer` own minimal code changes once the task is understood.
- Let `code-critic` return `PASS` or `REVISE` with concrete findings.
- Let `playbook-librarian` update only the librarian-managed sections of `AGENTS.md`.

## Output Expectations

- Summaries should state the files changed, the validation command or check run, the critic result, and any new durable playbook note.
- If no stable repo knowledge was discovered, do not force an `AGENTS.md` edit.
- Generated validation output belongs under `artifacts/validation/`, not in tracked repo result files.
