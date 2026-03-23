# Changelog

This changelog captures weekly repo-level highlights from landed git history and supporting docs.

## Week of March 16-22, 2026

### Highlights

- Established the canonical nested script layout under `PowerShell Script/V7` and `PowerShell Script/V5`, removed duplicate root script trees, and redirected generated validation output into `artifacts/validation/`.
- Rolled out first-pass validation automation with a GitHub Actions workflow, analyzer and Pester helpers, trusted `-WhatIf` smoke checks, and Windows Sandbox guidance for risky manual validation.
- Shipped repo-wide security hardening across Adobe install, printer export/transcript, orphaned-installer handling, and cache-cleanup scripts in both V7 and V5, backed by new regression coverage.
- Closed the week by codifying the current maintenance workflow in repo-local security-hardening and behavioral Pester skills plus an expanded `AGENTS.md` playbook.

### PRs and Landed Changes

- March 20, 2026: Initial import of `sysadmin-main` landed in Git.
- March 20, 2026: The repo consolidated onto the nested `PowerShell Script` tree and added validation tooling, CI wiring, Windows Sandbox assets, and supporting docs.
- March 20, 2026: The simple spool cleanup flow had its `-WhatIf` and restart behavior aligned across the V7 and V5 variants.
- March 21, 2026: A security best-practices review report documented installer-trust, output-root, reparse-point, and coverage gaps.
- March 21, 2026: Security hardening and regression tests landed across the mirrored V7 and V5 admin script pairs.
- March 21, 2026: `restart.SpoolDeleteQV4.ps1` was corrected so the spooler restarts only when the current invocation actually stopped the service.
- March 22, 2026: Repo-local skills for PowerShell security hardening and behavioral Pester coverage were added.
- March 22, 2026: `AGENTS.md` was refreshed with the current analyzer, Pester, smoke-check, and Windows Sandbox workflows.

### Rollouts

- Validation now flows through `.github/workflows/powershell-validation.yml`, `tools/Invoke-PSScriptAnalyzer.ps1`, and `artifacts/validation/`, keeping local and CI checks aligned.
- High-risk manual validation now has a documented Windows Sandbox path via `sandbox/sysadmin-main-validation.wsb` and `docs/windows-sandbox-validation.md`.
- Security controls rolled into the script pairs now include Authenticode and trusted-publisher validation for staged Adobe installers, trusted output or destination roots, and reparse-point guards for cleanup and quarantine-style moves.
- Behavioral coverage expanded alongside the hardening work so V7 and V5 drift stays explicit and test-backed.

### Incidents and Fixes

- The main incident-style regression this week was spooler restart logic that could restart the service even when the current run had not stopped it. That was fixed on March 21, 2026, and test coverage was added for both script variants.
- Earlier in the week, the simpler spool cleanup flow also had its `-WhatIf` and restart behavior aligned to reduce preview versus runtime drift.
- No separate outage or postmortem documents were found in the repo for this week; the incident summary above is based on landed bug-fix commits.

### Reviews

- `security_best_practices_report.md` added a structured review of installer trust, predictable root-level outputs, reparse-point exposure, and missing security-focused tests.
- The March 21, 2026 hardening pass appears to be the direct follow-through on that review, including new regression tests in both script trees.
- The maintenance skill and `AGENTS.md` now explicitly steer follow-on work toward the security-hardening and behavioral Pester patterns introduced this week.
