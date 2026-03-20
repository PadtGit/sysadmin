#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess = $true)]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$RequireAdmin = $true
$IsAdministrator = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$CleanupPaths = @(
    $env:TEMP,
    (Join-Path -Path $env:SystemRoot -ChildPath 'Temp'),
    (Join-Path -Path $env:SystemRoot -ChildPath 'Prefetch')
)
$UpdateServiceName = 'wuauserv'
$UpdateCachePath = Join-Path -Path $env:SystemRoot -ChildPath 'SoftwareDistribution\Download'
$ServiceTimeoutSeconds = 30
$FlushDns = $true
$ClearRecycleBin = $true
$IpConfigPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\ipconfig.exe'

function Invoke-WindowsCacheCleanup {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [bool]$RequireAdmin,

        [Parameter(Mandatory = $true)]
        [bool]$IsAdministrator,

        [Parameter(Mandatory = $true)]
        [string[]]$CleanupPaths,

        [Parameter(Mandatory = $true)]
        [string]$UpdateServiceName,

        [Parameter(Mandatory = $true)]
        [string]$UpdateCachePath,

        [Parameter(Mandatory = $true)]
        [int]$ServiceTimeoutSeconds,

        [Parameter(Mandatory = $true)]
        [bool]$FlushDns,

        [Parameter(Mandatory = $true)]
        [bool]$ClearRecycleBin,

        [Parameter(Mandatory = $true)]
        [string]$IpConfigPath
    )

    if ($RequireAdmin -and -not $WhatIfPreference -and -not $IsAdministrator) {
        throw 'Run this script in an elevated PowerShell 5.1 session.'
    }

    $Service = Get-Service -Name $UpdateServiceName -ErrorAction Stop
    $ServiceWasRunning = $Service.Status -eq [System.ServiceProcess.ServiceControllerStatus]::Running
    $RemovedCount = 0
    $Status = 'Completed'

    if ($ServiceWasRunning -and $PSCmdlet.ShouldProcess($UpdateServiceName, 'Stop service')) {
        Stop-Service -Name $UpdateServiceName -Force -ErrorAction Stop
        (Get-Service -Name $UpdateServiceName -ErrorAction Stop).WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Stopped, [TimeSpan]::FromSeconds($ServiceTimeoutSeconds))
    }

    try {
        if (Test-Path -LiteralPath $UpdateCachePath -PathType Container) {
            try {
                $UpdateItems = @(Get-ChildItem -LiteralPath $UpdateCachePath -Force -ErrorAction Stop)
            }
            catch {
                $UpdateItems = @()
            }

            foreach ($UpdateItem in $UpdateItems) {
                if ($PSCmdlet.ShouldProcess($UpdateItem.FullName, 'Remove update cache item')) {
                    Remove-Item -LiteralPath $UpdateItem.FullName -Recurse -Force -ErrorAction SilentlyContinue
                    $RemovedCount++
                }
            }
        }
    }
    finally {
        if ($ServiceWasRunning -and $PSCmdlet.ShouldProcess($UpdateServiceName, 'Start service')) {
            Start-Service -Name $UpdateServiceName -ErrorAction Stop
            (Get-Service -Name $UpdateServiceName -ErrorAction Stop).WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Running, [TimeSpan]::FromSeconds($ServiceTimeoutSeconds))
        }
    }

    foreach ($CleanupPath in $CleanupPaths) {
        if (-not (Test-Path -LiteralPath $CleanupPath -PathType Container)) {
            continue
        }

        try {
            $CleanupItems = @(Get-ChildItem -LiteralPath $CleanupPath -Force -ErrorAction Stop)
        }
        catch {
            $CleanupItems = @()
        }

        foreach ($CleanupItem in $CleanupItems) {
            if ($PSCmdlet.ShouldProcess($CleanupItem.FullName, 'Remove cache item')) {
                Remove-Item -LiteralPath $CleanupItem.FullName -Recurse -Force -ErrorAction SilentlyContinue
                $RemovedCount++
            }
        }
    }

    if ($FlushDns -and $PSCmdlet.ShouldProcess('DNS client cache', 'Flush')) {
        & $IpConfigPath /flushdns | Out-Null

        if ($LASTEXITCODE -ne 0) {
            throw 'DNS cache flush failed.'
        }
    }

    if ($ClearRecycleBin -and $PSCmdlet.ShouldProcess('Recycle Bin', 'Clear')) {
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
    }

    if ($WhatIfPreference) {
        $Status = 'WhatIf'
    }

    [pscustomobject]@{
        CleanupPathCount = $CleanupPaths.Count
        RemovedCount     = $RemovedCount
        FlushDns         = $FlushDns
        ClearRecycleBin  = $ClearRecycleBin
        Status           = $Status
        Reason           = ''
    }
}

try {
    Invoke-WindowsCacheCleanup `
        -RequireAdmin $RequireAdmin `
        -IsAdministrator $IsAdministrator `
        -CleanupPaths $CleanupPaths `
        -UpdateServiceName $UpdateServiceName `
        -UpdateCachePath $UpdateCachePath `
        -ServiceTimeoutSeconds $ServiceTimeoutSeconds `
        -FlushDns $FlushDns `
        -ClearRecycleBin $ClearRecycleBin `
        -IpConfigPath $IpConfigPath
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
