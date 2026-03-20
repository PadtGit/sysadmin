#Requires -Version 7.0

[CmdletBinding(SupportsShouldProcess = $true)]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$RequireAdmin = $true
$IsAdministrator = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$PrinterStatus = 'Offline'

function Invoke-OfflinePrinterRemoval {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [bool]$RequireAdmin,

        [Parameter(Mandatory = $true)]
        [bool]$IsAdministrator,

        [Parameter(Mandatory = $true)]
        [string]$PrinterStatus
    )

    if ($RequireAdmin -and -not $WhatIfPreference -and -not $IsAdministrator) {
        throw 'Run this script in an elevated PowerShell 5.1 session.'
    }

    try {
        $Printers = @(Get-Printer -ErrorAction Stop | Where-Object { [string]$_.PrinterStatus -eq $PrinterStatus })
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
    Invoke-OfflinePrinterRemoval `
        -RequireAdmin $RequireAdmin `
        -IsAdministrator $IsAdministrator `
        -PrinterStatus $PrinterStatus
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}

