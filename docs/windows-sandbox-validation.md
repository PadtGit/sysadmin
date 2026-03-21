# Windows Sandbox Validation

## Purpose

Use Windows Sandbox for manual validation of risky scripts such as:

- network reset/reboot
- installer orphan move
- broad cleanup scripts

## Repo Template

- Sandbox file: `sandbox/sysadmin-main-validation.wsb`
- Host repo path is mapped read-only into the Sandbox.
- Networking is disabled by default.

## Validation Flow

1. Launch the `.wsb` file.
2. Open PowerShell in the mapped repo folder.
3. Run the target script with `-WhatIf` first.
4. Inspect the result object and any generated output under `artifacts/validation/`.
5. Only perform non-`WhatIf` validation when you are intentionally testing in the disposable Sandbox environment.
