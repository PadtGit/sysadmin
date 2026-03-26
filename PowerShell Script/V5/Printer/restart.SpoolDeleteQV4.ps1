#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess = $true)]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$CommonApplicationDataPath = [Environment]::GetFolderPath('CommonApplicationData')

$RequireAdmin = $true
$IsAdministrator = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$StorageRoot = Join-Path -Path $CommonApplicationDataPath -ChildPath 'sysadmin-main'
$ServiceName = 'Spooler'
$SpoolDirectory = Join-Path -Path $env:SystemRoot -ChildPath 'System32\spool\PRINTERS'
$TimeoutSeconds = 30
$LogDirectory = Join-Path -Path $CommonApplicationDataPath -ChildPath 'sysadmin-main\Logs\Printer'
$LogFilePrefix = 'print-queue'
$AllowedExtensions = @('.spl', '.shd')
$TemporaryFilePattern = 'FP*.tmp'

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
        Set-Acl -LiteralPath $Directory.FullName -AclObject $Acl -ErrorAction Stop
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
    $GuidSuffix = [guid]::NewGuid().ToString('N').Substring(0, 8)
    return (Join-Path -Path $Directory -ChildPath ('{0}-{1}-{2}{3}' -f $FileNamePrefix, $Timestamp, $GuidSuffix, $Extension))
}

function Invoke-LoggedPrintQueueCleanup {
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory = $true)]
        [bool]$RequireAdmin,

        [Parameter(Mandatory = $true)]
        [bool]$IsAdministrator,

        [Parameter(Mandatory = $true)]
        [string]$ServiceName,

        [Parameter(Mandatory = $true)]
        [string]$SpoolDirectory,

        [Parameter(Mandatory = $true)]
        [int]$TimeoutSeconds,

        [Parameter(Mandatory = $true)]
        [string]$LogDirectory,

        [Parameter(Mandatory = $true)]
        [string]$LogFilePrefix,

        [Parameter(Mandatory = $true)]
        [string[]]$AllowedExtensions,

        [Parameter()]
        [string]$TemporaryFilePattern = 'FP*.tmp'
    )

    if ($RequireAdmin -and -not $WhatIfPreference -and -not $IsAdministrator) {
        throw 'Run this script in an elevated PowerShell 5.1 session.'
    }

    $SecureLogDirectory = Resolve-SecureDirectory -Path $LogDirectory -AllowedRoots @($StorageRoot)
    $LogPath = Get-UniqueChildPath -Directory $SecureLogDirectory -FileNamePrefix $LogFilePrefix -Extension '.log'
    $TranscriptStarted = $false
    $DeletedCount = 0
    $Status = 'Completed'
    $Files = @()
    $Service = Get-Service -Name $ServiceName -ErrorAction Stop
    $ServiceWasRunning = $Service.Status -eq [System.ServiceProcess.ServiceControllerStatus]::Running
    $ServiceWasStopped = $false

    if (-not $WhatIfPreference -and $PSCmdlet.ShouldProcess($LogPath, 'Start transcript')) {
        Start-Transcript -Path $LogPath -NoClobber | Out-Null
        $TranscriptStarted = $true
    }

    try {
        if ($ServiceWasRunning -and $PSCmdlet.ShouldProcess($ServiceName, 'Stop Print Spooler')) {
            Stop-Service -Name $ServiceName -Force -ErrorAction Stop
            $Service.Refresh()
            $Service.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Stopped, [TimeSpan]::FromSeconds($TimeoutSeconds))
            $ServiceWasStopped = $true
        }

        try {
            $Files = @(
                Get-ChildItem -LiteralPath $SpoolDirectory -File -ErrorAction SilentlyContinue |
                    Where-Object {
                        $_.Extension -in '.spl', '.shd' -or
                        $_.Name -like $TemporaryFilePattern
                    }
            )

            foreach ($File in $Files) {
                if ($PSCmdlet.ShouldProcess($File.FullName, 'Remove spool file')) {
                    Remove-Item -LiteralPath $File.FullName -Force -ErrorAction Stop
                    $DeletedCount++
                }
            }
        }
        finally {
            if ($ServiceWasStopped -and $PSCmdlet.ShouldProcess($ServiceName, 'Restart Print Spooler')) {
                Start-Service -Name $ServiceName -ErrorAction Stop
                $Service.Refresh()
                $Service.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Running, [TimeSpan]::FromSeconds($TimeoutSeconds))
            }
        }
    }
    finally {
        if ($TranscriptStarted) {
            Stop-Transcript | Out-Null
        }
    }

    if ($WhatIfPreference) {
        $Status = 'WhatIf'
    }

    [pscustomobject]@{
        ServiceName  = $ServiceName
        Service      = $ServiceName
        QueuePath    = $SpoolDirectory
        LogPath      = $LogPath
        FileCount    = $Files.Count
        DeletedCount = $DeletedCount
        DeletedFiles = $DeletedCount
        ServiceWasUp = $ServiceWasRunning
        Status       = $Status
        Success      = $true
        WhatIfRun    = [bool]$WhatIfPreference
    }
}

try {
    Invoke-LoggedPrintQueueCleanup `
        -RequireAdmin $RequireAdmin `
        -IsAdministrator $IsAdministrator `
        -ServiceName $ServiceName `
        -SpoolDirectory $SpoolDirectory `
        -TimeoutSeconds $TimeoutSeconds `
        -LogDirectory $LogDirectory `
        -LogFilePrefix $LogFilePrefix `
        -AllowedExtensions $AllowedExtensions `
        -TemporaryFilePattern $TemporaryFilePattern
}
catch {
    Write-Error -ErrorRecord $_
    exit 1
}
