#Requires -Version 5.1

[CmdletBinding()]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$BasePath = 'C:\Users\Bob\Documents\sysadmin-main\PowerShell Script\V5'
$PowerShellPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'
$ScriptPaths = @(
    (Join-Path -Path $BasePath -ChildPath 'Adobe\Install.AdobeAcrobat.Clean.ps1'),
    (Join-Path -Path $BasePath -ChildPath 'Printer\Delete.all.offline.printer.ps1'),
    (Join-Path -Path $BasePath -ChildPath 'Printer\Deleter.NamePrinter.ps1'),
    (Join-Path -Path $BasePath -ChildPath 'Printer\Export.printer.list.BASIC.ps1'),
    (Join-Path -Path $BasePath -ChildPath 'Printer\Export.printer.list.FULL.ps1'),
    (Join-Path -Path $BasePath -ChildPath 'Printer\Restart.spool.delete.printerQ.ps1'),
    (Join-Path -Path $BasePath -ChildPath 'Printer\Restart.Spool.DeletePrinterQSimple.ps1'),
    (Join-Path -Path $BasePath -ChildPath 'Printer\restart.SpoolDeleteQV4.ps1'),
    (Join-Path -Path $BasePath -ChildPath 'windows-maintenance\Move-OrphanedInstallerFiles.ps1'),
    (Join-Path -Path $BasePath -ChildPath 'windows-maintenance\Nettoyage.Avance.Windows.Sauf.logserreur.ps1'),
    (Join-Path -Path $BasePath -ChildPath 'windows-maintenance\Nettoyage.Complet.Caches.Windows.ps1'),
    (Join-Path -Path $BasePath -ChildPath 'windows-maintenance\Reset.Network.RebootPC.ps1'),
    (Join-Path -Path $BasePath -ChildPath 'WindowsServer\FichierOphelin.ps1')
)

function Invoke-V5WhatIfValidation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PowerShellPath,

        [Parameter(Mandatory = $true)]
        [string[]]$ScriptPaths
    )

    $Results = @()
    $FailureCount = 0

    foreach ($ScriptPath in $ScriptPaths) {
        $CurrentErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $OutputLines = @(& $PowerShellPath -NoProfile -ExecutionPolicy Bypass -File $ScriptPath -WhatIf 2>&1 | ForEach-Object { $_.ToString() })
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

    $Results

    if ($FailureCount -gt 0) {
        exit 1
    }
}

Invoke-V5WhatIfValidation -PowerShellPath $PowerShellPath -ScriptPaths $ScriptPaths
