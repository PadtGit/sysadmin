#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess = $true)]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$RequireAdmin = $true
$IsAdministrator = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$NamePattern = '*NAMEPRINTER*'

function Invoke-NamedPrinterRemoval {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [bool]$RequireAdmin,

        [Parameter(Mandatory = $true)]
        [bool]$IsAdministrator,

        [Parameter(Mandatory = $true)]
        [string]$NamePattern
    )

    if ($RequireAdmin -and -not $WhatIfPreference -and -not $IsAdministrator) {
        throw 'Run this script in an elevated PowerShell 5.1 session.'
    }

    if ([string]::IsNullOrWhiteSpace($NamePattern) -or $NamePattern -eq '*NAMEPRINTER*') {
        return [pscustomobject]@{
            NamePattern  = $NamePattern
            PrinterCount = 0
            RemovedCount = 0
            Status       = 'Skipped'
            Reason       = 'NamePatternNotConfigured'
        }
    }

    try {
        $Printers = @(Get-Printer -ErrorAction Stop | Where-Object { $_.Name -like $NamePattern })
    }
    catch {
        if ($WhatIfPreference) {
            return [pscustomobject]@{
                NamePattern  = $NamePattern
                PrinterCount = 0
                RemovedCount = 0
                Status       = 'Skipped'
                Reason       = 'GetPrinterUnavailable'
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
        NamePattern  = $NamePattern
        PrinterCount = $Printers.Count
        RemovedCount = $RemovedCount
        Status       = $Status
        Reason       = ''
    }
}

try {
    Invoke-NamedPrinterRemoval `
        -RequireAdmin $RequireAdmin `
        -IsAdministrator $IsAdministrator `
        -NamePattern $NamePattern
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
