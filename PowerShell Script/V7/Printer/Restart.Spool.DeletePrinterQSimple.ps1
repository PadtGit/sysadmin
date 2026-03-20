#Requires -Version 7.0
#Requires -RunAsAdministrator

[CmdletBinding(SupportsShouldProcess)]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$ScriptConfig = @{
    ServiceName    = 'Spooler'
    SpoolDirectory = Join-Path -Path $env:SystemRoot -ChildPath 'System32\spool\PRINTERS'
}

function Invoke-ClearPrintQueueSimple {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$ServiceName,

        [Parameter(Mandatory)]
        [string]$SpoolDirectory
    )

    Stop-Service -Name $ServiceName -Force -ErrorAction Stop

    try {
        $deletedCount = 0
        $files = @(
            Get-ChildItem -LiteralPath $SpoolDirectory -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -in '.spl', '.shd' }
        )

        foreach ($file in $files) {
            if ($PSCmdlet.ShouldProcess($file.FullName, 'Remove spool file')) {
                Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
                $deletedCount++
            }
        }

        [pscustomobject]@{
            DeletedFiles = $deletedCount
            ServiceName  = $ServiceName
        }
    }
    finally {
        Start-Service -Name $ServiceName -ErrorAction Stop
    }
}

try {
    Invoke-ClearPrintQueueSimple `
        -ServiceName $ScriptConfig.ServiceName `
        -SpoolDirectory $ScriptConfig.SpoolDirectory
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
