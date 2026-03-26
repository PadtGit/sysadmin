#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess = $true)]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$CommonApplicationDataPath = [Environment]::GetFolderPath('CommonApplicationData')

$RequireAdmin = $true
$IsAdministrator = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$StorageRoot = Join-Path -Path $CommonApplicationDataPath -ChildPath 'sysadmin-main'
$InstallerPath = 'C:\Windows\Installer'
$BackupPath = Join-Path -Path $CommonApplicationDataPath -ChildPath 'sysadmin-main\Quarantine\InstallerOrphans'
$RegistryRoot = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Installer\UserData'
$AllowedExtensions = @('.msi', '.msp')

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

function Set-RestrictedDirectoryAcl {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $Directory = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if (-not $Directory.PSIsContainer) {
        throw ('Secure directory path must be a directory: {0}' -f $Path)
    }

    if (Test-IsReparsePoint -Item $Directory) {
        throw ('Secure directory path must not be a reparse point: {0}' -f $Path)
    }

    $CurrentUserSid = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $AdministratorsSid = [Security.Principal.SecurityIdentifier]::new([Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid, $null)
    $SystemSid = [Security.Principal.SecurityIdentifier]::new([Security.Principal.WellKnownSidType]::LocalSystemSid, $null)
    $InheritanceFlags = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
    $PropagationFlags = [System.Security.AccessControl.PropagationFlags]::None
    $Rights = [System.Security.AccessControl.FileSystemRights]::FullControl
    $AccessType = [System.Security.AccessControl.AccessControlType]::Allow
    $Acl = [System.Security.AccessControl.DirectorySecurity]::new()
    $Acl.SetAccessRuleProtection($true, $false)

    foreach ($SidGroup in @($CurrentUserSid, $AdministratorsSid, $SystemSid) | Group-Object Value) {
        $Rule = [System.Security.AccessControl.FileSystemAccessRule]::new(
            $SidGroup.Group[0],
            $Rights,
            $InheritanceFlags,
            $PropagationFlags,
            $AccessType
        )
        [void]$Acl.AddAccessRule($Rule)
    }

    if ($PSCmdlet.ShouldProcess($Directory.FullName, 'Apply restricted directory ACL')) {
        Set-Acl -LiteralPath $Directory.FullName -AclObject $Acl
    }
}

function Resolve-SecureDirectory {
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

    if (Test-Path -LiteralPath $NormalizedPath -PathType Container) {
        $DirectoryItem = Get-Item -LiteralPath $NormalizedPath -Force -ErrorAction Stop
        if (Test-IsReparsePoint -Item $DirectoryItem) {
            throw ('Directory path must not be a reparse point: {0}' -f $NormalizedPath)
        }
    }
    elseif (-not $WhatIfPreference) {
        New-Item -ItemType Directory -Path $NormalizedPath -Force | Out-Null
    }

    if (-not $WhatIfPreference -and (Test-Path -LiteralPath $NormalizedPath -PathType Container)) {
        Set-RestrictedDirectoryAcl -Path $NormalizedPath
    }

    return $NormalizedPath
}

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

    $InstallerDirectory = Get-Item -LiteralPath $InstallerPath -Force -ErrorAction Stop
    if (Test-IsReparsePoint -Item $InstallerDirectory) {
        throw ('Installer path must not be a reparse point: {0}' -f $InstallerDirectory.FullName)
    }

    $SecureBackupPath = Resolve-SecureDirectory -Path $BackupPath -AllowedRoots @($StorageRoot)

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

    $InstallerFiles = @(
        Get-ChildItem -LiteralPath $InstallerPath -File -ErrorAction Stop |
            Where-Object { $AllowedExtensions -contains $_.Extension.ToLowerInvariant() -and -not (Test-IsReparsePoint -Item $_) }
    )

    foreach ($InstallerFile in $InstallerFiles) {
        if ($KnownPackages.ContainsKey($InstallerFile.FullName.ToLowerInvariant())) {
            continue
        }

        $OrphanCount++
        $DestinationPath = Join-Path -Path $SecureBackupPath -ChildPath $InstallerFile.Name

        if (Test-Path -LiteralPath $DestinationPath) {
            $DestinationPath = Join-Path -Path $SecureBackupPath -ChildPath ('{0}_{1}{2}' -f [System.IO.Path]::GetFileNameWithoutExtension($InstallerFile.Name), (Get-Date -Format 'yyyyMMddHHmmssfff'), [System.IO.Path]::GetExtension($InstallerFile.Name))
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
        BackupPath    = $SecureBackupPath
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
