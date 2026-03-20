#Requires -Version 7.0
#Requires -RunAsAdministrator

[CmdletBinding(SupportsShouldProcess)]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$ScriptConfig = @{
    CleanupPaths = @(
        $env:TEMP,
        (Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Temp'),
        (Join-Path -Path $env:SystemRoot -ChildPath 'Temp'),
        (Join-Path -Path $env:LOCALAPPDATA -ChildPath 'D3DSCache'),
        (Join-Path -Path $env:SystemRoot -ChildPath 'SoftwareDistribution\DeliveryOptimization')
    )
    ThumbCacheDirectory = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Microsoft\Windows\Explorer'
    ThumbCacheFilter    = 'thumbcache_*.db'
    WindowsOldPath      = Join-Path -Path $env:SystemDrive -ChildPath 'Windows.old'
    RemoveWindowsOld    = $false
    RunComponentCleanup = $true
}

function Invoke-ClearWindowsSystem {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string[]]$CleanupPaths,

        [Parameter(Mandatory)]
        [string]$ThumbCacheDirectory,

        [Parameter(Mandatory)]
        [string]$ThumbCacheFilter,

        [Parameter(Mandatory)]
        [string]$WindowsOldPath,

        [Parameter(Mandatory)]
        [bool]$RemoveWindowsOld,

        [Parameter(Mandatory)]
        [bool]$RunComponentCleanup
    )

    foreach ($path in $CleanupPaths) {
        if (-not (Test-Path -LiteralPath $path)) {
            continue
        }

        Get-ChildItem -LiteralPath $path -Force -ErrorAction SilentlyContinue | ForEach-Object {
            if ($PSCmdlet.ShouldProcess($_.FullName, 'Remove item')) {
                Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    if ($PSCmdlet.ShouldProcess('Recycle Bin', 'Clear')) {
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
    }

    if (Test-Path -LiteralPath $ThumbCacheDirectory) {
        Get-ChildItem -LiteralPath $ThumbCacheDirectory -File -Filter $ThumbCacheFilter -ErrorAction SilentlyContinue | ForEach-Object {
            if ($PSCmdlet.ShouldProcess($_.FullName, 'Remove thumb cache')) {
                Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
            }
        }
    }

    if ($RemoveWindowsOld -and (Test-Path -LiteralPath $WindowsOldPath)) {
        if ($PSCmdlet.ShouldProcess($WindowsOldPath, 'Remove directory')) {
            Remove-Item -LiteralPath $WindowsOldPath -Recurse -Force -ErrorAction Stop
        }
    }

    if ($RunComponentCleanup -and $PSCmdlet.ShouldProcess('Windows component store', 'Cleanup')) {
        & DISM.exe /Online /Cleanup-Image /StartComponentCleanup | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw 'DISM component cleanup failed.'
        }
    }

    Write-Output 'Windows system cleanup completed.'
}

try {
    Invoke-ClearWindowsSystem `
        -CleanupPaths $ScriptConfig.CleanupPaths `
        -ThumbCacheDirectory $ScriptConfig.ThumbCacheDirectory `
        -ThumbCacheFilter $ScriptConfig.ThumbCacheFilter `
        -WindowsOldPath $ScriptConfig.WindowsOldPath `
        -RemoveWindowsOld $ScriptConfig.RemoveWindowsOld `
        -RunComponentCleanup $ScriptConfig.RunComponentCleanup
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
