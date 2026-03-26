#Requires -Version 5.1

[CmdletBinding()]
param(
    [string]$ResultPath = ''
)

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$BasePath = Join-Path -Path $PSScriptRoot -ChildPath 'PowerShell Script'
$PowerShellPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'

if ([string]::IsNullOrWhiteSpace($ResultPath)) {
    $ResultPath = Join-Path -Path $PSScriptRoot -ChildPath 'artifacts\validation\whatif-validation.txt'
}

$ResultDirectory = Split-Path -Path $ResultPath -Parent
if (-not [string]::IsNullOrWhiteSpace($ResultDirectory) -and -not (Test-Path -LiteralPath $ResultDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $ResultDirectory -Force | Out-Null
}

$ScriptPaths = @(
    'Adobe\Install.AdobeAcrobat.Clean.ps1',
    'Printer\Delete.all.offline.printer.ps1',
    'Printer\Deleter.NamePrinter.ps1',
    'Printer\Export.printer.list.BASIC.ps1',
    'Printer\Export.printer.list.FULL.ps1',
    'Printer\Restart.spool.delete.printerQ.ps1',
    'Printer\Restart.Spool.DeletePrinterQSimple.ps1',
    'Printer\restart.SpoolDeleteQV4.ps1',
    'windows-maintenance\Move-OrphanedInstallerFiles.ps1',
    'windows-maintenance\Nettoyage.Avance.Windows.Sauf.logserreur.ps1',
    'windows-maintenance\Nettoyage.Complet.Caches.Windows.ps1',
    'windows-maintenance\Reset.Network.RebootPC.ps1',
    'WindowsServer\FichierOphelin.ps1'
) | ForEach-Object {
    Join-Path -Path $BasePath -ChildPath $_
}

function Invoke-WhatIfValidation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PowerShellPath,

        [Parameter(Mandatory = $true)]
        [string[]]$ScriptPaths,

        [Parameter(Mandatory = $true)]
        [string]$ResultPath
    )

    $Results = @()
    $FailureCount = 0

    foreach ($ScriptPath in $ScriptPaths) {
        if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
            $Results += [pscustomobject]@{
                ScriptPath = $ScriptPath
                ExitCode   = 1
                Success    = $false
                Output     = 'Script not found.'
            }
            $FailureCount++
            continue
        }

        $CurrentErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $OutputLines = @(
            & $PowerShellPath -NoProfile -ExecutionPolicy Bypass -File $ScriptPath -WhatIf 2>&1 |
                ForEach-Object { $_.ToString() }
        )
        $ExitCode = $LASTEXITCODE
        $ErrorActionPreference = $CurrentErrorActionPreference

        $Results += [pscustomobject]@{
            ScriptPath = $ScriptPath
            ExitCode   = $ExitCode
            Success    = ($ExitCode -eq 0)
            Output     = ($OutputLines -join [Environment]::NewLine)
        }

        if ($ExitCode -ne 0) {
            $FailureCount++
        }
    }

    $Results |
        Sort-Object -Property ScriptPath |
        Format-List |
        Out-String |
        Set-Content -LiteralPath $ResultPath -Encoding UTF8

    $Results

    if ($FailureCount -gt 0) {
        exit 1
    }
}

Invoke-WhatIfValidation -PowerShellPath $PowerShellPath -ScriptPaths $ScriptPaths -ResultPath $ResultPath
