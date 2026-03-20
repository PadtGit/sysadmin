#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess = $true)]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$RequireAdmin = $true
$IsAdministrator = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$CleanupPaths = @(
    $env:TEMP,
    (Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Temp'),
    (Join-Path -Path $env:SystemRoot -ChildPath 'Temp'),
    (Join-Path -Path $env:LOCALAPPDATA -ChildPath 'D3DSCache'),
    (Join-Path -Path $env:SystemRoot -ChildPath 'SoftwareDistribution\DeliveryOptimization')
)
$ThumbCacheDirectory = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Microsoft\Windows\Explorer'
$ThumbCacheFilter = 'thumbcache_*.db'
$WindowsOldPath = Join-Path -Path $env:SystemDrive -ChildPath 'Windows.old'
$RemoveWindowsOld = $false
$RunComponentCleanup = $true
$DismPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\Dism.exe'

function Invoke-AdvancedWindowsCleanup {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [bool]$RequireAdmin,

        [Parameter(Mandatory = $true)]
        [bool]$IsAdministrator,

        [Parameter(Mandatory = $true)]
        [string[]]$CleanupPaths,

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
        throw 'Run this script in an elevated PowerShell 5.1 session.'
    }

    if ($WhatIfPreference -and -not $IsAdministrator) {
        return [pscustomobject]@{
            CleanupPathCount = $CleanupPaths.Count
            RemovedCount     = 0
            RemoveWindowsOld = $RemoveWindowsOld
            ComponentCleanup = $RunComponentCleanup
            Status           = 'Skipped'
            Reason           = 'AdminPreviewRequired'
        }
    }

    $RemovedCount = 0
    $Status = 'Completed'

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
            if ($PSCmdlet.ShouldProcess($CleanupItem.FullName, 'Remove item')) {
                Remove-Item -LiteralPath $CleanupItem.FullName -Recurse -Force -ErrorAction SilentlyContinue
                $RemovedCount++
            }
        }
    }

    if ($PSCmdlet.ShouldProcess('Recycle Bin', 'Clear')) {
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
    }

    if (Test-Path -LiteralPath $ThumbCacheDirectory -PathType Container) {
        try {
            $ThumbCacheFiles = @(Get-ChildItem -LiteralPath $ThumbCacheDirectory -File -Filter $ThumbCacheFilter -ErrorAction Stop)
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

    if ($RemoveWindowsOld -and (Test-Path -LiteralPath $WindowsOldPath -PathType Container)) {
        if ($PSCmdlet.ShouldProcess($WindowsOldPath, 'Remove directory')) {
            Remove-Item -LiteralPath $WindowsOldPath -Recurse -Force -ErrorAction Stop
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
        CleanupPathCount = $CleanupPaths.Count
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
        -CleanupPaths $CleanupPaths `
        -ThumbCacheDirectory $ThumbCacheDirectory `
        -ThumbCacheFilter $ThumbCacheFilter `
        -WindowsOldPath $WindowsOldPath `
        -RemoveWindowsOld $RemoveWindowsOld `
        -RunComponentCleanup $RunComponentCleanup `
        -DismPath $DismPath
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
