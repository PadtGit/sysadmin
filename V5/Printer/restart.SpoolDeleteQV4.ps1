#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess = $true)]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$RequireAdmin = $true
$IsAdministrator = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ServiceName = 'Spooler'
$SpoolDirectory = Join-Path -Path $env:SystemRoot -ChildPath 'System32\spool\PRINTERS'
$TimeoutSeconds = 30
$LogPath = 'C:\Temp\print-queue.log'
$AllowedExtensions = @('.spl', '.shd')

function Invoke-LoggedPrintQueueCleanup {
    [CmdletBinding(SupportsShouldProcess = $true)]
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
        [string]$LogPath,

        [Parameter(Mandatory = $true)]
        [string[]]$AllowedExtensions
    )

    if ($RequireAdmin -and -not $WhatIfPreference -and -not $IsAdministrator) {
        throw 'Run this script in an elevated PowerShell 5.1 session.'
    }

    $LogDirectory = Split-Path -Path $LogPath -Parent
    $TranscriptStarted = $false
    $DeletedCount = 0
    $Status = 'Completed'
    $Service = Get-Service -Name $ServiceName -ErrorAction Stop
    $ServiceWasRunning = $Service.Status -eq [System.ServiceProcess.ServiceControllerStatus]::Running

    if (-not $WhatIfPreference -and $LogDirectory -and -not (Test-Path -LiteralPath $LogDirectory -PathType Container)) {
        if ($PSCmdlet.ShouldProcess($LogDirectory, 'Create directory')) {
            New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
        }
    }

    if (-not $WhatIfPreference -and $PSCmdlet.ShouldProcess($LogPath, 'Start transcript')) {
        Start-Transcript -Path $LogPath -Append | Out-Null
        $TranscriptStarted = $true
    }

    try {
        if ($ServiceWasRunning -and $PSCmdlet.ShouldProcess($ServiceName, 'Stop service')) {
            Stop-Service -Name $ServiceName -Force -ErrorAction Stop
            (Get-Service -Name $ServiceName -ErrorAction Stop).WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Stopped, [TimeSpan]::FromSeconds($TimeoutSeconds))
        }

        try {
            $Files = @(Get-ChildItem -LiteralPath $SpoolDirectory -File -ErrorAction SilentlyContinue | Where-Object { $AllowedExtensions -contains $_.Extension.ToLowerInvariant() })

            foreach ($File in $Files) {
                if ($PSCmdlet.ShouldProcess($File.FullName, 'Remove spool file')) {
                    Remove-Item -LiteralPath $File.FullName -Force -ErrorAction Stop
                    $DeletedCount++
                }
            }
        }
        finally {
            if ($ServiceWasRunning -and $PSCmdlet.ShouldProcess($ServiceName, 'Start service')) {
                Start-Service -Name $ServiceName -ErrorAction Stop
                (Get-Service -Name $ServiceName -ErrorAction Stop).WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Running, [TimeSpan]::FromSeconds($TimeoutSeconds))
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
        QueuePath    = $SpoolDirectory
        LogPath      = $LogPath
        FileCount    = $Files.Count
        DeletedCount = $DeletedCount
        ServiceWasUp = $ServiceWasRunning
        Status       = $Status
        Reason       = ''
    }
}

try {
    Invoke-LoggedPrintQueueCleanup `
        -RequireAdmin $RequireAdmin `
        -IsAdministrator $IsAdministrator `
        -ServiceName $ServiceName `
        -SpoolDirectory $SpoolDirectory `
        -TimeoutSeconds $TimeoutSeconds `
        -LogPath $LogPath `
        -AllowedExtensions $AllowedExtensions
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
