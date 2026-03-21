Describe 'V7 advanced cleanup' {
    . (Resolve-Path (Join-Path $PSScriptRoot '..\..\TestHelpers.ps1')).Path

    It 'uses the ASCII filename and returns a safe preview result' {
        $Result = Invoke-WhatIfScriptObject -Shell pwsh -RelativeScriptPath 'PowerShell Script\V7\windows-maintenance\Nettoyage.Avance.Windows.Sauf.logserreur.ps1'

        $Result.Object | Should Not BeNullOrEmpty
        (@('Skipped', 'WhatIf') -contains $Result.Object.Status) | Should Be $true

        if ($Result.Object.Status -eq 'Skipped') {
            $Result.Object.Reason | Should Be 'AdminPreviewRequired'
        }
    }
}
