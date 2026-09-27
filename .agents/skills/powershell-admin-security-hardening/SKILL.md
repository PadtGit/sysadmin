---
name: powershell-admin-security-hardening
description: Apply secure-by-default hardening patterns to this repo's Windows admin PowerShell scripts. Use when changes involve Authenticode or trusted-publisher validation, output-root hardening, restrictive ACL setup, canonical path trust checks, or reparse-point defenses across V7 and V5 script pairs.
---

# PowerShell Admin Security Hardening

## Overview

Harden script behavior around trust boundaries while preserving existing repo contracts: truthful `#Requires`, `SupportsShouldProcess`, strict mode, stable result objects, and WhatIf-safe admin behavior.

## Core Workflow

1. Map the exact V7 and V5 script pair and current contract before editing.
2. Apply hardening in V7 first.
3. Backport equivalent behavior to V5 with compatible syntax.
4. Validate with focused `-WhatIf` runs and targeted Pester coverage.
5. Summarize boundary decisions and any intentional V7/V5 differences.

## Security Boundary Patterns

1. Package trust and elevated execution:
- Validate package signatures with `Get-AuthenticodeSignature` before execution.
- Require trusted publisher allowlist matching (subject/pattern based).
- Refuse execution on invalid or unknown signatures.

2. Output and quarantine root safety:
- Prefer roots under `ProgramData` or explicit user profile roots over `C:\Temp`.
- Use per-run unique names to prevent clobbering and path planting.
- Apply restrictive ACLs when creating shared directories.

3. Path trust checks:
- Canonicalize paths before action and enforce allowed-root prefix checks.
- Reject untrusted destination roots and root-level fallbacks.
- Use `LiteralPath` for all file operations.

4. Reparse-point defense:
- Detect and skip reparse points for recursive delete/move operations.
- Never follow links outside the trusted root boundary.

5. Safe operation contracts:
- Preserve `SupportsShouldProcess` for mutating scripts.
- Keep WhatIf previews truthful and side-effect free.
- Preserve result object shape unless the task explicitly changes the contract.

## Validation Expectations

1. Run focused `-WhatIf` checks for each modified script variant.
2. Add or update regression tests for the exact boundary being hardened.
3. Confirm no return to weak defaults such as root-level temp output paths.

## Forward-Test Prompts

Use these for realistic forward-testing without leaking answers:

1. Adobe trust scenario:
- "Use $powershell-admin-security-hardening to harden the Adobe installer refresh scripts so elevated execution only occurs for trusted signed packages and logs use secure roots."

2. Cleanup/orphan boundary scenario:
- "Use $powershell-admin-security-hardening to harden recursive cleanup and orphan-move scripts against untrusted destinations and reparse points while preserving WhatIf behavior."

## References

Load [security-boundary-patterns.md](references/security-boundary-patterns.md) for implementation checklist details and acceptance criteria.
