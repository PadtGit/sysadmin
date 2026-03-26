#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess = $true)]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$RequireAdmin = $true
$IsAdministrator = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ServiceName = 'Spooler'
$SpoolDirectory = Join-Path -Path $env:SystemRoot -ChildPath 'System32\spool\PRINTERS'
$AllowedExtensions = @('.spl', '.shd')

function Invoke-SimplePrintQueueCleanup {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [bool]$RequireAdmin,

        [Parameter(Mandatory = $true)]
        [bool]$IsAdministrator,

        [Parameter(Mandatory = $true)]
        [string]$ServiceName,

        [Parameter(Mandatory = $true)]
        [string]$SpoolDirectory,

        [Parameter(Mandatory = $true)]
        [string[]]$AllowedExtensions
    )

    if ($RequireAdmin -and -not $WhatIfPreference -and -not $IsAdministrator) {
        throw 'Run this script in an elevated PowerShell 5.1 session.'
    }

    $Service = Get-Service -Name $ServiceName -ErrorAction Stop
    $ServiceWasRunning = $Service.Status -eq [System.ServiceProcess.ServiceControllerStatus]::Running
    $ServiceWasStopped = $false
    $DeletedCount = 0
    $Status = 'Completed'

    if ($ServiceWasRunning -and $PSCmdlet.ShouldProcess($ServiceName, 'Stop service')) {
        Stop-Service -Name $ServiceName -Force -ErrorAction Stop
        $ServiceWasStopped = $true
    }

    try {
        $Files = @(Get-ChildItem -LiteralPath $SpoolDirectory -File -ErrorAction SilentlyContinue | Where-Object { $AllowedExtensions -contains $_.Extension.ToLowerInvariant() })

        foreach ($File in $Files) {
            if ($PSCmdlet.ShouldProcess($File.FullName, 'Remove spool file')) {
                Remove-Item -LiteralPath $File.FullName -Force -ErrorAction Stop
                $DeletedCount++
            }
        }
    }
    finally {
        if ($ServiceWasStopped -and $PSCmdlet.ShouldProcess($ServiceName, 'Start service')) {
            Start-Service -Name $ServiceName -ErrorAction Stop
        }
    }

    if ($WhatIfPreference) {
        $Status = 'WhatIf'
    }

    [pscustomobject]@{
        ServiceName  = $ServiceName
        QueuePath    = $SpoolDirectory
        FileCount    = $Files.Count
        DeletedCount = $DeletedCount
        Status       = $Status
    }
}

try {
    Invoke-SimplePrintQueueCleanup `
        -RequireAdmin $RequireAdmin `
        -IsAdministrator $IsAdministrator `
        -ServiceName $ServiceName `
        -SpoolDirectory $SpoolDirectory `
        -AllowedExtensions $AllowedExtensions
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
