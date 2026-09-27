#Requires -Version 7.0

[CmdletBinding(SupportsShouldProcess = $true)]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$LocalApplicationDataPath = [Environment]::GetFolderPath('LocalApplicationData')

$ScriptConfig = @{
    StorageRoot          = Join-Path -Path $LocalApplicationDataPath -ChildPath 'sysadmin-main'
    OutputDirectory      = Join-Path -Path $LocalApplicationDataPath -ChildPath 'sysadmin-main\Exports\Printers'
    OutputFileNamePrefix = 'printers-full'
    Properties           = @(
        'Name',
        'ComputerName',
        'Type',
        'DriverName',
        'PortName',
        'Shared',
        'ShareName',
        'Published',
        'Queued',
        'Direct',
        'KeepPrintedJobs',
        'PermissionSDDL',
        'PrinterStatus',
        'RenderingMode',
        'WorkflowPolicy'
    )
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

    $CreatedDirectory = $false

    if (Test-Path -LiteralPath $NormalizedPath -PathType Container) {
        $DirectoryItem = Get-Item -LiteralPath $NormalizedPath -Force -ErrorAction Stop
        if (Test-IsReparsePoint -Item $DirectoryItem) {
            throw ('Directory path must not be a reparse point: {0}' -f $NormalizedPath)
        }
    }
    elseif (-not $WhatIfPreference) {
        New-Item -ItemType Directory -Path $NormalizedPath -Force | Out-Null
        $CreatedDirectory = $true
    }

    if ($CreatedDirectory) {
        Set-RestrictedDirectoryAcl -Path $NormalizedPath
    }

    return $NormalizedPath
}

function Get-UniqueChildPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Directory,

        [Parameter(Mandatory = $true)]
        [string]$FileNamePrefix,

        [Parameter(Mandatory = $true)]
        [string]$Extension
    )

    $Timestamp = Get-Date -Format 'yyyyMMdd-HHmmssfff'
    $CandidatePath = Join-Path -Path $Directory -ChildPath ('{0}-{1}{2}' -f $FileNamePrefix, $Timestamp, $Extension)
    $Counter = 1

    while (Test-Path -LiteralPath $CandidatePath -PathType Leaf) {
        $CandidatePath = Join-Path -Path $Directory -ChildPath ('{0}-{1}-{2}{3}' -f $FileNamePrefix, $Timestamp, $Counter, $Extension)
        $Counter++
    }

    return $CandidatePath
}

function Invoke-ExportPrinterListFull {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutputDirectory,

        [Parameter(Mandatory = $true)]
        [string]$OutputFileNamePrefix,

        [Parameter(Mandatory = $true)]
        [string[]]$Properties
    )

    $SecureOutputDirectory = Resolve-SecureDirectory -Path $OutputDirectory -AllowedRoots @($ScriptConfig.StorageRoot)
    $OutputPath = Get-UniqueChildPath -Directory $SecureOutputDirectory -FileNamePrefix $OutputFileNamePrefix -Extension '.csv'

    try {
        $Printers = @(
            Get-Printer -ErrorAction Stop |
                Sort-Object -Property Name
        )
    }
    catch {
        if ($WhatIfPreference) {
            return [pscustomobject]@{
                OutputPath    = $OutputPath
                PrinterCount  = 0
                ExportProfile = 'Full'
                Status        = 'Skipped'
                Reason        = 'GetPrinterUnavailable'
            }
        }

        throw
    }

    if ($PSCmdlet.ShouldProcess($OutputPath, 'Export printer list')) {
        $Printers |
            Select-Object -Property $Properties |
            Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
    }

    [pscustomobject]@{
        OutputPath    = $OutputPath
        PrinterCount  = $Printers.Count
        ExportProfile = 'Full'
        Status        = $(if ($WhatIfPreference) { 'WhatIf' } else { 'Completed' })
        Reason        = ''
    }
}

try {
    Invoke-ExportPrinterListFull `
        -OutputDirectory $ScriptConfig.OutputDirectory `
        -OutputFileNamePrefix $ScriptConfig.OutputFileNamePrefix `
        -Properties $ScriptConfig.Properties
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
