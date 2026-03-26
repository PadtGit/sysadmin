#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess = $true)]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$LocalApplicationDataPath = [Environment]::GetFolderPath('LocalApplicationData')

$RequireAdmin = $true
$IsAdministrator = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$CleanupSpecs = @(
    @{
        Path         = Join-Path -Path $LocalApplicationDataPath -ChildPath 'Temp'
        AllowedRoots = @($LocalApplicationDataPath)
    },
    @{
        Path         = Join-Path -Path $env:SystemRoot -ChildPath 'Temp'
        AllowedRoots = @($env:SystemRoot)
    },
    @{
        Path         = Join-Path -Path $env:SystemRoot -ChildPath 'Prefetch'
        AllowedRoots = @($env:SystemRoot)
    }
)
$UpdateServiceName = 'wuauserv'
$UpdateCachePath = Join-Path -Path $env:SystemRoot -ChildPath 'SoftwareDistribution\Download'
$ServiceTimeoutSeconds = 30
$FlushDns = $true
$ClearRecycleBin = $true
$IpConfigPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\ipconfig.exe'

function Test-PathWithinAllowedRoot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string[]]$AllowedRoots
    )

    $NormalizedPath = [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
    foreach ($AllowedRoot in $AllowedRoots) {
        if ([string]::IsNullOrWhiteSpace($AllowedRoot)) {
            continue
        }

        $NormalizedRoot = [System.IO.Path]::GetFullPath($AllowedRoot).TrimEnd('\')
        if ($NormalizedPath.Equals($NormalizedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }

        if ($NormalizedPath.StartsWith(($NormalizedRoot + '\'), [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    return $false
}

function Test-IsReparsePoint {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileSystemInfo]$Item
    )

    return (($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Resolve-TrustedDirectoryPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string[]]$AllowedRoots
    )

    $NormalizedPath = [System.IO.Path]::GetFullPath($Path)
    if (-not (Test-PathWithinAllowedRoot -Path $NormalizedPath -AllowedRoots $AllowedRoots)) {
        throw ('Directory path is outside the trusted root: {0}' -f $NormalizedPath)
    }

    foreach ($AllowedRoot in $AllowedRoots) {
        if ([string]::IsNullOrWhiteSpace($AllowedRoot) -or -not (Test-Path -LiteralPath $AllowedRoot -PathType Container)) {
            continue
        }

        $AllowedRootItem = Get-Item -LiteralPath $AllowedRoot -Force -ErrorAction Stop
        if (Test-IsReparsePoint -Item $AllowedRootItem) {
            throw ('Trusted root must not be a reparse point: {0}' -f $AllowedRootItem.FullName)
        }
    }

    if (-not (Test-Path -LiteralPath $NormalizedPath -PathType Container)) {
        return $null
    }

    $DirectoryItem = Get-Item -LiteralPath $NormalizedPath -Force -ErrorAction Stop
    if (Test-IsReparsePoint -Item $DirectoryItem) {
        throw ('Directory path must not be a reparse point: {0}' -f $DirectoryItem.FullName)
    }

    return $DirectoryItem.FullName
}

function Get-SafeChildItems {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    try {
        $ChildItems = @(Get-ChildItem -LiteralPath $Path -Force -ErrorAction Stop)
    }
    catch {
        return @()
    }

    return @(
        $ChildItems |
            Where-Object { -not (Test-IsReparsePoint -Item $_) }
    )
}

function Invoke-WindowsCacheCleanup {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [bool]$RequireAdmin,

        [Parameter(Mandatory = $true)]
        [bool]$IsAdministrator,

        [Parameter(Mandatory = $true)]
        [object[]]$CleanupSpecs,

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

    if ($WhatIfPreference -and -not $IsAdministrator) {
        return [pscustomobject]@{
            CleanupPathCount = $CleanupSpecs.Count
            RemovedCount     = 0
            FlushDns         = $FlushDns
            ClearRecycleBin  = $ClearRecycleBin
            Status           = 'Skipped'
            Reason           = 'AdminPreviewRequired'
        }
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
        $TrustedUpdateCachePath = Resolve-TrustedDirectoryPath -Path $UpdateCachePath -AllowedRoots @(Join-Path -Path $env:SystemRoot -ChildPath 'SoftwareDistribution')
        if (-not [string]::IsNullOrWhiteSpace($TrustedUpdateCachePath)) {
            $UpdateItems = Get-SafeChildItems -Path $TrustedUpdateCachePath

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

    foreach ($CleanupSpec in $CleanupSpecs) {
        $CleanupPath = Resolve-TrustedDirectoryPath -Path $CleanupSpec.Path -AllowedRoots $CleanupSpec.AllowedRoots
        if ([string]::IsNullOrWhiteSpace($CleanupPath)) {
            continue
        }

        $CleanupItems = Get-SafeChildItems -Path $CleanupPath

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
        CleanupPathCount = $CleanupSpecs.Count
        RemovedCount     = $RemovedCount
        FlushDns         = $FlushDns
        ClearRecycleBin  = $ClearRecycleBin
        Status           = $Status
    }
}

try {
    Invoke-WindowsCacheCleanup `
        -RequireAdmin $RequireAdmin `
        -IsAdministrator $IsAdministrator `
        -CleanupSpecs $CleanupSpecs `
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
