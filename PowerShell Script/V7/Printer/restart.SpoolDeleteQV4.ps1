#Requires -Version 7.0
#Requires -RunAsAdministrator

[CmdletBinding(SupportsShouldProcess)]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$CommonApplicationDataPath = [Environment]::GetFolderPath('CommonApplicationData')

$ScriptConfig = @{
    StorageRoot    = Join-Path -Path $CommonApplicationDataPath -ChildPath 'sysadmin-main'
    ServiceName    = 'Spooler'
    SpoolDirectory = Join-Path -Path $env:SystemRoot -ChildPath 'System32\spool\PRINTERS'
    TimeoutSeconds = 30
    LogDirectory   = Join-Path -Path $CommonApplicationDataPath -ChildPath 'sysadmin-main\Logs\Printer'
    LogFilePrefix  = 'print-queue'
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

    Set-Acl -LiteralPath $directory.FullName -AclObject $acl
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

function New-UniqueChildPath {
    param(
        [Parameter(Mandatory)]
        [string]$Directory,

        [Parameter(Mandatory)]
        [string]$FileNamePrefix,

        [Parameter(Mandatory)]
        [string]$Extension
    )

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmssfff'
    $candidatePath = Join-Path -Path $Directory -ChildPath ('{0}-{1}{2}' -f $FileNamePrefix, $timestamp, $Extension)
    $counter = 1

    while (Test-Path -LiteralPath $candidatePath -PathType Leaf) {
        $candidatePath = Join-Path -Path $Directory -ChildPath ('{0}-{1}-{2}{3}' -f $FileNamePrefix, $timestamp, $counter, $Extension)
        $counter++
    }

    return $candidatePath
}

function Invoke-ClearPrintQueueLogged {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$ServiceName,

        [Parameter(Mandatory)]
        [string]$SpoolDirectory,

        [Parameter(Mandatory)]
        [int]$TimeoutSeconds,

        [Parameter(Mandatory)]
        [string]$LogDirectory,

        [Parameter(Mandatory)]
        [string]$LogFilePrefix
    )

    $secureLogDirectory = Resolve-SecureDirectory -Path $LogDirectory -AllowedRoots @($ScriptConfig.StorageRoot)
    $logPath = New-UniqueChildPath -Directory $secureLogDirectory -FileNamePrefix $LogFilePrefix -Extension '.log'
    $transcriptStarted = $false

    if (-not $WhatIfPreference -and $PSCmdlet.ShouldProcess($logPath, 'Start transcript')) {
        Start-Transcript -Path $logPath -NoClobber | Out-Null
        $transcriptStarted = $true
    }

    try {
        $service = Get-Service -Name $ServiceName -ErrorAction Stop
        $wasRunning = $service.Status -eq [System.ServiceProcess.ServiceControllerStatus]::Running
        $serviceWasStopped = $false

        if ($wasRunning -and $PSCmdlet.ShouldProcess($ServiceName, 'Stop service')) {
            Stop-Service -Name $ServiceName -Force -ErrorAction Stop
            (Get-Service -Name $ServiceName -ErrorAction Stop).WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Stopped, [TimeSpan]::FromSeconds($TimeoutSeconds))
            $serviceWasStopped = $true
        }

        try {
            $deletedCount = 0
            $files = @(
                Get-ChildItem -LiteralPath $SpoolDirectory -File -ErrorAction SilentlyContinue |
                    Where-Object { $_.Extension -in '.spl', '.shd' }
            )

            foreach ($file in $files) {
                if ($PSCmdlet.ShouldProcess($file.FullName, 'Remove spool file')) {
                    Remove-Item -LiteralPath $file.FullName -Force -ErrorAction Stop
                    $deletedCount++
                }
            }

            [pscustomobject]@{
                DeletedFiles = $deletedCount
                LogPath      = $logPath
                ServiceName  = $ServiceName
                ServiceWasUp = $wasRunning
            }
        }
        finally {
            if ($serviceWasStopped -and $PSCmdlet.ShouldProcess($ServiceName, 'Start service')) {
                Start-Service -Name $ServiceName -ErrorAction Stop
                (Get-Service -Name $ServiceName -ErrorAction Stop).WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Running, [TimeSpan]::FromSeconds($TimeoutSeconds))
            }
        }
    }
    finally {
        if ($transcriptStarted) {
            Stop-Transcript | Out-Null
        }
    }
}

try {
    Invoke-ClearPrintQueueLogged `
        -ServiceName $ScriptConfig.ServiceName `
        -SpoolDirectory $ScriptConfig.SpoolDirectory `
        -TimeoutSeconds $ScriptConfig.TimeoutSeconds `
        -LogDirectory $ScriptConfig.LogDirectory `
        -LogFilePrefix $ScriptConfig.LogFilePrefix
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
