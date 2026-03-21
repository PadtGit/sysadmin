#Requires -Version 7.0

[CmdletBinding()]
param(
    [string[]]$Paths = @(
        'PowerShell Script/V5',
        'PowerShell Script/V7',
        'Invoke-V5-WhatIfValidation.ps1',
        'PowerShell Script/Invoke-V5-WhatIfValidation.ps1'
    ),

    [string]$SettingsPath = '',

    [string]$ResultPath = ''
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$RepoRoot = Split-Path -Path $PSScriptRoot -Parent

if ([string]::IsNullOrWhiteSpace($SettingsPath)) {
    $SettingsPath = Join-Path -Path $PSScriptRoot -ChildPath 'PSScriptAnalyzerSettings.psd1'
}

if ([string]::IsNullOrWhiteSpace($ResultPath)) {
    $ResultPath = Join-Path -Path $RepoRoot -ChildPath 'artifacts\validation\psscriptanalyzer.txt'
}

$ResultDirectory = Split-Path -Path $ResultPath -Parent
if (-not [string]::IsNullOrWhiteSpace($ResultDirectory) -and -not (Test-Path -LiteralPath $ResultDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $ResultDirectory -Force | Out-Null
}

if (-not (Get-Module -ListAvailable -Name PSScriptAnalyzer)) {
    Write-Warning 'PSScriptAnalyzer is not installed. Skipping analyzer run.'
    Set-Content -LiteralPath $ResultPath -Value 'PSScriptAnalyzer is not installed. Analyzer run skipped.' -Encoding UTF8
    return
}

$ResolvedPaths = foreach ($Path in $Paths) {
    if ([string]::IsNullOrWhiteSpace($Path)) {
        continue
    }

    if ([System.IO.Path]::IsPathRooted($Path)) {
        $ResolvedPath = $Path
    }
    else {
        $ResolvedPath = Join-Path -Path $RepoRoot -ChildPath $Path
    }

    if (Test-Path -LiteralPath $ResolvedPath) {
        $ResolvedPath
    }
}

$Results = @()
foreach ($ResolvedPath in $ResolvedPaths) {
    $Results += Invoke-ScriptAnalyzer -Path $ResolvedPath -Settings $SettingsPath
}

if ($Results.Count -eq 0) {
    Set-Content -LiteralPath $ResultPath -Value 'No analyzer findings.' -Encoding UTF8
    return
}

$Results |
    Sort-Object -Property Severity, RuleName, ScriptName, Line |
    Format-Table -AutoSize Severity, RuleName, ScriptName, Line, Message |
    Out-String |
    Set-Content -LiteralPath $ResultPath -Encoding UTF8

$Results

if (($Results | Where-Object Severity -eq 'Error').Count -gt 0) {
    exit 1
}
