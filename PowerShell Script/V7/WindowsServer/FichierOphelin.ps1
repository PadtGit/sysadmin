#Requires -Version 7.0
#Requires -RunAsAdministrator

[CmdletBinding(SupportsShouldProcess)]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$ScriptConfig = @{
    InstallerPath = Join-Path -Path $env:SystemRoot -ChildPath 'Installer'
    BackupFolder  = 'C:\InstallerOrphans'
    RegistryRoot  = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData'
}

function Invoke-MoveInstallerOrphans {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$InstallerPath,

        [Parameter(Mandatory)]
        [string]$BackupFolder,

        [Parameter(Mandatory)]
        [string]$RegistryRoot
    )

    if (-not (Test-Path -LiteralPath $BackupFolder)) {
        New-Item -ItemType Directory -Path $BackupFolder -Force | Out-Null
    }

    $knownPackages = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    Get-ChildItem -Path $RegistryRoot -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
        $packagePath = (Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue).LocalPackage
        if (-not [string]::IsNullOrWhiteSpace($packagePath)) {
            [void]$knownPackages.Add($packagePath)
        }
    }

    if ($knownPackages.Count -eq 0) {
        throw 'No installer package references were found. Aborting to avoid moving valid files.'
    }

    $installerFiles = @(
        Get-ChildItem -LiteralPath $InstallerPath -File -ErrorAction Stop |
            Where-Object { $_.Extension -in '.msi', '.msp' }
    )

    $orphanedFiles = @(
        $installerFiles | Where-Object { -not $knownPackages.Contains($_.FullName) }
    )

    $movedCount = 0
    foreach ($file in $orphanedFiles) {
        $destination = Join-Path -Path $BackupFolder -ChildPath $file.Name

        if (Test-Path -LiteralPath $destination) {
            continue
        }

        if ($PSCmdlet.ShouldProcess($file.FullName, 'Move installer file')) {
            Move-Item -LiteralPath $file.FullName -Destination $destination -ErrorAction Stop
            $movedCount++
        }
    }

    [pscustomobject]@{
        InstallerPath = $InstallerPath
        BackupFolder  = $BackupFolder
        OrphanCount   = $orphanedFiles.Count
        MovedCount    = $movedCount
    }
}

try {
    Invoke-MoveInstallerOrphans `
        -InstallerPath $ScriptConfig.InstallerPath `
        -BackupFolder $ScriptConfig.BackupFolder `
        -RegistryRoot $ScriptConfig.RegistryRoot
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
