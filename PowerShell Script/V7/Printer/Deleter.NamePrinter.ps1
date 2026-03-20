#Requires -Version 7.0

[CmdletBinding(SupportsShouldProcess)]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$ScriptConfig = @{
    NamePattern = '*NAMEPRINTER*'
}

function Invoke-RemovePrinterByName {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$NamePattern
    )

    if ([string]::IsNullOrWhiteSpace($NamePattern) -or $NamePattern -eq '*NAMEPRINTER*') {
        if ($WhatIfPreference) {
            Write-Output 'Skipped because NamePattern is still the default placeholder.'
            return
        }

        throw 'Update $ScriptConfig.NamePattern before running the script.'
    }

    $printers = @(
        Get-Printer -ErrorAction Stop |
            Where-Object { $_.Name -like $NamePattern }
    )

    if ($printers.Count -eq 0) {
        Write-Output ("No printers match pattern: {0}" -f $NamePattern)
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
    Invoke-RemovePrinterByName -NamePattern $ScriptConfig.NamePattern
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
