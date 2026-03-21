#Requires -Version 5.1

[CmdletBinding()]
param(
    [string]$ResultPath = ''
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$NestedValidatorPath = Join-Path -Path $PSScriptRoot -ChildPath 'PowerShell Script\Invoke-V5-WhatIfValidation.ps1'

if (-not (Test-Path -LiteralPath $NestedValidatorPath -PathType Leaf)) {
    throw ('Nested validator not found: {0}' -f $NestedValidatorPath)
}

& $NestedValidatorPath @PSBoundParameters
exit $LASTEXITCODE
