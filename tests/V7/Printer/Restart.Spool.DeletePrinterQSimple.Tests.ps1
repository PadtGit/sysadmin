Describe 'V7 simple spool cleanup' {
    . (Resolve-Path (Join-Path $PSScriptRoot '..\..\TestHelpers.ps1')).Path

    It 'returns structured WhatIf output' {
        $Result = Invoke-WhatIfScriptObject -Shell pwsh -RelativeScriptPath 'PowerShell Script\V7\Printer\Restart.Spool.DeletePrinterQSimple.ps1'

        $Result.Object | Should -Not -BeNullOrEmpty
        $Result.Object.ServiceName | Should -Be 'Spooler'
        $Result.Object.Status | Should -Be 'WhatIf'
        $Result.Object.DeletedCount | Should -Be 0
    }
}
