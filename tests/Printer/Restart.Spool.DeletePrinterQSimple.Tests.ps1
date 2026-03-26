Describe 'V5 simple spool cleanup' {
    . (Resolve-Path (Join-Path $PSScriptRoot '..\TestHelpers.ps1')).Path

    It 'returns structured WhatIf output' {
$Result = Invoke-WhatIfScriptObject -RelativeScriptPath 'PowerShell Script\Printer\Restart.Spool.DeletePrinterQSimple.ps1'

        $Result.Object | Should -Not -BeNullOrEmpty
        $Result.Object.ServiceName | Should -Be 'Spooler'
        $Result.Object.Status | Should -Be 'WhatIf'
        $Result.Object.DeletedCount | Should -Be 0
    }
}
