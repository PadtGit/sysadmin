#Requires -Version 7.0
#Requires -RunAsAdministrator

[CmdletBinding(SupportsShouldProcess)]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$ScriptConfig = @{
    ServiceName    = 'Spooler'
    SpoolDirectory = Join-Path -Path $env:SystemRoot -ChildPath 'System32\spool\PRINTERS'
    TimeoutSeconds = 30
    LogPath        = 'C:\Temp\print-queue.log'
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
        [string]$LogPath
    )

    $logDirectory = Split-Path -Path $LogPath -Parent
    if ($logDirectory -and -not (Test-Path -LiteralPath $logDirectory)) {
        New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
    }

    Start-Transcript -Path $LogPath -Append | Out-Null

    try {
        $service = Get-Service -Name $ServiceName -ErrorAction Stop
        $wasRunning = $service.Status -eq [System.ServiceProcess.ServiceControllerStatus]::Running

        if ($wasRunning) {
            Stop-Service -Name $ServiceName -Force -ErrorAction Stop
            $service.WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Stopped, [TimeSpan]::FromSeconds($TimeoutSeconds))
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
                LogPath      = $LogPath
                ServiceName  = $ServiceName
                ServiceWasUp = $wasRunning
            }
        }
        finally {
            if ($wasRunning) {
                Start-Service -Name $ServiceName -ErrorAction Stop
                (Get-Service -Name $ServiceName -ErrorAction Stop).WaitForStatus([System.ServiceProcess.ServiceControllerStatus]::Running, [TimeSpan]::FromSeconds($TimeoutSeconds))
            }
        }
    }
    finally {
        Stop-Transcript | Out-Null
    }
}

try {
    Invoke-ClearPrintQueueLogged `
        -ServiceName $ScriptConfig.ServiceName `
        -SpoolDirectory $ScriptConfig.SpoolDirectory `
        -TimeoutSeconds $ScriptConfig.TimeoutSeconds `
        -LogPath $ScriptConfig.LogPath
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
