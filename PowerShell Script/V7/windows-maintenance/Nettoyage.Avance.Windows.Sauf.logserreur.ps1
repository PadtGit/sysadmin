#Requires -Version 7.0

[CmdletBinding(SupportsShouldProcess = $true)]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$LocalApplicationDataPath = [Environment]::GetFolderPath('LocalApplicationData')

$RequireAdmin = $true
$IsAdministrator = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScriptConfig = @{
    CleanupSpecs = @(
        @{
            Path         = Join-Path -Path $LocalApplicationDataPath -ChildPath 'Temp'
            AllowedRoots = @($LocalApplicationDataPath)
        },
        @{
            Path         = Join-Path -Path $LocalApplicationDataPath -ChildPath 'D3DSCache'
            AllowedRoots = @($LocalApplicationDataPath)
        },
        @{
            Path         = Join-Path -Path $env:SystemRoot -ChildPath 'Temp'
            AllowedRoots = @($env:SystemRoot)
        },
        @{
            Path         = Join-Path -Path $env:SystemRoot -ChildPath 'SoftwareDistribution\DeliveryOptimization'
            AllowedRoots = @(Join-Path -Path $env:SystemRoot -ChildPath 'SoftwareDistribution')
        }
    )
    ThumbCacheDirectory = Join-Path -Path $LocalApplicationDataPath -ChildPath 'Microsoft\Windows\Explorer'
    ThumbCacheFilter    = 'thumbcache_*.db'
    WindowsOldPath      = Join-Path -Path $env:SystemDrive -ChildPath 'Windows.old'
    RemoveWindowsOld    = $false
    RunComponentCleanup = $true
    DismPath            = Join-Path -Path $env:SystemRoot -ChildPath 'System32\Dism.exe'
}

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
        $ChildItems = @(
            Get-ChildItem -LiteralPath $Path -Force -ErrorAction Stop
        )
    }
    catch {
        return @()
    }

    return @(
        $ChildItems |
            Where-Object { -not (Test-IsReparsePoint -Item $_) }
    )
}

function Invoke-AdvancedWindowsCleanup {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [bool]$RequireAdmin,

        [Parameter(Mandatory = $true)]
        [bool]$IsAdministrator,

        [Parameter(Mandatory = $true)]
        [object[]]$CleanupSpecs,

        [Parameter(Mandatory = $true)]
        [string]$ThumbCacheDirectory,

        [Parameter(Mandatory = $true)]
        [string]$ThumbCacheFilter,

        [Parameter(Mandatory = $true)]
        [string]$WindowsOldPath,

        [Parameter(Mandatory = $true)]
        [bool]$RemoveWindowsOld,

        [Parameter(Mandatory = $true)]
        [bool]$RunComponentCleanup,

        [Parameter(Mandatory = $true)]
        [string]$DismPath
    )

    if ($RequireAdmin -and -not $WhatIfPreference -and -not $IsAdministrator) {
        throw 'Run this script in an elevated PowerShell 7 session.'
    }

    if ($WhatIfPreference -and -not $IsAdministrator) {
        return [pscustomobject]@{
            CleanupPathCount = $CleanupSpecs.Count
            RemovedCount     = 0
            RemoveWindowsOld = $RemoveWindowsOld
            ComponentCleanup = $RunComponentCleanup
            Status           = 'Skipped'
            Reason           = 'AdminPreviewRequired'
        }
    }

    $RemovedCount = 0
    $Status = 'Completed'

    foreach ($CleanupSpec in $CleanupSpecs) {
        $CleanupPath = Resolve-TrustedDirectoryPath -Path $CleanupSpec.Path -AllowedRoots $CleanupSpec.AllowedRoots
        if ([string]::IsNullOrWhiteSpace($CleanupPath)) {
            continue
        }

        $CleanupItems = Get-SafeChildItems -Path $CleanupPath

        foreach ($CleanupItem in $CleanupItems) {
            if ($PSCmdlet.ShouldProcess($CleanupItem.FullName, 'Remove item')) {
                Remove-Item -LiteralPath $CleanupItem.FullName -Recurse -Force -ErrorAction SilentlyContinue
                $RemovedCount++
            }
        }
    }

    if ($PSCmdlet.ShouldProcess('Recycle Bin', 'Clear')) {
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
    }

    $TrustedThumbCacheDirectory = Resolve-TrustedDirectoryPath -Path $ThumbCacheDirectory -AllowedRoots @($LocalApplicationDataPath)
    if (-not [string]::IsNullOrWhiteSpace($TrustedThumbCacheDirectory)) {
        try {
            $ThumbCacheFiles = @(
                Get-ChildItem -LiteralPath $TrustedThumbCacheDirectory -File -Filter $ThumbCacheFilter -ErrorAction Stop |
                    Where-Object { -not (Test-IsReparsePoint -Item $_) }
            )
        }
        catch {
            $ThumbCacheFiles = @()
        }

        foreach ($ThumbCacheFile in $ThumbCacheFiles) {
            if ($PSCmdlet.ShouldProcess($ThumbCacheFile.FullName, 'Remove thumb cache')) {
                Remove-Item -LiteralPath $ThumbCacheFile.FullName -Force -ErrorAction SilentlyContinue
                $RemovedCount++
            }
        }
    }

    $TrustedWindowsOldPath = Resolve-TrustedDirectoryPath -Path $WindowsOldPath -AllowedRoots @($env:SystemDrive)
    if ($RemoveWindowsOld -and -not [string]::IsNullOrWhiteSpace($TrustedWindowsOldPath)) {
        if ($PSCmdlet.ShouldProcess($TrustedWindowsOldPath, 'Remove directory')) {
            Remove-Item -LiteralPath $TrustedWindowsOldPath -Recurse -Force -ErrorAction Stop
            $RemovedCount++
        }
    }

    if ($RunComponentCleanup -and $PSCmdlet.ShouldProcess('Windows component store', 'Run DISM cleanup')) {
        & $DismPath /Online /Cleanup-Image /StartComponentCleanup | Out-Null

        if ($LASTEXITCODE -ne 0) {
            throw 'DISM cleanup failed.'
        }
    }

    if ($WhatIfPreference) {
        $Status = 'WhatIf'
    }

    [pscustomobject]@{
        CleanupPathCount = $CleanupSpecs.Count
        RemovedCount     = $RemovedCount
        RemoveWindowsOld = $RemoveWindowsOld
        ComponentCleanup = $RunComponentCleanup
        Status           = $Status
        Reason           = ''
    }
}

try {
    Invoke-AdvancedWindowsCleanup `
        -RequireAdmin $RequireAdmin `
        -IsAdministrator $IsAdministrator `
        -CleanupSpecs $ScriptConfig.CleanupSpecs `
        -ThumbCacheDirectory $ScriptConfig.ThumbCacheDirectory `
        -ThumbCacheFilter $ScriptConfig.ThumbCacheFilter `
        -WindowsOldPath $ScriptConfig.WindowsOldPath `
        -RemoveWindowsOld $ScriptConfig.RemoveWindowsOld `
        -RunComponentCleanup $ScriptConfig.RunComponentCleanup `
        -DismPath $ScriptConfig.DismPath
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
