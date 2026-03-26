#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess = $true)]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$RequireAdmin = $true
$IsAdministrator = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$NetshPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\netsh.exe'
$IpConfigPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\ipconfig.exe'
$ShutdownPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\shutdown.exe'
$Commands = @(
    @{ FilePath = $NetshPath; Arguments = @('int', 'ip', 'reset') },
    @{ FilePath = $NetshPath; Arguments = @('winsock', 'reset') },
    @{ FilePath = $IpConfigPath; Arguments = @('/release') },
    @{ FilePath = $IpConfigPath; Arguments = @('/flushdns') },
    @{ FilePath = $IpConfigPath; Arguments = @('/renew') }
)
$RebootDelaySeconds = 5

function Test-IsWindowsSandboxSession {
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    if ([Environment]::UserName -eq 'WDAGUtilityAccount') {
        return $true
    }

    try {
        $CurrentIdentity = [Security.Principal.WindowsIdentity]::GetCurrent()
        if ($null -ne $CurrentIdentity -and $CurrentIdentity.Name -match '(^|\\)WDAGUtilityAccount$') {
            return $true
        }
    }
    catch {
        return $false
    }

    return $false
}

$IsWindowsSandbox = Test-IsWindowsSandboxSession

function Invoke-NetworkReset {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [bool]$RequireAdmin,

        [Parameter(Mandatory = $true)]
        [bool]$IsAdministrator,

        [Parameter(Mandatory = $true)]
        [bool]$IsWindowsSandbox,

        [Parameter(Mandatory = $true)]
        [object[]]$Commands,

        [Parameter(Mandatory = $true)]
        [string]$ShutdownPath,

        [Parameter(Mandatory = $true)]
        [int]$RebootDelaySeconds
    )

    if ($RequireAdmin -and -not $WhatIfPreference -and -not $IsAdministrator) {
        throw 'Run this script in an elevated PowerShell 5.1 session.'
    }

    if ($IsWindowsSandbox -and -not $WhatIfPreference) {
        return [pscustomobject]@{
            CommandCount       = $Commands.Count
            ExecutedCount      = 0
            RebootDelaySeconds = $RebootDelaySeconds
            Status             = 'Skipped'
            Reason             = 'NetworkResetUnsupportedInWindowsSandbox'
        }
    }

    $ExecutedCount = 0
    $Status = 'Completed'

    foreach ($Command in $Commands) {
        $CommandLine = '{0} {1}' -f $Command.FilePath, ($Command.Arguments -join ' ')

        if ($PSCmdlet.ShouldProcess($CommandLine, 'Run command')) {
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
        CommandCount        = $Commands.Count
        ExecutedCount       = $ExecutedCount
        RebootDelaySeconds  = $RebootDelaySeconds
        Status              = $Status
        Reason              = ''
    }
}

try {
    Invoke-NetworkReset `
        -RequireAdmin $RequireAdmin `
        -IsAdministrator $IsAdministrator `
        -IsWindowsSandbox $IsWindowsSandbox `
        -Commands $Commands `
        -ShutdownPath $ShutdownPath `
        -RebootDelaySeconds $RebootDelaySeconds
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
