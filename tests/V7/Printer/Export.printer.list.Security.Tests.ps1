Describe 'V7 printer export hardening' {
    . (Resolve-Path (Join-Path $PSScriptRoot '..\..\TestHelpers.ps1')).Path

    It 'uses a secured per-user path and unique file name for the basic export preview' {
        $Result = Invoke-WhatIfScriptObject -Shell pwsh -RelativeScriptPath 'PowerShell Script\V7\Printer\Export.printer.list.BASIC.ps1'

        $Result.Object | Should Not BeNullOrEmpty
        $Result.Object.OutputPath | Should Match 'sysadmin-main\\Exports\\Printers\\printers-basic-'
        $Result.Object.OutputPath | Should Not Match 'C:\\Temp'
    }

    It 'uses a secured per-user path and unique file name for the full export preview' {
        $Result = Invoke-WhatIfScriptObject -Shell pwsh -RelativeScriptPath 'PowerShell Script\V7\Printer\Export.printer.list.FULL.ps1'

        $Result.Object | Should Not BeNullOrEmpty
        $Result.Object.OutputPath | Should Match 'sysadmin-main\\Exports\\Printers\\printers-full-'
        $Result.Object.OutputPath | Should Not Match 'C:\\Temp'
    }

    It 'restricts the export directory in code' {
        $BasicContent = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'PowerShell Script\V7\Printer\Export.printer.list.BASIC.ps1') -Raw
        $FullContent = Get-Content -LiteralPath (Join-Path $script:RepoRoot 'PowerShell Script\V7\Printer\Export.printer.list.FULL.ps1') -Raw

        $BasicContent | Should Match 'Resolve-SecureDirectory'
        $BasicContent | Should Match 'Set-RestrictedDirectoryAcl'
        $FullContent | Should Match 'Resolve-SecureDirectory'
        $FullContent | Should Match 'Set-RestrictedDirectoryAcl'
    }
}
