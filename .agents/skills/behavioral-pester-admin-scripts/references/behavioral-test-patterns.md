# Behavioral Test Patterns

## Conversion Checklist

1. Capture current contract
- Identify the exact safety boundary and expected output fields.
- Identify commands that must not run under WhatIf.

2. Replace static checks
- Convert broad regex checks into mock-driven behavior assertions.
- Assert command calls, parameters, and non-calls.

3. Validate side-effect boundaries
- Mock mutating cmdlets (`Move-Item`, `Remove-Item`, service cmdlets).
- Assert no unintended mutation under preview conditions.

4. Validate trust logic
- Mock `Get-AuthenticodeSignature` and publisher checks.
- Assert installer execution is blocked when trust is invalid.

## Scenario Matrix

1. Adobe trust hardening tests:
- Invalid signature: installer path is not executed.
- Unknown publisher: installer path is not executed.
- Valid signature and publisher: execution path is reachable under non-WhatIf conditions.

2. Cleanup/orphan boundary tests:
- Reparse-point item: skipped and not removed/moved.
- Destination outside trusted root: operation blocked.
- Trusted destination and normal item: operation proceeds only when ShouldProcess allows.

3. Service behavior tests:
- Service already stopped externally: no unconditional restart.
- Service stopped by current invocation: restart is attempted when ShouldProcess allows.

## Acceptance Criteria

1. Tests assert behavior and side effects, not only static string presence.
2. WhatIf mode protects mutating operations in each covered boundary.
3. Tests cover the supported branch runtime and current behavior boundaries.
4. Tests remain deterministic and pass in CI without external dependencies.
