#Requires -Version 7.0

[CmdletBinding(SupportsShouldProcess)]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$ScriptConfig = @{
    PrinterStatus = 'Offline'
}

function Invoke-RemoveOfflinePrinters {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$PrinterStatus
    )

    try {
        $printers = @(
            Get-Printer -ErrorAction Stop |
                Where-Object { [string]$_.PrinterStatus -eq $PrinterStatus }
        )
    }
    catch {
        if ($WhatIfPreference) {
            Write-Output 'Skipped because printers could not be queried in this session.'
            return
        }

        throw
    }

    if ($printers.Count -eq 0) {
        Write-Output 'No offline printers found.'
        return
    }

    foreach ($printer in $printers) {
        if ($PSCmdlet.ShouldProcess($printer.Name, 'Remove printer')) {
            Remove-Printer -Name $printer.Name -Confirm:$false -ErrorAction Stop
            [pscustomobject]@{
                Name   = $printer.Name
                Action = 'Removed'
            }
        }
    }
}

try {
    Invoke-RemoveOfflinePrinters -PrinterStatus $ScriptConfig.PrinterStatus
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
