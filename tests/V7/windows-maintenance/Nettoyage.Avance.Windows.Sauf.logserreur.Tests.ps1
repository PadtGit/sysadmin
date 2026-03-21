Describe 'V7 advanced cleanup' {
    . (Resolve-Path (Join-Path $PSScriptRoot '..\..\TestHelpers.ps1')).Path

    It 'uses the ASCII filename and returns a safe preview result' {
        $Result = Invoke-WhatIfScriptObject -Shell pwsh -RelativeScriptPath 'PowerShell Script\V7\windows-maintenance\Nettoyage.Avance.Windows.Sauf.logserreur.ps1'
        $ScriptPath = Join-Path $script:RepoRoot 'PowerShell Script\V7\windows-maintenance\Nettoyage.Avance.Windows.Sauf.logserreur.ps1'
        $Content = Get-Content -LiteralPath $ScriptPath -Raw

        $Result.Object | Should Not BeNullOrEmpty
        (@('Skipped', 'WhatIf') -contains $Result.Object.Status) | Should Be $true
        $Content | Should Match 'CleanupSpecs'
        $Content | Should Match 'Resolve-TrustedDirectoryPath'
        $Content | Should Match 'Test-IsReparsePoint'
        $Content | Should Not Match '\$env:TEMP'

        if ($Result.Object.Status -eq 'Skipped') {
            $Result.Object.Reason | Should Be 'AdminPreviewRequired'
        }
    }
}
