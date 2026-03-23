Describe 'V5 complete cleanup hardening' {
    . (Resolve-Path (Join-Path $PSScriptRoot '..\..\TestHelpers.ps1')).Path

    It 'uses trusted cleanup specs and reparse-point guards' {
        $ScriptPath = Join-Path $global:SysadminMainRepoRoot 'PowerShell Script\V5\windows-maintenance\Nettoyage.Complet.Caches.Windows.ps1'
        $Content = Get-Content -LiteralPath $ScriptPath -Raw

        $Content | Should -Match 'CleanupSpecs'
        $Content | Should -Match 'Resolve-TrustedDirectoryPath'
        $Content | Should -Match 'Test-IsReparsePoint'
        $Content | Should -Not -Match '\$env:TEMP'
    }
}
