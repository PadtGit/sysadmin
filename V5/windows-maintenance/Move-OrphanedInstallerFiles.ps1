#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess = $true)]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$RequireAdmin = $true
$IsAdministrator = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$InstallerPath = Join-Path -Path $env:SystemRoot -ChildPath 'Installer'
$BackupPath = 'C:\FichierOrphelin'
$RegistryRoot = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData'
$AllowedExtensions = @('.msi', '.msp')

function Invoke-OrphanedInstallerMove {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [bool]$RequireAdmin,

        [Parameter(Mandatory = $true)]
        [bool]$IsAdministrator,

        [Parameter(Mandatory = $true)]
        [string]$InstallerPath,

        [Parameter(Mandatory = $true)]
        [string]$BackupPath,

        [Parameter(Mandatory = $true)]
        [string]$RegistryRoot,

        [Parameter(Mandatory = $true)]
        [string[]]$AllowedExtensions
    )

    if ($RequireAdmin -and -not $WhatIfPreference -and -not $IsAdministrator) {
        throw 'Run this script in an elevated PowerShell 5.1 session.'
    }

    if (-not (Test-Path -LiteralPath $InstallerPath -PathType Container)) {
        throw ('Installer path not found: {0}' -f $InstallerPath)
    }

    if (-not (Test-Path -LiteralPath $BackupPath -PathType Container)) {
        if ($PSCmdlet.ShouldProcess($BackupPath, 'Create directory')) {
            New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null
        }
    }

    $KnownPackages = @{}
    $MovedCount = 0
    $OrphanCount = 0
    $Status = 'Completed'

    foreach ($RegistryItem in @(Get-ChildItem -Path $RegistryRoot -Recurse -ErrorAction SilentlyContinue)) {
        try {
            $LocalPackage = [string](Get-ItemProperty -LiteralPath $RegistryItem.PSPath -ErrorAction Stop).LocalPackage
        }
        catch {
            $LocalPackage = ''
        }

        if (-not [string]::IsNullOrWhiteSpace($LocalPackage)) {
            $KnownPackages[$LocalPackage.ToLowerInvariant()] = $true
        }
    }

    if ($KnownPackages.Count -eq 0) {
        if ($WhatIfPreference) {
            return [pscustomobject]@{
                InstallerPath = $InstallerPath
                BackupPath    = $BackupPath
                FileCount     = 0
                OrphanCount   = 0
                MovedCount    = 0
                Status        = 'Skipped'
                Reason        = 'NoReferencesFound'
            }
        }

        throw 'No installer references were found.'
    }

    $InstallerFiles = @(Get-ChildItem -LiteralPath $InstallerPath -File -ErrorAction Stop | Where-Object { $AllowedExtensions -contains $_.Extension.ToLowerInvariant() })

    foreach ($InstallerFile in $InstallerFiles) {
        if ($KnownPackages.ContainsKey($InstallerFile.FullName.ToLowerInvariant())) {
            continue
        }

        $OrphanCount++
        $DestinationPath = Join-Path -Path $BackupPath -ChildPath $InstallerFile.Name

        if (Test-Path -LiteralPath $DestinationPath) {
            $DestinationPath = Join-Path -Path $BackupPath -ChildPath ('{0}_{1}{2}' -f [System.IO.Path]::GetFileNameWithoutExtension($InstallerFile.Name), (Get-Date -Format 'yyyyMMddHHmmssfff'), [System.IO.Path]::GetExtension($InstallerFile.Name))
        }

        if ($PSCmdlet.ShouldProcess($InstallerFile.FullName, ('Move to {0}' -f $DestinationPath))) {
            Move-Item -LiteralPath $InstallerFile.FullName -Destination $DestinationPath -Force -ErrorAction Stop
            $MovedCount++
        }
    }

    if ($WhatIfPreference) {
        $Status = 'WhatIf'
    }

    [pscustomobject]@{
        InstallerPath = $InstallerPath
        BackupPath    = $BackupPath
        FileCount     = $InstallerFiles.Count
        OrphanCount   = $OrphanCount
        MovedCount    = $MovedCount
        Status        = $Status
        Reason        = ''
    }
}

try {
    Invoke-OrphanedInstallerMove `
        -RequireAdmin $RequireAdmin `
        -IsAdministrator $IsAdministrator `
        -InstallerPath $InstallerPath `
        -BackupPath $BackupPath `
        -RegistryRoot $RegistryRoot `
        -AllowedExtensions $AllowedExtensions
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
