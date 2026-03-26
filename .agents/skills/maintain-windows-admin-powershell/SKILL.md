---
name: maintain-windows-admin-powershell
description: Maintain and review this repository's Windows system administration PowerShell scripts. Use when Codex needs to edit or audit files under PowerShell Script/*, preserve WhatIf and admin-safe behavior, coordinate implementation and critic passes, delegate security hardening to $powershell-admin-security-hardening, delegate behavioral test design to $behavioral-pester-admin-scripts, or update AGENTS.md with stable repo discoveries after meaningful work.
---

# Maintain Windows Admin Powershell

## Overview

Maintain this Windows PowerShell 5.1 branch with a manager-pattern workflow that starts from the canonical script tree, validates WhatIf-safe behavior locally and in GitHub Actions, and records lasting repo knowledge in `AGENTS.md` and `docs/*`.

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
- Converting string or presence checks into behavioral mocks.
- Verifying WhatIf safety and side-effect suppression.
- Keeping branch behavior explicit and test-backed.

## Workflow

### Round 1: Exploration

- Have `repo-explorer` map the exact script or workflow surface before editing.
- Gather helper scripts, validation commands, workflow triggers, sandbox expectations, and any current drift that matters to the task.

### Round 2: Implementation

- Have `script-implementer` update the relevant files under `PowerShell Script/*`.
- For workflow-only tasks, keep `AGENTS.md`, `docs/*`, `.codex/agents/*.toml`, `.agents/skills/*`, and `.github/workflows/*` aligned in the same change set.
- Preserve `#Requires`, `[CmdletBinding(SupportsShouldProcess = $true)]`, `Set-StrictMode -Version 3.0`, `$ErrorActionPreference = 'Stop'`, admin gating, and current result-object shape unless the task explicitly changes them.
- Keep `-WhatIf` usable whenever the existing script already supports that pattern.

### Round 3: Optional Security Specialist

- If trust boundaries changed, hand the exact boundary slice to `security-boundary-hardener` when available.
- Otherwise run the `$powershell-admin-security-hardening` checklist before finishing edits.

### Round 4: Optional Behavioral Pester Specialist

- If tests, WhatIf behavior, or result contracts changed, hand `tests/*` to `behavioral-pester-specialist` when available.
- Otherwise run the `$behavioral-pester-admin-scripts` checklist before final validation.
- Keep changes minimal and reversible; avoid broad rewrites unless explicitly requested.

### Round 5: Validation

- Have `validation-runner` execute the repo-wide analyzer command, the CI-style Pester configuration, the trusted local `-WhatIf` smoke checks, and the Windows Sandbox sanity check described in `AGENTS.md`.
- After local validation passes, dispatch `gh workflow run "PowerShell Validation" --repo PadtGit/sysadmin --ref Powershell.5` and watch the latest run to completion.

### Round 6: Code-Quality Review

- Hand the changed files or diff to the critic agent after implementation.
- Require a top-line `PASS` or `REVISE`.
- Treat correctness, safety, regressions, and broken validation as review blockers.
- If the critic returns `REVISE`, fix only the concrete issues with behavioral or safety impact, then rerun focused validation.

### Round 7: Playbook Sync and Change Analysis

- Have `playbook-librarian` sync `AGENTS.md` and `docs/*` when workflow wording or durable repo knowledge changed.
- Use Git metadata for recent-commit or last-N-days analysis.
- Do not substitute file timestamps for commit windows.

## Follow-On Roadmap

1. `validation-and-ci-design-for-powershell-ops`
2. `path-trust-filesystem-boundaries`

## Agent Handoffs

- Let the orchestrator stay the single user-facing controller and sequence exploration, implementation, validation, critique, playbook maintenance, and workflow dispatch.
- Let `repo-explorer` gather canonical paths, validation commands, and existing script patterns without editing files.
- Let `script-implementer` own minimal code, workflow, and documentation changes once the task is understood.
- Let `validation-runner` own analyzer, Pester, smoke-check, sandbox, and GitHub workflow execution without editing tracked files.
- Let `security-boundary-hardener` own only trust-boundary edits in `PowerShell Script/*`.
- Let `behavioral-pester-specialist` own only `tests/*` and behavior-focused Pester coverage.
- Let `code-critic` return `PASS` or `REVISE` with concrete findings across code, docs, and validation evidence.
- Let `playbook-librarian` sync `AGENTS.md` and `docs/*` when workflow guidance drifts.

## Output Expectations

- Summaries should state the files changed, the local validation checks run, the GitHub workflow dispatch result, the critic result, and any new durable playbook note.
- If no stable repo knowledge was discovered, do not force an `AGENTS.md` edit.
- Generated validation output belongs under `artifacts/validation/`, not in tracked repo result files.
