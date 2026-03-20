#Requires -Version 7.0
#Requires -RunAsAdministrator

[CmdletBinding(SupportsShouldProcess)]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$ScriptConfig = @{
    Commands = @(
        @{
            FilePath  = 'netsh.exe'
            Arguments = @('int', 'ip', 'reset')
        },
        @{
            FilePath  = 'netsh.exe'
            Arguments = @('winsock', 'reset')
        },
        @{
            FilePath  = 'ipconfig.exe'
            Arguments = @('/release')
        },
        @{
            FilePath  = 'ipconfig.exe'
            Arguments = @('/flushdns')
        },
        @{
            FilePath  = 'ipconfig.exe'
            Arguments = @('/renew')
        }
    )
    RebootDelaySeconds = 5
}

function Invoke-ResetNetworkAndReboot {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [object[]]$Commands,

        [Parameter(Mandatory)]
        [int]$RebootDelaySeconds
    )

    foreach ($command in $Commands) {
        $commandLine = '{0} {1}' -f $command.FilePath, ($command.Arguments -join ' ')

        if ($PSCmdlet.ShouldProcess($commandLine, 'Run network reset command')) {
            & $command.FilePath @($command.Arguments) | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw ("Command failed: {0}" -f $commandLine)
            }
        }
    }

    if ($PSCmdlet.ShouldProcess('Local computer', ("Reboot in {0} seconds" -f $RebootDelaySeconds))) {
        & shutdown.exe /r /t $RebootDelaySeconds /f | Out-Null
        Write-Output ("Reboot scheduled in {0} seconds." -f $RebootDelaySeconds)
    }
}

try {
    Invoke-ResetNetworkAndReboot `
        -Commands $ScriptConfig.Commands `
        -RebootDelaySeconds $ScriptConfig.RebootDelaySeconds
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
