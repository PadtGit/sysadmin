#Requires -Version 7.0

[CmdletBinding(SupportsShouldProcess = $true)]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$ScriptConfig = @{
    NamePattern = '*NAMEPRINTER*'
}

function Invoke-RemovePrinterByName {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$NamePattern
    )

    if ([string]::IsNullOrWhiteSpace($NamePattern) -or $NamePattern -eq '*NAMEPRINTER*') {
        if ($WhatIfPreference) {
            return [pscustomobject]@{
                NamePattern  = $NamePattern
                PrinterCount = 0
                RemovedCount = 0
                Status       = 'Skipped'
                Reason       = 'NamePatternNotConfigured'
            }
        }

        throw 'Update $ScriptConfig.NamePattern before running the script.'
    }

    try {
        $Printers = @(
            Get-Printer -ErrorAction Stop |
                Where-Object { $_.Name -like $NamePattern }
        )
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
    Invoke-RemovePrinterByName -NamePattern $ScriptConfig.NamePattern
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
