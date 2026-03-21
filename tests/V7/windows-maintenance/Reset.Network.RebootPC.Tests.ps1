Describe 'V7 network reset and reboot' {
    . (Resolve-Path (Join-Path $PSScriptRoot '..\..\TestHelpers.ps1')).Path

    It 'returns a preview-safe WhatIf summary' {
        $Result = Invoke-WhatIfScriptObject -Shell pwsh -RelativeScriptPath 'PowerShell Script\V7\windows-maintenance\Reset.Network.RebootPC.ps1'

        $Result.Object | Should Not BeNullOrEmpty
        $Result.Object.CommandCount | Should Be 5
        $Result.Object.ExecutedCount | Should Be 0
        $Result.Object.Status | Should Be 'WhatIf'
    }
}
