# Security Best Practices Review

> Branch note: `Powershell.7` is the single-runtime PowerShell 7 branch. File references below may point to the pre-split mirrored V5/V7 layout that was reviewed on `main`.

## Executive Summary

This PowerShell admin-scripts repo is in better shape than many operational codebases: I did not find any hardcoded secrets, dynamic code execution (`Invoke-Expression`/`iex`), or download-and-run behavior, and the canonical scripts generally preserve `Set-StrictMode`, `$ErrorActionPreference = 'Stop'`, and `SupportsShouldProcess`.

The highest-value secure-by-default improvements are concentrated in three places:

1. The Adobe refresh scripts execute a locally staged installer as administrator after only checking that the file exists.
2. Several scripts write logs or inventory exports to predictable root-level paths such as `C:\Temp`, including a printer export that contains `PermissionSDDL`.
3. The elevated cleanup/move scripts recursively remove or relocate files without explicit reparse-point or destination-trust checks.

## High Severity

### SEC-1: Elevated installer execution without signature or publisher validation

Impact: if an attacker can replace the staged installer before an admin runs the script, the script will execute attacker-controlled code as administrator.

- [PowerShell Script/V7/Adobe/Install.AdobeAcrobat.Clean.ps1](PowerShell%20Script/V7/Adobe/Install.AdobeAcrobat.Clean.ps1):11-13 hard-codes the package path and log directory.
- [PowerShell Script/V7/Adobe/Install.AdobeAcrobat.Clean.ps1](PowerShell%20Script/V7/Adobe/Install.AdobeAcrobat.Clean.ps1):60-66 verifies only that the package exists.
- [PowerShell Script/V7/Adobe/Install.AdobeAcrobat.Clean.ps1](PowerShell%20Script/V7/Adobe/Install.AdobeAcrobat.Clean.ps1):150-163 launches the package with `msiexec.exe` or `Start-Process` without validating an Authenticode signature, expected publisher, or hash.
- [PowerShell Script/V5/Adobe/Install.AdobeAcrobat.Clean.ps1](PowerShell%20Script/V5/Adobe/Install.AdobeAcrobat.Clean.ps1):11-13,70-89,192-217 contain the same behavior in the Windows PowerShell variant.

Why this matters:

- `Test-Path` proves presence, not trust.
- The script is explicitly admin-only in normal execution, so any replaced package inherits elevated execution.
- This is especially risky if the package is staged in a shared location or copied there by a different workflow that does not verify provenance.

Secure-by-default improvements:

- Require `Get-AuthenticodeSignature` to return `Valid` before execution.
- Enforce an allowlist for expected publisher/subject, for example Adobe's signing identity.
- Prefer a restricted staging directory under `ProgramData` or another ACL-controlled path rather than a generic root-level folder.
- Optionally accept an expected SHA-256 hash and refuse to run when it does not match.

## Medium Severity

### SEC-2: Predictable root-level output paths expose sensitive operational data

Impact: these scripts can place admin-generated inventory or transcript data in locations that are often shared, weakly permissioned, or easy to target with path-hijack techniques.

- [PowerShell Script/V7/Printer/Export.printer.list.FULL.ps1](PowerShell%20Script/V7/Printer/Export.printer.list.FULL.ps1):10-27 defaults to `C:\Temp\printers-full.csv` and exports `PermissionSDDL`.
- [PowerShell Script/V7/Printer/Export.printer.list.FULL.ps1](PowerShell%20Script/V7/Printer/Export.printer.list.FULL.ps1):72-75 writes the export directly to that predictable path.
- [PowerShell Script/V5/Printer/Export.printer.list.FULL.ps1](PowerShell%20Script/V5/Printer/Export.printer.list.FULL.ps1):9-27,67-68 mirror the same pattern.
- [PowerShell Script/V7/Printer/restart.SpoolDeleteQV4.ps1](PowerShell%20Script/V7/Printer/restart.SpoolDeleteQV4.ps1):10-15 and 33-38 default the transcript to `C:\Temp\print-queue.log`.
- [PowerShell Script/V5/Printer/restart.SpoolDeleteQV4.ps1](PowerShell%20Script/V5/Printer/restart.SpoolDeleteQV4.ps1):11-15 and 46-60 mirror the same pattern.
- [PowerShell Script/V7/Adobe/Install.AdobeAcrobat.Clean.ps1](PowerShell%20Script/V7/Adobe/Install.AdobeAcrobat.Clean.ps1):13 and 64-66 default installer logs to `C:\Temp\AdobeAcrobat`.
- [PowerShell Script/V5/Adobe/Install.AdobeAcrobat.Clean.ps1](PowerShell%20Script/V5/Adobe/Install.AdobeAcrobat.Clean.ps1):13 and 86-89 mirror the same pattern.

Why this matters:

- `PermissionSDDL` reveals printer ACL configuration that is not usually needed outside admin workflows.
- Predictable file names make accidental overexposure and clobbering more likely.
- On systems where `C:\Temp` already exists with permissive ACLs, a non-admin user may be able to read these outputs or pre-create path targets.

Secure-by-default improvements:

- Default to an app-specific directory under `ProgramData` or the invoking admin's profile, not `C:\Temp`.
- Create per-run file names with a timestamp or GUID rather than a single fixed filename.
- If the directory must be shared, explicitly set restrictive ACLs when creating it.
- Consider making `PermissionSDDL` opt-in rather than part of the default export profile.

### SEC-3: Elevated delete/move routines do not defend against reparse points or untrusted destinations

Impact: when these scripts run elevated, link-based path tricks or weakly controlled destination folders can cause operations outside the intended cleanup or quarantine area.

- [PowerShell Script/V7/windows-maintenance/Nettoyage.Avance.Windows.Sauf.logserreur.ps1](PowerShell%20Script/V7/windows-maintenance/Nettoyage.Avance.Windows.Sauf.logserreur.ps1):12-18 builds cleanup targets from environment and system paths, then [PowerShell Script/V7/windows-maintenance/Nettoyage.Avance.Windows.Sauf.logserreur.ps1](PowerShell%20Script/V7/windows-maintenance/Nettoyage.Avance.Windows.Sauf.logserreur.ps1):76-95 recursively removes every child item without checking for reparse points.
- [PowerShell Script/V7/windows-maintenance/Nettoyage.Complet.Caches.Windows.ps1](PowerShell%20Script/V7/windows-maintenance/Nettoyage.Complet.Caches.Windows.ps1):12-23 and [PowerShell Script/V7/windows-maintenance/Nettoyage.Complet.Caches.Windows.ps1](PowerShell%20Script/V7/windows-maintenance/Nettoyage.Complet.Caches.Windows.ps1):81-127 do the same for update-cache and temp cleanup.
- [PowerShell Script/V5/windows-maintenance/Nettoyage.Avance.Windows.Sauf.logserreur.ps1](PowerShell%20Script/V5/windows-maintenance/Nettoyage.Avance.Windows.Sauf.logserreur.ps1):11-17,76-119 and [PowerShell Script/V5/windows-maintenance/Nettoyage.Complet.Caches.Windows.ps1](PowerShell%20Script/V5/windows-maintenance/Nettoyage.Complet.Caches.Windows.ps1):11-21,68-110 mirror the same pattern.
- [PowerShell Script/V7/windows-maintenance/Move-OrphanedInstallerFiles.ps1](PowerShell%20Script/V7/windows-maintenance/Move-OrphanedInstallerFiles.ps1):12-13 and [PowerShell Script/V7/windows-maintenance/Move-OrphanedInstallerFiles.ps1](PowerShell%20Script/V7/windows-maintenance/Move-OrphanedInstallerFiles.ps1):48-50,156-169 move files into a root-level backup folder without validating that the destination is trusted and not a reparse point.
- [PowerShell Script/V7/WindowsServer/FichierOphelin.ps1](PowerShell%20Script/V7/WindowsServer/FichierOphelin.ps1):12-15 and [PowerShell Script/V7/WindowsServer/FichierOphelin.ps1](PowerShell%20Script/V7/WindowsServer/FichierOphelin.ps1):48-50,93-111 repeat the same destination-trust gap.
- [PowerShell Script/V5/windows-maintenance/Move-OrphanedInstallerFiles.ps1](PowerShell%20Script/V5/windows-maintenance/Move-OrphanedInstallerFiles.ps1):11-14,46-49,88-102 and [PowerShell Script/V5/WindowsServer/FichierOphelin.ps1](PowerShell%20Script/V5/WindowsServer/FichierOphelin.ps1):11-14,46-49,88-102 mirror it in the V5 tree.

Why this matters:

- Admin cleanup code should treat junctions, symlinks, and root-level destinations as hostile by default.
- Recursive removal without a reparse-point guard increases the chance of deleting outside the intended boundary.
- Moving privileged installer files into a user-controlled or weakly permissioned folder creates an unnecessary trust transfer.

Secure-by-default improvements:

- Skip any item where `($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0`.
- Resolve and canonicalize candidate paths before acting, then enforce an expected root prefix check.
- Refuse root-level backup/output locations unless their ACLs and owner are explicitly validated.
- Prefer an application-owned directory under `ProgramData` for quarantine-style moves.

## Low Severity / Hardening Opportunities

### SEC-4: Security-sensitive scripts are under-tested in the areas that matter most

I found test coverage for several cleanup/orphan-handling scripts, but not for the most security-relevant behaviors above:

- No tests currently exercise signature validation or trusted publisher checks for the Adobe installer flow.
- No tests assert that export/log destinations are created with restrictive ACLs or unique filenames.
- No tests assert that reparse points are skipped during elevated cleanup or quarantine moves.

Recommended follow-up:

- Add Pester tests that mock `Get-AuthenticodeSignature`, `Get-Acl`, `Get-ChildItem`, `Move-Item`, and `Remove-Item`.
- Add explicit regression tests for junction/symlink inputs and pre-existing destination folders.

## Positive Security Notes

- I did not find any use of `Invoke-Expression`, `iex`, `DownloadString`, `Invoke-WebRequest`, or `Invoke-RestMethod` in the script trees.
- I did not find hardcoded credentials, tokens, or plaintext password handling.
- The scripts generally use `LiteralPath`, `Set-StrictMode -Version 3.0`, and `$ErrorActionPreference = 'Stop'`.
- The destructive scripts consistently expose `SupportsShouldProcess`, which is a strong safety baseline for admin tooling.
- The repo already includes analyzer and test entrypoints; the existing analyzer output at `artifacts/validation/psscriptanalyzer.txt` currently reports `No analyzer findings.`

## Recommended Fix Order

1. Add signature and publisher validation to the Adobe installer script pair.
2. Move default log/export/quarantine roots out of `C:\Temp` and other generic root-level folders; create unique filenames and restricted ACLs.
3. Add reparse-point and destination-trust guards to the elevated cleanup and orphan-move script pairs.
4. Add focused Pester coverage for the security boundaries above so future maintenance does not regress them.

