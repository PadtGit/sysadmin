#Requires -Version 7.0

[CmdletBinding(SupportsShouldProcess = $true)]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$CommonApplicationDataPath = [Environment]::GetFolderPath('CommonApplicationData')

$RequireAdmin = $true
$IsAdministrator = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScriptConfig = @{
    StorageRoot   = Join-Path -Path $CommonApplicationDataPath -ChildPath 'sysadmin-main'
    InstallerPath = 'C:\Windows\Installer'
    BackupPath    = Join-Path -Path $CommonApplicationDataPath -ChildPath 'sysadmin-main\Quarantine\InstallerOrphans'
    Contexts      = @(1, 2, 4)
    PatchState    = 7
}

function Test-PathWithinAllowedRoot {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string[]]$AllowedRoots
    )

    $normalizedPath = [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
    foreach ($allowedRoot in $AllowedRoots) {
        if ([string]::IsNullOrWhiteSpace($allowedRoot)) {
            continue
        }

        $normalizedRoot = [System.IO.Path]::GetFullPath($allowedRoot).TrimEnd('\')
        if ($normalizedPath.Equals($normalizedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }

        if ($normalizedPath.StartsWith(($normalizedRoot + '\'), [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    return $false
}

function Test-IsReparsePoint {
    param(
        [Parameter(Mandatory)]
        [System.IO.FileSystemInfo]$Item
    )

    return (($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Set-RestrictedDirectoryAcl {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $directory = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if (-not $directory.PSIsContainer) {
        throw ('Secure directory path must be a directory: {0}' -f $Path)
    }

    if (Test-IsReparsePoint -Item $directory) {
        throw ('Secure directory path must not be a reparse point: {0}' -f $Path)
    }

    $currentUserSid = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $administratorsSid = [Security.Principal.SecurityIdentifier]::new([Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid, $null)
    $systemSid = [Security.Principal.SecurityIdentifier]::new([Security.Principal.WellKnownSidType]::LocalSystemSid, $null)
    $inheritanceFlags = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
    $propagationFlags = [System.Security.AccessControl.PropagationFlags]::None
    $rights = [System.Security.AccessControl.FileSystemRights]::FullControl
    $accessType = [System.Security.AccessControl.AccessControlType]::Allow
    $acl = [System.Security.AccessControl.DirectorySecurity]::new()
    $acl.SetAccessRuleProtection($true, $false)

    foreach ($sidGroup in @($currentUserSid, $administratorsSid, $systemSid) | Group-Object Value) {
        $rule = [System.Security.AccessControl.FileSystemAccessRule]::new(
            $sidGroup.Group[0],
            $rights,
            $inheritanceFlags,
            $propagationFlags,
            $accessType
        )
        [void]$acl.AddAccessRule($rule)
    }

    if ($PSCmdlet.ShouldProcess($directory.FullName, 'Apply restricted directory ACL')) {
        Set-Acl -LiteralPath $directory.FullName -AclObject $acl
    }
}

function Resolve-SecureDirectory {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string[]]$AllowedRoots
    )

    $normalizedPath = [System.IO.Path]::GetFullPath($Path)
    if (-not (Test-PathWithinAllowedRoot -Path $normalizedPath -AllowedRoots $AllowedRoots)) {
        throw ('Directory path is outside the trusted root: {0}' -f $normalizedPath)
    }

    foreach ($allowedRoot in $AllowedRoots) {
        if ([string]::IsNullOrWhiteSpace($allowedRoot) -or -not (Test-Path -LiteralPath $allowedRoot -PathType Container)) {
            continue
        }

        $allowedRootItem = Get-Item -LiteralPath $allowedRoot -Force -ErrorAction Stop
        if (Test-IsReparsePoint -Item $allowedRootItem) {
            throw ('Trusted root must not be a reparse point: {0}' -f $allowedRootItem.FullName)
        }
    }

    if (Test-Path -LiteralPath $normalizedPath -PathType Container) {
        $directoryItem = Get-Item -LiteralPath $normalizedPath -Force -ErrorAction Stop
        if (Test-IsReparsePoint -Item $directoryItem) {
            throw ('Directory path must not be a reparse point: {0}' -f $normalizedPath)
        }
    }
    elseif (-not $WhatIfPreference) {
        New-Item -ItemType Directory -Path $normalizedPath -Force | Out-Null
    }

    if (-not $WhatIfPreference -and (Test-Path -LiteralPath $normalizedPath -PathType Container)) {
        Set-RestrictedDirectoryAcl -Path $normalizedPath
    }

    return $normalizedPath
}

function Invoke-MoveOrphanedInstallerFiles {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [bool]$RequireAdmin,

        [Parameter(Mandatory = $true)]
        [bool]$IsAdministrator,

        [Parameter(Mandatory)]
        [string]$InstallerPath,

        [Parameter(Mandatory)]
        [string]$BackupPath,

        [Parameter(Mandatory)]
        [int[]]$Contexts,

        [Parameter(Mandatory)]
        [int]$PatchState
    )

    if ($RequireAdmin -and -not $WhatIfPreference -and -not $IsAdministrator) {
        throw 'Run this script in an elevated PowerShell 7 session.'
    }

    if (-not (Test-Path -LiteralPath $InstallerPath)) {
        throw 'Installer path was not found.'
    }

    $installerDirectory = Get-Item -LiteralPath $InstallerPath -Force -ErrorAction Stop
    if (Test-IsReparsePoint -Item $installerDirectory) {
        throw ('Installer path must not be a reparse point: {0}' -f $installerDirectory.FullName)
    }

    $secureBackupPath = Resolve-SecureDirectory -Path $BackupPath -AllowedRoots @($ScriptConfig.StorageRoot)

    $references = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $installer = $null
    $movedCount = 0
    $status = 'Completed'

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
                    Write-Verbose 'Unable to read one installed product reference from Windows Installer.'
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
                            Write-Verbose 'Unable to read one patch reference from Windows Installer.'
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
                Write-Verbose 'Unable to read one global patch reference from Windows Installer.'
            }
        }
    }
    finally {
        if ($null -ne $installer) {
            [System.Runtime.InteropServices.Marshal]::ReleaseComObject($installer) | Out-Null
        }
    }

    if ($references.Count -eq 0) {
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

        throw 'No Windows Installer references were found. Aborting.'
    }

    $installerFiles = @(
        Get-ChildItem -LiteralPath $InstallerPath -File -ErrorAction Stop |
            Where-Object { $_.Extension -in '.msi', '.msp' -and -not (Test-IsReparsePoint -Item $_) }
    )

    $orphanedFiles = @(
        $installerFiles | Where-Object { -not $references.Contains($_.FullName) }
    )

    foreach ($file in $orphanedFiles) {
        $destination = Join-Path -Path $secureBackupPath -ChildPath $file.Name

        if (Test-Path -LiteralPath $destination) {
            $destination = Join-Path -Path $secureBackupPath -ChildPath (
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

    if ($WhatIfPreference) {
        $status = 'WhatIf'
    }

    [pscustomobject]@{
        InstallerPath = $InstallerPath
        BackupPath    = $secureBackupPath
        FileCount     = $installerFiles.Count
        OrphanCount   = $orphanedFiles.Count
        MovedCount    = $movedCount
        Status        = $status
        Reason        = ''
    }
}

try {
    Invoke-MoveOrphanedInstallerFiles `
        -RequireAdmin $RequireAdmin `
        -IsAdministrator $IsAdministrator `
        -InstallerPath $ScriptConfig.InstallerPath `
        -BackupPath $ScriptConfig.BackupPath `
        -Contexts $ScriptConfig.Contexts `
        -PatchState $ScriptConfig.PatchState
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
