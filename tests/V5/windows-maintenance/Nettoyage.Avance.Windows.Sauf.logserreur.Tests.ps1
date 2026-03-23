Describe 'V5 advanced cleanup' {
    . (Resolve-Path (Join-Path $PSScriptRoot '..\..\TestHelpers.ps1')).Path

    It 'supports safe preview without elevation' {
        $Result = Invoke-WhatIfScriptObject -Shell powershell -RelativeScriptPath 'PowerShell Script\V5\windows-maintenance\Nettoyage.Avance.Windows.Sauf.logserreur.ps1'
        $ScriptPath = Join-Path $global:SysadminMainRepoRoot 'PowerShell Script\V5\windows-maintenance\Nettoyage.Avance.Windows.Sauf.logserreur.ps1'
        $Content = Get-Content -LiteralPath $ScriptPath -Raw

        $Result.Object | Should -Not -BeNullOrEmpty
        (@('Skipped', 'WhatIf') -contains $Result.Object.Status) | Should -Be $true
        $Content | Should -Match 'CleanupSpecs'
        $Content | Should -Match 'Resolve-TrustedDirectoryPath'
        $Content | Should -Match 'Test-IsReparsePoint'
        $Content | Should -Not -Match '\$env:TEMP'

        if ($Result.Object.Status -eq 'Skipped') {
            $Result.Object.Reason | Should -Be 'AdminPreviewRequired'
        }
    }
}
