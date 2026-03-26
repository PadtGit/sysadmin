---
name: behavioral-pester-admin-scripts
description: Build behavior-focused Pester coverage for this repository's Windows admin PowerShell scripts. Use when converting string or presence assertions into mocked behavioral tests, validating WhatIf safety, and proving no unintended side effects from file, service, transcript, or installer operations in this Windows PowerShell 5.1 branch.
---

# Behavioral Pester Admin Scripts

## Overview

Upgrade tests from static string checks to behavior assertions that prove safety boundaries and side-effect control in this Windows PowerShell 5.1 branch.

## Core Workflow

1. Identify the contract under test: WhatIf output, return object fields, side effects, and trust boundary behavior.
2. Isolate external operations with mocks (`Get-AuthenticodeSignature`, `Move-Item`, `Remove-Item`, `Start-Transcript`, service cmdlets).
3. Assert behavior using call counts, parameters, and branch outcomes.
4. Keep tests deterministic and focused on one behavior boundary per example.
5. Prefer targeted branch-local assertions over broad output matching.

## Behavioral Patterns

1. WhatIf safety:
- Assert no mutating command executes when preview mode is active.
- Verify returned object still reports planned actions and reasons.

2. Trust checks:
- Mock `Get-AuthenticodeSignature` and publisher results to assert fail-closed behavior.
- Assert installer execution path is skipped when trust fails.

3. Filesystem side effects:
- Mock `Move-Item` and `Remove-Item`.
- Assert calls only occur for trusted canonical paths.
- Assert reparse-point entries are ignored.

4. Service and transcript behavior:
- Mock service stop/start operations and assert restart only when this run stopped the service.
- Mock transcript operations and assert secure output path behavior.

## Shell-Specific Guidance

1. Use `Invoke-WhatIfScriptObject` from `tests/TestHelpers.ps1` for preview-contract validation.
2. Keep tests parallel only where multiple scripts share one behavior contract inside this branch.
3. Prefer explicit mock scopes and stable parameter assertions over brittle string-output checks.

## Forward-Test Prompts

1. Behavior rewrite scenario:
- "Use `$behavioral-pester-admin-scripts to rewrite this test into behavioral mocks that prove WhatIf safety and side-effect suppression."

2. Service or filesystem scenario:
- "Use `$behavioral-pester-admin-scripts to build a behavioral test that mocks file or service operations and verifies WhatIf behavior without unintended mutations."

## References

Load [behavioral-test-patterns.md](references/behavioral-test-patterns.md) for a conversion checklist and acceptance matrix.
