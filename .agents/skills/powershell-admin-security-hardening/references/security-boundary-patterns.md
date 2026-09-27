# Security Boundary Patterns

## Checklist

1. Confirm script contract before hardening:
- `#Requires` values remain truthful per shell variant.
- `Set-StrictMode -Version 3.0` and `$ErrorActionPreference = 'Stop'` remain intact unless explicitly changed.
- Existing result object shape remains stable unless intentionally revised.

2. For elevated package execution:
- Validate signature status with `Get-AuthenticodeSignature`.
- Validate publisher against approved patterns.
- Fail closed when trust checks fail.

3. For directories and file outputs:
- Resolve output root from trusted location (`ProgramData` or profile-owned root).
- Ensure destination path is canonical and under allowed root.
- Apply restrictive ACLs when creating shared directories.
- Use unique per-run file names.

4. For delete/move operations:
- Enumerate with `LiteralPath` and explicit error handling.
- Skip reparse points.
- Reject operations escaping trusted root.

## Acceptance Criteria

1. No hardcoded `C:\Temp` defaults in hardened paths unless explicitly justified by task contract.
2. Reparse-point checks are present on recursive cleanup and quarantine moves.
3. Authenticode and publisher checks guard elevated installer execution.
4. WhatIf output remains usable and side-effect free.
5. V7-first changes are reflected in V5 with compatibility-safe syntax.
