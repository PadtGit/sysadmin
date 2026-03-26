#Requires -Version 7.0

[CmdletBinding(SupportsShouldProcess = $true)]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$LocalApplicationDataPath = [Environment]::GetFolderPath('LocalApplicationData')
$RoamingAppDataPath = [Environment]::GetFolderPath('ApplicationData')

$RequireAdmin = $true
$IsAdministrator = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)

$FirefoxProfilesRoot = Join-Path $LocalApplicationDataPath 'Mozilla\Firefox\Profiles'
$FirefoxCacheSpecs = @(
    if (Test-Path -LiteralPath $FirefoxProfilesRoot -PathType Container) {
        Get-ChildItem -LiteralPath $FirefoxProfilesRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { -not ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) } |
            ForEach-Object {
                @{
                    Path         = Join-Path $_.FullName 'cache2'
                    AllowedRoots = @($LocalApplicationDataPath)
                }
            }
    }
)

$NewTeamsPackageRoot = Join-Path $LocalApplicationDataPath 'Packages'
$NewTeamsCacheSpecs = @(
    if (Test-Path -LiteralPath $NewTeamsPackageRoot -PathType Container) {
        Get-ChildItem -LiteralPath $NewTeamsPackageRoot -Directory -Filter 'MSTeams_*' -ErrorAction SilentlyContinue |
            Where-Object { -not ($_.Attributes -band [System.IO.FileAttributes]::ReparsePoint) } |
            ForEach-Object {
                @{
                    Path         = Join-Path $_.FullName 'LocalCache\Microsoft\MSTeams'
                    AllowedRoots = @($LocalApplicationDataPath)
                }
            }
    }
)

$ScriptConfig = @{
    CleanupSpecs = @(
        @{
            Path         = Join-Path $LocalApplicationDataPath 'Temp'
            AllowedRoots = @($LocalApplicationDataPath)
        },
        @{
            Path         = Join-Path $LocalApplicationDataPath 'D3DSCache'
            AllowedRoots = @($LocalApplicationDataPath)
        },
        @{
            Path         = Join-Path $env:SystemRoot 'Temp'
            AllowedRoots = @($env:SystemRoot)
        },
        @{
            Path         = Join-Path $env:SystemRoot 'SoftwareDistribution\DeliveryOptimization'
            AllowedRoots = @(Join-Path $env:SystemRoot 'SoftwareDistribution')
        },
        @{
            Path         = Join-Path $LocalApplicationDataPath 'Google\Chrome\User Data\Default\Cache'
            AllowedRoots = @($LocalApplicationDataPath)
        },
        @{
            Path         = Join-Path $LocalApplicationDataPath 'Google\Chrome\User Data\Default\Code Cache'
            AllowedRoots = @($LocalApplicationDataPath)
        },
        @{
            Path         = Join-Path $LocalApplicationDataPath 'Google\Chrome\User Data\Default\GPUCache'
            AllowedRoots = @($LocalApplicationDataPath)
        },
        @{
            Path         = Join-Path $LocalApplicationDataPath 'Microsoft\Edge\User Data\Default\Cache'
            AllowedRoots = @($LocalApplicationDataPath)
        },
        @{
            Path         = Join-Path $LocalApplicationDataPath 'Microsoft\Edge\User Data\Default\Code Cache'
            AllowedRoots = @($LocalApplicationDataPath)
        },
        @{
            Path         = Join-Path $LocalApplicationDataPath 'Microsoft\Edge\User Data\Default\GPUCache'
            AllowedRoots = @($LocalApplicationDataPath)
        },
        @{
            Path         = Join-Path $RoamingAppDataPath 'Microsoft\Teams\Cache'
            AllowedRoots = @($RoamingAppDataPath)
        },
        @{
            Path         = Join-Path $RoamingAppDataPath 'Microsoft\Teams\blob_storage'
            AllowedRoots = @($RoamingAppDataPath)
        },
        @{
            Path         = Join-Path $RoamingAppDataPath 'Microsoft\Teams\databases'
            AllowedRoots = @($RoamingAppDataPath)
        },
        @{
            Path         = Join-Path $RoamingAppDataPath 'Microsoft\Teams\GPUCache'
            AllowedRoots = @($RoamingAppDataPath)
        },
        @{
            Path         = Join-Path $LocalApplicationDataPath 'Microsoft\Windows\WER\ReportArchive'
            AllowedRoots = @($LocalApplicationDataPath)
        },
        @{
            Path         = Join-Path $LocalApplicationDataPath 'Microsoft\Windows\WER\ReportQueue'
            AllowedRoots = @($LocalApplicationDataPath)
        },
        @{
            Path         = Join-Path $LocalApplicationDataPath 'CrashDumps'
            AllowedRoots = @($LocalApplicationDataPath)
        }
    ) + $FirefoxCacheSpecs + $NewTeamsCacheSpecs
    ThumbCacheDirectory = Join-Path $LocalApplicationDataPath 'Microsoft\Windows\Explorer'
    ThumbCacheFilter    = 'thumbcache_*.db'
    WindowsOldPath      = Join-Path $env:SystemDrive 'Windows.old'
    RemoveWindowsOld    = $false
    RunComponentCleanup = $true
    DismPath            = Join-Path $env:SystemRoot 'System32\Dism.exe'
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
        if ([string]::IsNullOrWhiteSpace($AllowedRoot) -or
            -not (Test-Path -LiteralPath $AllowedRoot -PathType Container)) {
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
        [string]$LocalApplicationDataPath,

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

    if ($RunComponentCleanup -and -not (Test-Path -LiteralPath $DismPath -PathType Leaf)) {
        throw ('DISM not found at: {0}' -f $DismPath)
    }

    $RemovedCount = 0
    $Status = 'Completed'

    foreach ($CleanupSpec in $CleanupSpecs) {
        $CleanupPath = Resolve-TrustedDirectoryPath -Path $CleanupSpec.Path -AllowedRoots $CleanupSpec.AllowedRoots
        if ([string]::IsNullOrWhiteSpace($CleanupPath)) {
            continue
        }

        foreach ($CleanupItem in (Get-SafeChildItems -Path $CleanupPath)) {
            if ($PSCmdlet.ShouldProcess($CleanupItem.FullName, 'Remove item')) {
                try {
                    Remove-Item -LiteralPath $CleanupItem.FullName -Recurse -Force -ErrorAction Stop
                    $RemovedCount++
                }
                catch {
                    Write-Verbose ('Failed to remove cleanup item: {0}' -f $CleanupItem.FullName)
                }
            }
        }
    }

    if ($PSCmdlet.ShouldProcess('Recycle Bin', 'Clear')) {
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
    }

    $TrustedThumbDirectory = Resolve-TrustedDirectoryPath -Path $ThumbCacheDirectory -AllowedRoots @($LocalApplicationDataPath)
    if (-not [string]::IsNullOrWhiteSpace($TrustedThumbDirectory)) {
        try {
            $ThumbCacheFiles = @(
                Get-ChildItem -LiteralPath $TrustedThumbDirectory -File -Filter $ThumbCacheFilter -ErrorAction Stop |
                    Where-Object { -not (Test-IsReparsePoint -Item $_) }
            )
        }
        catch {
            $ThumbCacheFiles = @()
        }

        foreach ($ThumbCacheFile in $ThumbCacheFiles) {
            if ($PSCmdlet.ShouldProcess($ThumbCacheFile.FullName, 'Remove thumb cache')) {
                try {
                    Remove-Item -LiteralPath $ThumbCacheFile.FullName -Force -ErrorAction Stop
                    $RemovedCount++
                }
                catch {
                    Write-Verbose ('Failed to remove thumb cache item: {0}' -f $ThumbCacheFile.FullName)
                }
            }
        }
    }

    if ($RemoveWindowsOld) {
        $TrustedWindowsOldPath = Resolve-TrustedDirectoryPath -Path $WindowsOldPath -AllowedRoots @($env:SystemDrive + '\')
        if (-not [string]::IsNullOrWhiteSpace($TrustedWindowsOldPath) -and
            $PSCmdlet.ShouldProcess($TrustedWindowsOldPath, 'Remove directory')) {
            Remove-Item -LiteralPath $TrustedWindowsOldPath -Recurse -Force -ErrorAction Stop
            $RemovedCount++
        }
    }

    if ($RunComponentCleanup -and $PSCmdlet.ShouldProcess('Windows component store', 'Run DISM cleanup')) {
        $DismOutput = & $DismPath /Online /Cleanup-Image /StartComponentCleanup 2>&1
        if ($LASTEXITCODE -ne 0) {
            throw ('DISM cleanup failed (exit {0}): {1}' -f $LASTEXITCODE, ($DismOutput -join ' '))
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
        -LocalApplicationDataPath $LocalApplicationDataPath `
        -WindowsOldPath $ScriptConfig.WindowsOldPath `
        -RemoveWindowsOld $ScriptConfig.RemoveWindowsOld `
        -RunComponentCleanup $ScriptConfig.RunComponentCleanup `
        -DismPath $ScriptConfig.DismPath
}
catch {
    Write-Error -ErrorRecord $_
    exit 1
}
