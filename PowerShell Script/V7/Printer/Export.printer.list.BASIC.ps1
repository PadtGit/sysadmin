#Requires -Version 7.0

[CmdletBinding(SupportsShouldProcess = $true)]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$ScriptConfig = @{
    OutputDirectory = 'C:\Temp'
    OutputFileName  = 'printers-basic.csv'
    Properties      = @('Name', 'DriverName', 'PortName', 'Shared', 'Published')
}

function Invoke-ExportPrinterListBasic {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutputDirectory,

        [Parameter(Mandatory = $true)]
        [string]$OutputFileName,

        [Parameter(Mandatory = $true)]
        [string[]]$Properties
    )

    $OutputPath = Join-Path -Path $OutputDirectory -ChildPath $OutputFileName

    if (-not (Test-Path -LiteralPath $OutputDirectory -PathType Container)) {
        if ($PSCmdlet.ShouldProcess($OutputDirectory, 'Create directory')) {
            New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
        }
    }

    try {
        $Printers = @(
            Get-Printer -ErrorAction Stop |
                Sort-Object -Property Name
        )
    }
    catch {
        if ($WhatIfPreference) {
            return [pscustomobject]@{
                OutputPath    = $OutputPath
                PrinterCount  = 0
                ExportProfile = 'Basic'
                Status        = 'Skipped'
                Reason        = 'GetPrinterUnavailable'
            }
        }

        throw
    }

    if ($PSCmdlet.ShouldProcess($OutputPath, 'Export printer list')) {
        $Printers |
            Select-Object -Property $Properties |
            Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
    }

    [pscustomobject]@{
        OutputPath    = $OutputPath
        PrinterCount  = $Printers.Count
        ExportProfile = 'Basic'
        Status        = $(if ($WhatIfPreference) { 'WhatIf' } else { 'Completed' })
        Reason        = ''
    }
}

try {
    Invoke-ExportPrinterListBasic `
        -OutputDirectory $ScriptConfig.OutputDirectory `
        -OutputFileName $ScriptConfig.OutputFileName `
        -Properties $ScriptConfig.Properties
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
