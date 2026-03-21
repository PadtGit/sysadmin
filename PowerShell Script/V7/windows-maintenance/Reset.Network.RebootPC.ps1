#Requires -Version 7.0

[CmdletBinding(SupportsShouldProcess = $true)]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$RequireAdmin = $true
$IsAdministrator = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$ScriptConfig = @{
    Commands = @(
        @{
            FilePath  = Join-Path -Path $env:SystemRoot -ChildPath 'System32\netsh.exe'
            Arguments = @('int', 'ip', 'reset')
        },
        @{
            FilePath  = Join-Path -Path $env:SystemRoot -ChildPath 'System32\netsh.exe'
            Arguments = @('winsock', 'reset')
        },
        @{
            FilePath  = Join-Path -Path $env:SystemRoot -ChildPath 'System32\ipconfig.exe'
            Arguments = @('/release')
        },
        @{
            FilePath  = Join-Path -Path $env:SystemRoot -ChildPath 'System32\ipconfig.exe'
            Arguments = @('/flushdns')
        },
        @{
            FilePath  = Join-Path -Path $env:SystemRoot -ChildPath 'System32\ipconfig.exe'
            Arguments = @('/renew')
        }
    )
    ShutdownPath       = Join-Path -Path $env:SystemRoot -ChildPath 'System32\shutdown.exe'
    RebootDelaySeconds = 5
}

function Invoke-ResetNetworkAndReboot {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [bool]$RequireAdmin,

        [Parameter(Mandatory = $true)]
        [bool]$IsAdministrator,

        [Parameter(Mandatory = $true)]
        [object[]]$Commands,

        [Parameter(Mandatory = $true)]
        [string]$ShutdownPath,

        [Parameter(Mandatory = $true)]
        [int]$RebootDelaySeconds
    )

    if ($RequireAdmin -and -not $WhatIfPreference -and -not $IsAdministrator) {
        throw 'Run this script in an elevated PowerShell 7 session.'
    }

    $ExecutedCount = 0
    $Status = 'Completed'

    foreach ($Command in $Commands) {
        $CommandLine = '{0} {1}' -f $Command.FilePath, ($Command.Arguments -join ' ')

        if ($PSCmdlet.ShouldProcess($CommandLine, 'Run network reset command')) {
            & $Command.FilePath @($Command.Arguments) | Out-Null

            if ($LASTEXITCODE -ne 0) {
                throw ('Command failed: {0}' -f $CommandLine)
            }

            $ExecutedCount++
        }
    }

    if ($PSCmdlet.ShouldProcess('Local computer', ('Restart in {0} seconds' -f $RebootDelaySeconds))) {
        & $ShutdownPath /r /t $RebootDelaySeconds /f | Out-Null
    }

    if ($WhatIfPreference) {
        $Status = 'WhatIf'
    }

    [pscustomobject]@{
        CommandCount       = $Commands.Count
        ExecutedCount      = $ExecutedCount
        RebootDelaySeconds = $RebootDelaySeconds
        Status             = $Status
        Reason             = ''
    }
}

try {
    Invoke-ResetNetworkAndReboot `
        -RequireAdmin $RequireAdmin `
        -IsAdministrator $IsAdministrator `
        -Commands $ScriptConfig.Commands `
        -ShutdownPath $ScriptConfig.ShutdownPath `
        -RebootDelaySeconds $ScriptConfig.RebootDelaySeconds
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
