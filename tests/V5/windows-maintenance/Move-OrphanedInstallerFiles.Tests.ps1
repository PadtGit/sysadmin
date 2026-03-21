Describe 'V5 installer orphan move hardening' {
    . (Resolve-Path (Join-Path $PSScriptRoot '..\..\TestHelpers.ps1')).Path

    It 'uses a secured quarantine path and guards against reparse points' {
        $ScriptPath = Join-Path $script:RepoRoot 'PowerShell Script\V5\windows-maintenance\Move-OrphanedInstallerFiles.ps1'
        $Content = Get-Content -LiteralPath $ScriptPath -Raw

        $Content | Should Match 'Quarantine\\InstallerOrphans'
        $Content | Should Match 'Resolve-SecureDirectory'
        $Content | Should Match 'Test-IsReparsePoint'
        $Content | Should Not Match 'C:\\FichierOrphelin'
    }
}
