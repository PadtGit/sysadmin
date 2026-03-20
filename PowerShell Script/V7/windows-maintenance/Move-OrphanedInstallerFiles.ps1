#Requires -Version 7.0
#Requires -RunAsAdministrator

[CmdletBinding(SupportsShouldProcess)]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$ScriptConfig = @{
    InstallerPath = 'C:\Windows\Installer'
    BackupPath    = 'C:\FichierOrphelin'
    Contexts      = @(1, 2, 4)
    PatchState    = 7
}

function Invoke-MoveOrphanedInstallerFiles {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$InstallerPath,

        [Parameter(Mandatory)]
        [string]$BackupPath,

        [Parameter(Mandatory)]
        [int[]]$Contexts,

        [Parameter(Mandatory)]
        [int]$PatchState
    )

    if (-not (Test-Path -LiteralPath $InstallerPath)) {
        throw 'Installer path was not found.'
    }

    if (-not (Test-Path -LiteralPath $BackupPath)) {
        New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null
    }

    $references = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $installer = $null
    $movedCount = 0

    try {
        $installer = New-Object -ComObject WindowsInstaller.Installer

        foreach ($context in $Contexts) {
            try {
                $products = @($installer.ProductsEx('', '', $context))
            }
            catch {
                $products = @()
            }

            foreach ($product in $products) {
                $productCode = $null
                $productPackage = $null

                try {
                    $productPackage = [string]$product.InstallProperty('LocalPackage')
                    $productCode = [string]$product.ProductCode()
                }
                catch {
                }

                if (-not [string]::IsNullOrWhiteSpace($productPackage)) {
                    [void]$references.Add($productPackage)
                }

                if (-not [string]::IsNullOrWhiteSpace($productCode)) {
                    try {
                        $patches = @($installer.PatchesEx($productCode, '', $context, $PatchState))
                    }
                    catch {
                        $patches = @()
                    }

                    foreach ($patch in $patches) {
                        try {
                            $patchPackage = [string]$patch.PatchProperty('LocalPackage')
                            if (-not [string]::IsNullOrWhiteSpace($patchPackage)) {
                                [void]$references.Add($patchPackage)
                            }
                        }
                        catch {
                        }
                    }
                }
            }
        }

        try {
            $globalPatches = @($installer.PatchesEx('', '', $PatchState, $PatchState))
        }
        catch {
            $globalPatches = @()
        }

        foreach ($patch in $globalPatches) {
            try {
                $patchPackage = [string]$patch.PatchProperty('LocalPackage')
                if (-not [string]::IsNullOrWhiteSpace($patchPackage)) {
                    [void]$references.Add($patchPackage)
                }
            }
            catch {
            }
        }
    }
    finally {
        if ($null -ne $installer) {
            [System.Runtime.InteropServices.Marshal]::ReleaseComObject($installer) | Out-Null
        }
    }

    if ($references.Count -eq 0) {
        throw 'No Windows Installer references were found. Aborting.'
    }

    $installerFiles = @(
        Get-ChildItem -LiteralPath $InstallerPath -File -ErrorAction Stop |
            Where-Object { $_.Extension -in '.msi', '.msp' }
    )

    $orphanedFiles = @(
        $installerFiles | Where-Object { -not $references.Contains($_.FullName) }
    )

    foreach ($file in $orphanedFiles) {
        $destination = Join-Path -Path $BackupPath -ChildPath $file.Name

        if (Test-Path -LiteralPath $destination) {
            $destination = Join-Path -Path $BackupPath -ChildPath (
                '{0}_{1}{2}' -f
                [System.IO.Path]::GetFileNameWithoutExtension($file.Name),
                (Get-Date -Format 'yyyyMMddHHmmssfff'),
                [System.IO.Path]::GetExtension($file.Name)
            )
        }

        if ($PSCmdlet.ShouldProcess($file.FullName, ("Move to {0}" -f $destination))) {
            Move-Item -LiteralPath $file.FullName -Destination $destination -Force -ErrorAction Stop
            $movedCount++
        }
    }

    [pscustomobject]@{
        InstallerPath = $InstallerPath
        BackupPath    = $BackupPath
        FileCount     = $installerFiles.Count
        OrphanCount   = $orphanedFiles.Count
        MovedCount    = $movedCount
    }
}

try {
    Invoke-MoveOrphanedInstallerFiles `
        -InstallerPath $ScriptConfig.InstallerPath `
        -BackupPath $ScriptConfig.BackupPath `
        -Contexts $ScriptConfig.Contexts `
        -PatchState $ScriptConfig.PatchState
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
