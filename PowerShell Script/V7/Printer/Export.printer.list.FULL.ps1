#Requires -Version 7.0

[CmdletBinding(SupportsShouldProcess)]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$ScriptConfig = @{
    OutputDirectory = 'C:\Temp'
    OutputFileName  = 'printers-full.csv'
    Properties      = @(
        'Name',
        'ComputerName',
        'Type',
        'DriverName',
        'PortName',
        'Shared',
        'ShareName',
        'Published',
        'Queued',
        'Direct',
        'KeepPrintedJobs',
        'PermissionSDDL',
        'PrinterStatus',
        'RenderingMode',
        'WorkflowPolicy'
    )
}

function Invoke-ExportPrinterListFull {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$OutputDirectory,

        [Parameter(Mandatory)]
        [string]$OutputFileName,

        [Parameter(Mandatory)]
        [string[]]$Properties
    )

    if (-not (Test-Path -LiteralPath $OutputDirectory)) {
        New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
    }

    $outputPath = Join-Path -Path $OutputDirectory -ChildPath $OutputFileName

    try {
        $printers = Get-Printer -ErrorAction Stop | Sort-Object -Property Name
    }
    catch {
        if ($WhatIfPreference) {
            [pscustomobject]@{
                OutputPath    = $outputPath
                PrinterCount  = 0
                ExportProfile = 'Full'
                Status        = 'Skipped'
            }
            return
        }

        throw
    }

    if ($PSCmdlet.ShouldProcess($outputPath, 'Export printer list')) {
        $printers |
            Select-Object -Property $Properties |
            Export-Csv -Path $outputPath -NoTypeInformation -Encoding utf8
    }

    [pscustomobject]@{
        OutputPath    = $outputPath
        PrinterCount  = $printers.Count
        ExportProfile = 'Full'
        Status        = 'Ready'
    }
}

try {
    Invoke-ExportPrinterListFull `
        -OutputDirectory $ScriptConfig.OutputDirectory `
        -OutputFileName $ScriptConfig.OutputFileName `
        -Properties $ScriptConfig.Properties
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
