# Windows Sandbox Validation

## Purpose

Use Windows Sandbox for manual validation of risky scripts such as:

- network reset/reboot
- installer orphan move
- broad cleanup scripts

## Repo Template

- Sandbox file: `sandbox/sysadmin-main-validation.wsb`
- Host repo path: `C:\Users\Bob\Documents\sysadmin-main`
- Sandbox repo path: `C:\Users\WDAGUtilityAccount\Desktop\sysadmin-main`
- The host repo is mapped read-only into the Sandbox.
- Networking is disabled.
- vGPU is disabled.
- The logon command opens PowerShell and sets the working location to `C:\Users\WDAGUtilityAccount\Desktop\sysadmin-main`.

## Validation Flow

1. Launch the `.wsb` file.
2. Confirm PowerShell opens in `C:\Users\WDAGUtilityAccount\Desktop\sysadmin-main`.
3. Run the target script with `-WhatIf` first.
4. Inspect the result object and any generated output under `artifacts/validation/`.
5. Remember that the repo mapping is read-only; use the Sandbox only for disposable validation, not for writing changes back to the host repo.
6. Only perform non-`WhatIf` validation when you are intentionally testing in the disposable Sandbox environment.
