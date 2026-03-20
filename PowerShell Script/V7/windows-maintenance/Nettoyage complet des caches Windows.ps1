#Requires -Version 7.0
#Requires -RunAsAdministrator

[CmdletBinding(SupportsShouldProcess)]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$ScriptConfig = @{
    CleanupPaths          = @(
        $env:TEMP,
        (Join-Path -Path $env:SystemRoot -ChildPath 'Temp'),
        (Join-Path -Path $env:SystemRoot -ChildPath 'Prefetch')
    )
    UpdateServiceName     = 'wuauserv'
    UpdateCachePath       = Join-Path -Path $env:SystemRoot -ChildPath 'SoftwareDistribution\Download'
    ServiceTimeoutSeconds = 30
    FlushDns              = $true
    ClearRecycleBin       = $true
}

function Invoke-ClearWindowsCaches {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string[]]$CleanupPaths,

        [Parameter(Mandatory)]
        [string]$UpdateServiceName,

        [Parameter(Mandatory)]
        [string]$UpdateCachePath,

        [Parameter(Mandatory)]
        [int]$ServiceTimeoutSeconds,

        [Parameter(Mandatory)]
        [bool]$FlushDns,

        [Parameter(Mandatory)]
        [bool]$ClearRecycleBin
    )

    $service = Get-Service -Name $UpdateServiceName -ErrorAction Stop
    $wasRunning = $service.Status -eq [System.ServiceProcess.ServiceControllerStatus]::Running

    if ($wasRunning) {
        Stop-Service -Name $UpdateServiceName -Force -ErrorAction Stop
        $service.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Stopped, [TimeSpan]::FromSeconds($ServiceTimeoutSeconds))
    }

    try {
        if (Test-Path -LiteralPath $UpdateCachePath) {
            Get-ChildItem -LiteralPath $UpdateCachePath -Force -ErrorAction SilentlyContinue | ForEach-Object {
                if ($PSCmdlet.ShouldProcess($_.FullName, 'Remove update cache item')) {
                    Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
    finally {
        if ($wasRunning) {
            Start-Service -Name $UpdateServiceName -ErrorAction Stop
            (Get-Service -Name $UpdateServiceName -ErrorAction Stop).WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Running, [TimeSpan]::FromSeconds($ServiceTimeoutSeconds))
        }
    }

    foreach ($path in $CleanupPaths) {
        if (-not (Test-Path -LiteralPath $path)) {
            continue
        }

        Get-ChildItem -LiteralPath $path -Force -ErrorAction SilentlyContinue | ForEach-Object {
            if ($PSCmdlet.ShouldProcess($_.FullName, 'Remove cache item')) {
                Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    if ($FlushDns -and $PSCmdlet.ShouldProcess('DNS client cache', 'Flush')) {
        & ipconfig.exe /flushdns | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw 'DNS cache flush failed.'
        }
    }

    if ($ClearRecycleBin -and $PSCmdlet.ShouldProcess('Recycle Bin', 'Clear')) {
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
    }

    Write-Output 'Windows cache cleanup completed.'
}

try {
    Invoke-ClearWindowsCaches `
        -CleanupPaths $ScriptConfig.CleanupPaths `
        -UpdateServiceName $ScriptConfig.UpdateServiceName `
        -UpdateCachePath $ScriptConfig.UpdateCachePath `
        -ServiceTimeoutSeconds $ScriptConfig.ServiceTimeoutSeconds `
        -FlushDns $ScriptConfig.FlushDns `
        -ClearRecycleBin $ScriptConfig.ClearRecycleBin
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
