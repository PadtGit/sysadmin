#Requires -Version 7.0

[CmdletBinding(SupportsShouldProcess = $true)]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$ScriptConfig = @{
    PrinterStatus = 'Offline'
}

function Invoke-RemoveOfflinePrinters {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PrinterStatus
    )

    try {
        $Printers = @(
            Get-Printer -ErrorAction Stop |
                Where-Object { [string]$_.PrinterStatus -eq $PrinterStatus }
        )
    }
    catch {
        if ($WhatIfPreference) {
            return [pscustomobject]@{
                PrinterStatus = $PrinterStatus
                PrinterCount  = 0
                RemovedCount  = 0
                Status        = 'Skipped'
                Reason        = 'GetPrinterUnavailable'
            }
        }

        throw
    }

    $RemovedCount = 0
    $Status = 'Completed'

    foreach ($Printer in $Printers) {
        if ($PSCmdlet.ShouldProcess($Printer.Name, 'Remove printer')) {
            Remove-Printer -Name $Printer.Name -Confirm:$false -ErrorAction Stop
            $RemovedCount++
        }
    }

    if ($WhatIfPreference) {
        $Status = 'WhatIf'
    }

    [pscustomobject]@{
        PrinterStatus = $PrinterStatus
        PrinterCount  = $Printers.Count
        RemovedCount  = $RemovedCount
        Status        = $Status
        Reason        = ''
    }
}

try {
    Invoke-RemoveOfflinePrinters -PrinterStatus $ScriptConfig.PrinterStatus
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
