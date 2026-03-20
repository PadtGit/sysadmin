---
name: maintain-windows-admin-powershell
description: Maintain and review this repository's Windows system administration PowerShell scripts. Use when Codex needs to edit or audit files under PowerShell Script/*, adapt a PowerShell 7 change back to PowerShell 5.1, preserve WhatIf and admin-safe behavior, coordinate implementation and critic passes, or update AGENTS.md with stable repo discoveries after meaningful work.
---

# Maintain Windows Admin Powershell

## Overview

Maintain this repo with a staged workflow that starts from the canonical nested script tree, keeps PowerShell 7 and PowerShell 5.1 variants aligned, validates WhatIf-safe behavior, and records lasting repo knowledge in `AGENTS.md`.

## Start Here

1. Read `AGENTS.md` before making changes.
2. Treat `PowerShell Script/*` as canonical.
3. Treat the root-level `V5/*` and `V7/*` trees as duplicates unless the user explicitly asks to work there.
4. Prefer narrow, behavior-preserving edits over bulk rewrites.

## Workflow

### Round 1: Maintenance

- Map the exact category and script pair before editing.
- Update `PowerShell Script/V7` first.
- Adapt `PowerShell Script/V5` second only where compatibility or parity requires it.
- Preserve `#Requires`, `[CmdletBinding(SupportsShouldProcess = $true)]`, `Set-StrictMode -Version 3.0`, `$ErrorActionPreference = 'Stop'`, admin gating, and current result-object shape unless the task explicitly changes them.
- Keep `-WhatIf` usable whenever the existing script already supports that pattern.
- Validate the changed scripts directly with the commands from `AGENTS.md`. Use helper scripts only when their target tree matches the files you changed.

### Round 2: Code-Quality Review

- Hand the changed files or diff to the critic agent after implementation.
- Require a top-line `PASS` or `REVISE`.
- Treat correctness, safety, regressions, V7/V5 drift, and broken validation as review blockers.
- If the critic returns `REVISE`, fix only the concrete issues with behavioral or safety impact, then rerun focused validation.

### Round 3: Change Analysis

- Only do recent-commit or last-N-days analysis when `.git` metadata exists and `git.exe` is available.
- Do not substitute file timestamps for commit windows.
- If Git is unavailable, stop and say that the requested workflow is Git-gated in this repo.

## Agent Handoffs

- Let the orchestrator sequence exploration, implementation, critique, and playbook maintenance.
- Let `repo-explorer` gather canonical paths, validation commands, and existing script patterns without editing files.
- Let `script-implementer` own minimal code changes once the task is understood.
- Let `code-critic` return `PASS` or `REVISE` with concrete findings.
- Let `playbook-librarian` update only the librarian-managed sections of `AGENTS.md`.

## Output Expectations

- Summaries should state the files changed, the validation command or check run, the critic result, and any new durable playbook note.
- If no stable repo knowledge was discovered, do not force an `AGENTS.md` edit.
- Do not promise automated test-gap discovery, new tests, `$yeet` PR workflows, or commit-window benchmarking while this repo lacks a Git checkout and test harness.
