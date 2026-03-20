#Requires -Version 5.1

[CmdletBinding()]
param(
    [switch]$ElevatedPass,

    [string]$ResultPath = ''
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$BasePath = $PSScriptRoot

if ([string]::IsNullOrWhiteSpace($BasePath)) {
    $BasePath = Join-Path -Path (Get-Location) -ChildPath 'PowerShell Script'
}

if (-not (Test-Path -LiteralPath $BasePath -PathType Container)) {
    throw ('Base folder not found: {0}' -f $BasePath)
}

$V5Path = Join-Path -Path $BasePath -ChildPath 'V5'
$V7Path = Join-Path -Path $BasePath -ChildPath 'V7'
$WindowsPowerShellPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'
$PowerShell7Path = (Get-Command -Name 'pwsh.exe' -ErrorAction Stop).Source
$ScriptPath = [string]$PSCommandPath
$ValidatorFilePath = Join-Path -Path $BasePath -ChildPath 'Invoke-V5-WhatIfValidation.ps1'
$IsAdministrator = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$CurrentScriptContent = if (-not [string]::IsNullOrWhiteSpace($ScriptPath) -and (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
    Get-Content -LiteralPath $ScriptPath -Raw
}
elseif (Test-Path -LiteralPath $ValidatorFilePath -PathType Leaf) {
    Get-Content -LiteralPath $ValidatorFilePath -Raw
}
else {
    $MyInvocation.MyCommand.Definition
}

if ([string]::IsNullOrWhiteSpace($ResultPath)) {
    $ResultPath = Join-Path -Path $BasePath -ChildPath 'AdminValidationResult.txt'
}

function Invoke-ScriptValidation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PhaseName,

        [Parameter(Mandatory = $true)]
        [string]$ShellPath,

        [Parameter(Mandatory = $true)]
        [string]$RootPath,

        [Parameter(Mandatory = $true)]
        [string]$ResultPath,

        [Parameter(Mandatory = $true)]
        [bool]$AppendResults
    )

    if (-not (Test-Path -LiteralPath $RootPath -PathType Container)) {
        throw ('Script folder not found: {0}' -f $RootPath)
    }

    $ScriptFiles = @(Get-ChildItem -LiteralPath $RootPath -Recurse -File -Filter *.ps1 | Sort-Object -Property FullName)
    $ResultLines = @()
    $FailureCount = 0

    if ($AppendResults) {
        $ResultLines += ''
    }

    $ResultLines += ('[{0}]' -f $PhaseName)
    $ResultLines += ('Shell={0}' -f $ShellPath)
    $ResultLines += 'Scripts='

    foreach ($ScriptFile in $ScriptFiles) {
        $RelativePath = $ScriptFile.FullName.Substring($RootPath.Length + 1)
        $ResultLines += $RelativePath
    }

    Write-Verbose ('[{0}] Script list:' -f $PhaseName)

    foreach ($ScriptFile in $ScriptFiles) {
        Write-Verbose ($ScriptFile.FullName.Substring($RootPath.Length + 1))
    }

    foreach ($ScriptFile in $ScriptFiles) {
        $RelativePath = $ScriptFile.FullName.Substring($RootPath.Length + 1)
        $OutputLines = @()
        $CurrentErrorActionPreference = $ErrorActionPreference
        $ScriptContent = Get-Content -LiteralPath $ScriptFile.FullName -Raw
        $EncodedScriptContent = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($ScriptContent))
        $InvocationWrapper = @"
`$ScriptContent = [System.Text.Encoding]::Unicode.GetString([System.Convert]::FromBase64String('$EncodedScriptContent'))
`$ScriptBlock = [ScriptBlock]::Create(`$ScriptContent)
& `$ScriptBlock -WhatIf
"@

        try {
            $ErrorActionPreference = 'Continue'
            $global:LASTEXITCODE = 0
            $OutputLines = @($InvocationWrapper | & $ShellPath -NoProfile -Command - 2>&1 | ForEach-Object { $_.ToString().Trim() })
            $ExitCode = if ($null -ne $LASTEXITCODE) { [int]$LASTEXITCODE } else { 0 }
        }
        finally {
            $ErrorActionPreference = $CurrentErrorActionPreference
        }

        if ($ExitCode -ne 0) {
            $FailureCount++
        }

        $ResultLines += ('{0}|{1}|{2}' -f $RelativePath, $ExitCode, ($ExitCode -eq 0))

        foreach ($OutputLine in $OutputLines) {
            if (-not [string]::IsNullOrWhiteSpace($OutputLine)) {
                $ResultLines += ('  {0}' -f $OutputLine)
            }
        }
    }

    if ($AppendResults) {
        Add-Content -LiteralPath $ResultPath -Value $ResultLines -Encoding Ascii
    }
    else {
        Set-Content -LiteralPath $ResultPath -Value $ResultLines -Encoding Ascii
    }

    [pscustomobject]@{
        PhaseName    = $PhaseName
        ScriptCount  = $ScriptFiles.Count
        FailureCount = $FailureCount
        ResultPath   = $ResultPath
    }
}

try {
    $TotalFailures = 0

    if ($ElevatedPass) {
        $AdminResult = Invoke-ScriptValidation `
            -PhaseName 'V5-Admin' `
            -ShellPath $WindowsPowerShellPath `
            -RootPath $V5Path `
            -ResultPath $ResultPath `
            -AppendResults $true

        $TotalFailures += $AdminResult.FailureCount
    }
    else {
        $V5Result = Invoke-ScriptValidation `
            -PhaseName 'V5-User' `
            -ShellPath $WindowsPowerShellPath `
            -RootPath $V5Path `
            -ResultPath $ResultPath `
            -AppendResults $false

        $V7Result = Invoke-ScriptValidation `
            -PhaseName 'V7-User' `
            -ShellPath $PowerShell7Path `
            -RootPath $V7Path `
            -ResultPath $ResultPath `
            -AppendResults $true

        $TotalFailures += $V5Result.FailureCount + $V7Result.FailureCount

        if ($IsAdministrator) {
            $AdminResult = Invoke-ScriptValidation `
                -PhaseName 'V5-Admin' `
                -ShellPath $WindowsPowerShellPath `
                -RootPath $V5Path `
                -ResultPath $ResultPath `
                -AppendResults $true

            $TotalFailures += $AdminResult.FailureCount
        }
        else {
            $ValidatorContentPath = Join-Path -Path $env:TEMP -ChildPath ('Invoke-V5-WhatIfValidation-{0}.txt' -f [Guid]::NewGuid().ToString('N'))
            $EscapedResultPath = $ResultPath.Replace("'", "''")
            $EscapedValidatorContentPath = $ValidatorContentPath.Replace("'", "''")

            Set-Content -LiteralPath $ValidatorContentPath -Value $CurrentScriptContent -Encoding Ascii

            try {
                $ElevatedInvocation = @"
`$ValidatorContent = Get-Content -LiteralPath '$EscapedValidatorContentPath' -Raw
`$ValidatorBlock = [ScriptBlock]::Create(`$ValidatorContent)
& `$ValidatorBlock -ElevatedPass -ResultPath '$EscapedResultPath'
"@
                $EncodedElevatedInvocation = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($ElevatedInvocation))
                $AdminProcess = Start-Process -FilePath $WindowsPowerShellPath -ArgumentList @('-NoProfile', '-EncodedCommand', $EncodedElevatedInvocation) -Verb RunAs -Wait -PassThru

                if ($AdminProcess.ExitCode -ne 0) {
                    Add-Content -LiteralPath $ResultPath -Value @('', '[V5-Admin]', 'ElevationFailed=True') -Encoding Ascii
                    $TotalFailures++
                }
            }
            finally {
                if (Test-Path -LiteralPath $ValidatorContentPath -PathType Leaf) {
                    Remove-Item -LiteralPath $ValidatorContentPath -Force
                }
            }
        }
    }

    if ($TotalFailures -gt 0) {
        exit 1
    }
}
catch {
    Add-Content -LiteralPath $ResultPath -Value @('', '[ValidationError]', $_.Exception.Message) -Encoding Ascii
    Write-Error $_.Exception.Message
    exit 1
}
