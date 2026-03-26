---
name: behavioral-pester-admin-scripts
description: Build behavior-focused Pester coverage for this repo's admin scripts. Use when converting string or presence assertions into mocked behavioral tests, validating WhatIf safety, checking shell-specific behavior for V7 and V5, and proving no unintended side effects from file, service, transcript, or installer operations.
---

# Behavioral Pester Admin Scripts

## Overview

Upgrade tests from static string checks to behavior assertions that prove safety boundaries and side-effect control in both PowerShell 7 and Windows PowerShell 5.1.

## Core Workflow

1. Identify contract under test: WhatIf output, return object fields, side effects, and trust boundary behavior.
2. Isolate external operations with mocks (`Get-AuthenticodeSignature`, `Move-Item`, `Remove-Item`, `Start-Transcript`, service cmdlets).
3. Assert behavior using call counts, parameters, and branch outcomes.
4. Cover both V7 and V5 variants when parity is expected.
5. Keep tests deterministic and focused on one behavior boundary per example.

## Behavioral Patterns

1. WhatIf safety:
- Assert no mutating command executes when preview mode is active.
- Verify returned object still reports planned actions and reasons.

2. Trust checks:
- Mock signature and publisher results to assert fail-closed behavior.
- Assert installer execution path is skipped when trust fails.

3. Filesystem side effects:
- Mock `Move-Item` and `Remove-Item`.
- Assert calls only occur for trusted canonical paths.
- Assert reparse-point entries are ignored.

4. Service and transcript behavior:
- Mock service stop/start operations and assert restart only when this run stopped the service.
- Mock transcript operations and assert secure output path behavior.

## Shell-Specific Guidance

1. Use `Invoke-WhatIfScriptObject` from `tests/TestHelpers.ps1` when validating cross-shell preview contracts.
2. Keep V5 and V7 test files parallel where behavior should match.
3. Prefer explicit mock scopes and stable parameter assertions to avoid shell-version drift.

## Forward-Test Prompts

Use these prompts for realistic forward-testing:

1. V7 conversion scenario:
- "Use $behavioral-pester-admin-scripts to rewrite this V7 string-contract test into behavioral mocks that prove WhatIf safety and side-effect suppression."

2. V5 shell-specific scenario:
- "Use $behavioral-pester-admin-scripts to build a V5 behavioral test that mocks file or service operations and verifies shell-specific WhatIf behavior without unintended mutations."

## References

Load [behavioral-test-patterns.md](references/behavioral-test-patterns.md) for a conversion checklist and acceptance matrix.
