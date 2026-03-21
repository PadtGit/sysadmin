Describe 'V7 installer orphan move contract' {
    . (Resolve-Path (Join-Path $PSScriptRoot '..\..\TestHelpers.ps1')).Path

    It 'preserves safe preview and structured result fields' {
        $ScriptPath = Join-Path $script:RepoRoot 'PowerShell Script\V7\windows-maintenance\Move-OrphanedInstallerFiles.ps1'
        $Content = Get-Content -LiteralPath $ScriptPath -Raw

        $Content | Should Match 'SupportsShouldProcess = \$true'
        $Content | Should Match 'Status'
        $Content | Should Match 'Reason'
        $Content | Should Match 'yyyyMMddHHmmssfff'
        $Content | Should Not Match '#Requires -RunAsAdministrator'
    }
}
