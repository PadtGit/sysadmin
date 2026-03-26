# Changelog

This changelog captures weekly repo-level highlights from landed git history and supporting docs.

> Branch note: `Powershell.7` is the single-runtime PowerShell 7 branch. Historical entries below may reference the pre-split mirrored V5/V7 layout from `main`.

## Week of March 23-29, 2026

### Highlights

- Refined the repo’s operating model into a manager-pattern workflow with dedicated explorer, implementation, validation, security, behavioral-Pester, critic, and playbook agent roles, while removing the leftover AutoHotkey subtree so `sysadmin-main` stays PowerShell-only.
- Promoted validation from a basic helper into a pinned and CI-aligned analyzer pipeline by standardizing on PSScriptAnalyzer `1.25.0`, expanding `tools/Invoke-PSScriptAnalyzer.ps1`, and aligning workflow, settings, and artifact handling around the recursive repo-wide command.
- Reworked mirrored V7 and V5 coverage toward behavioral Pester tests, then followed through with another hardening pass across printer, Adobe, orphaned-installer, and Windows-maintenance scripts.
- Closed the week by fixing analyzer crash handling and stale JSON artifact behavior, with dedicated tests to keep analyzer failures visible instead of silently losing signal.

### PRs and Landed Changes

- March 23, 2026: PSScriptAnalyzer was pinned to `1.25.0`, the GitHub validation workflow was updated to use explicit analyzer and Pester configuration, and the analyzer helper was expanded to emit aligned text, JSON, and SARIF outputs.
- March 23, 2026: The analyzer helper received a follow-up auto-update that removed a stale tracked SARIF artifact and improved report-generation behavior.
- March 23, 2026: The multi-agent workflow docs, repo-local maintenance skill, and `.codex/agents/*.toml` definitions were refreshed, and the lingering `AutoHotkey/` files were removed.
- March 25, 2026: A broad admin-script hardening pass landed across mirrored V7 and V5 Adobe, printer, orphaned-installer, and cleanup scripts, with matching regression coverage updates.
- March 25, 2026: `tools/Invoke-PSScriptAnalyzer.ps1` was fixed to surface analyzer invocation failures as diagnostics and to overwrite stale JSON output when a clean run returns no findings.
- March 25, 2026: A new `tests/tools/Invoke-PSScriptAnalyzer.Tests.ps1` suite landed to lock in the analyzer-helper crash-handling and artifact-reset behavior.

### Rollouts

- Validation is now more explicitly standardized around the recursive analyzer command, pinned `PSScriptAnalyzer 1.25.0`, CI-style `New-PesterConfiguration`, and uploaded artifacts under `artifacts/validation/`.
- The repo-local agent roster now covers dedicated validation, security-boundary, and behavioral-Pester specialist roles, with `AGENTS.md`, the maintenance skill, and `docs/sysadmin-main-multi-agent-sop.md` kept in sync.
- Behavioral Pester coverage broadened from contract-style checks toward mocked behavior and side-effect assertions for mirrored V7 and V5 admin scripts.
- Analyzer output handling is now safer for automation consumers because empty clean runs explicitly reset JSON findings and invocation crashes are recorded as structured diagnostics.

### Incidents and Fixes

- The most visible tooling regression this week was analyzer instability: some repo files could trigger PSScriptAnalyzer invocation failures, and clean reruns could leave stale JSON findings behind. The March 25, 2026 fixes now record invocation failures as explicit diagnostics and force empty JSON output on clean passes.
- This week also included a broader admin-script hardening sweep rather than a single script outage. The follow-on regression coverage indicates the focus was preventing quiet drift across mirrored V7 and V5 script pairs.
- No separate outage or postmortem documents were found in the repo for this week; the incident summary above is based on landed bug-fix and hardening commits.

### Reviews

- The repo’s validation and workflow surfaces were reviewed and tightened in lockstep across `AGENTS.md`, `.agents/skills/maintain-windows-admin-powershell/SKILL.md`, `.codex/agents/*.toml`, and `.github/workflows/powershell-validation.yml`.
- The week’s testing emphasis shifted further toward behavioral Pester coverage, especially around printer, orphaned-installer, analyzer-helper, and Windows-maintenance flows.
- The analyzer settings now document a concrete pinned-version caveat by keeping `PSUseCorrectCasing` disabled until the repo intentionally moves off the current analyzer baseline.

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

