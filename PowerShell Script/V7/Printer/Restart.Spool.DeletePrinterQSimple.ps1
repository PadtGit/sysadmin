#Requires -Version 7.0

[CmdletBinding(SupportsShouldProcess)]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$RequireAdmin = $true
$IsAdministrator = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScriptConfig = @{
    ServiceName       = 'Spooler'
    SpoolDirectory    = Join-Path -Path $env:SystemRoot -ChildPath 'System32\spool\PRINTERS'
    AllowedExtensions = @('.spl', '.shd')
}

function Invoke-ClearPrintQueueSimple {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [bool]$RequireAdmin,

        [Parameter(Mandatory)]
        [bool]$IsAdministrator,

        [Parameter(Mandatory)]
        [string]$ServiceName,

        [Parameter(Mandatory)]
        [string]$SpoolDirectory,

        [Parameter(Mandatory)]
        [string[]]$AllowedExtensions
    )

    if ($RequireAdmin -and -not $WhatIfPreference -and -not $IsAdministrator) {
        throw 'Run this script in an elevated PowerShell 7 session.'
    }

    $service = Get-Service -Name $ServiceName -ErrorAction Stop
    $serviceWasRunning = $service.Status -eq [System.ServiceProcess.ServiceControllerStatus]::Running
    $serviceWasStopped = $false

    try {
        $deletedCount = 0

        if ($serviceWasRunning -and $PSCmdlet.ShouldProcess($ServiceName, 'Stop service')) {
            Stop-Service -Name $ServiceName -Force -ErrorAction Stop
            $serviceWasStopped = $true
        }

        $files = @(
            Get-ChildItem -LiteralPath $SpoolDirectory -File -ErrorAction SilentlyContinue |
                Where-Object { $AllowedExtensions -contains $_.Extension.ToLowerInvariant() }
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
        if ($serviceWasStopped -and $PSCmdlet.ShouldProcess($ServiceName, 'Start service')) {
            Start-Service -Name $ServiceName -ErrorAction Stop
        }
    }
}

try {
    Invoke-ClearPrintQueueSimple `
        -RequireAdmin $RequireAdmin `
        -IsAdministrator $IsAdministrator `
        -ServiceName $ScriptConfig.ServiceName `
        -SpoolDirectory $ScriptConfig.SpoolDirectory `
        -AllowedExtensions $ScriptConfig.AllowedExtensions
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
