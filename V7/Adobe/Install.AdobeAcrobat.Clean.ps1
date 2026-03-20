#Requires -Version 7.0

[CmdletBinding(SupportsShouldProcess = $true)]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$RequireAdmin = $true
$IsAdministrator = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$PackagePath = 'C:\Install\Adobe\AcrobatInstaller.msi'
$PackageArguments = ''
$LogDirectory = 'C:\Temp\AdobeAcrobat'
$MsiExecPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\msiexec.exe'
$ProductNamePatterns = @(
    'Adobe Acrobat*',
    'Adobe Acrobat Reader*',
    'Adobe Reader*',
    'Acrobat DC*',
    'Acrobat Reader DC*'
)
$RegistryPaths = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
$ProcessNames = @(
    'Acrobat',
    'AcroRd32',
    'AcroCEF',
    'RdrCEF',
    'AdobeARM'
)
$SuccessExitCodes = @(0, 1641, 3010)

function Invoke-AdobeAcrobatRefresh {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [bool]$RequireAdmin,

        [Parameter(Mandatory = $true)]
        [bool]$IsAdministrator,

        [Parameter(Mandatory = $true)]
        [string]$PackagePath,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$PackageArguments,

        [Parameter(Mandatory = $true)]
        [string]$LogDirectory,

        [Parameter(Mandatory = $true)]
        [string]$MsiExecPath,

        [Parameter(Mandatory = $true)]
        [string[]]$ProductNamePatterns,

        [Parameter(Mandatory = $true)]
        [string[]]$RegistryPaths,

        [Parameter(Mandatory = $true)]
        [string[]]$ProcessNames,

        [Parameter(Mandatory = $true)]
        [int[]]$SuccessExitCodes
    )

    if ($RequireAdmin -and -not $WhatIfPreference -and -not $IsAdministrator) {
        throw 'Run this script in an elevated PowerShell 5.1 session.'
    }

    if (-not (Test-Path -LiteralPath $PackagePath -PathType Leaf)) {
        if ($WhatIfPreference) {
            return [pscustomobject]@{
                PackagePath         = $PackagePath
                RemovedProductCount = 0
                RemovedProducts     = ''
                RestartRequired     = $false
                LogDirectory        = $LogDirectory
                Status              = 'Skipped'
                Reason              = 'PackagePathNotFound'
            }
        }

        throw ('Package not found: {0}' -f $PackagePath)
    }

    if (-not (Test-Path -LiteralPath $LogDirectory -PathType Container)) {
        if ($PSCmdlet.ShouldProcess($LogDirectory, 'Create directory')) {
            New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
        }
    }

    $TimeStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $MatchingProducts = @()
    $RemovedProducts = @()
    $RestartRequired = $false
    $Status = 'Completed'

    foreach ($RegistryPath in $RegistryPaths) {
        $MatchingProducts += Get-ItemProperty -Path $RegistryPath -ErrorAction SilentlyContinue | Where-Object {
            $DisplayName = [string]$_.DisplayName

            if ([string]::IsNullOrWhiteSpace($DisplayName)) {
                return $false
            }

            foreach ($Pattern in $ProductNamePatterns) {
                if ($DisplayName -like $Pattern) {
                    return $true
                }
            }

            return $false
        }
    }

    $MatchingProducts = @($MatchingProducts | Sort-Object -Property PSPath -Unique)

    foreach ($RunningProcess in @(Get-Process -Name $ProcessNames -ErrorAction SilentlyContinue)) {
        if ($PSCmdlet.ShouldProcess($RunningProcess.ProcessName, 'Stop process')) {
            Stop-Process -Id $RunningProcess.Id -Force -ErrorAction SilentlyContinue
        }
    }

    foreach ($Product in $MatchingProducts) {
        $RawCommand = [string]$Product.QuietUninstallString

        if ([string]::IsNullOrWhiteSpace($RawCommand)) {
            $RawCommand = [string]$Product.UninstallString
        }

        if ([string]::IsNullOrWhiteSpace($RawCommand) -and $Product.PSChildName -match '^\{[A-F0-9-]+\}$') {
            $RawCommand = '"{0}" /x {1}' -f $MsiExecPath, $Product.PSChildName
        }

        if ([string]::IsNullOrWhiteSpace($RawCommand)) {
            if ($WhatIfPreference) {
                continue
            }

            throw ('No uninstall command found for {0}.' -f $Product.DisplayName)
        }

        $CommandMatch = [regex]::Match($RawCommand, '^(?<File>"[^"]+"|\S+)(?<Args>.*)$')
        if (-not $CommandMatch.Success) {
            if ($WhatIfPreference) {
                continue
            }

            throw ('Unable to parse uninstall command for {0}.' -f $Product.DisplayName)
        }

        $UninstallFilePath = $CommandMatch.Groups['File'].Value.Trim('"')
        $UninstallArguments = $CommandMatch.Groups['Args'].Value.Trim()
        $UninstallLogPath = Join-Path -Path $LogDirectory -ChildPath ('Uninstall-{0}-{1}.log' -f $TimeStamp, ($Product.PSChildName -replace '[^A-Za-z0-9-]', '_'))

        if ($UninstallFilePath -match '(?i)msiexec(\.exe)?$') {
            $UninstallFilePath = $MsiExecPath
            $UninstallArguments = $UninstallArguments -replace '(^|\s)/I(\s|$)', '$1/X$2'
            $UninstallArguments = $UninstallArguments -replace '(^|\s)/i(\s|$)', '$1/x$2'

            if ($UninstallArguments -notmatch '(^|\s)/x(\s|$)' -and $UninstallArguments -notmatch '(^|\s)/X(\s|$)' -and $Product.PSChildName -match '^\{[A-F0-9-]+\}$') {
                $UninstallArguments = ('/x {0} {1}' -f $Product.PSChildName, $UninstallArguments).Trim()
            }

            if ($UninstallArguments -notmatch '(^|\s)/qn(\s|$)') {
                $UninstallArguments = ('{0} /qn' -f $UninstallArguments).Trim()
            }

            if ($UninstallArguments -notmatch '(^|\s)/norestart(\s|$)') {
                $UninstallArguments = ('{0} /norestart' -f $UninstallArguments).Trim()
            }

            if ($UninstallArguments -notmatch '(^|\s)/L') {
                $UninstallArguments = ('{0} /L*v "{1}"' -f $UninstallArguments, $UninstallLogPath).Trim()
            }
        }

        if ($PSCmdlet.ShouldProcess($Product.DisplayName, 'Uninstall product')) {
            $ProcessResult = Start-Process -FilePath $UninstallFilePath -ArgumentList $UninstallArguments -Wait -PassThru

            if ($SuccessExitCodes -notcontains $ProcessResult.ExitCode) {
                throw ('Uninstall failed for {0}. Exit code: {1}' -f $Product.DisplayName, $ProcessResult.ExitCode)
            }

            if ($ProcessResult.ExitCode -in 1641, 3010) {
                $RestartRequired = $true
            }

            $RemovedProducts += [string]$Product.DisplayName
        }
    }

    $InstallFilePath = $PackagePath
    $InstallArguments = $PackageArguments
    $InstallLogPath = Join-Path -Path $LogDirectory -ChildPath ('Install-{0}.log' -f $TimeStamp)

    if ([System.IO.Path]::GetExtension($PackagePath) -ieq '.msi') {
        $InstallFilePath = $MsiExecPath
        $InstallArguments = '/i "{0}" /qn /norestart /L*v "{1}"' -f $PackagePath, $InstallLogPath
    }
    elseif ([string]::IsNullOrWhiteSpace($InstallArguments)) {
        if ($WhatIfPreference) {
            return [pscustomobject]@{
                PackagePath         = $PackagePath
                RemovedProductCount = $RemovedProducts.Count
                RemovedProducts     = $RemovedProducts -join '; '
                RestartRequired     = $RestartRequired
                LogDirectory        = $LogDirectory
                Status              = 'Skipped'
                Reason              = 'PackageArgumentsRequired'
            }
        }

        throw 'PackageArguments must be configured for non-MSI packages.'
    }

    if ($PSCmdlet.ShouldProcess($PackagePath, 'Install package')) {
        $ProcessResult = Start-Process -FilePath $InstallFilePath -ArgumentList $InstallArguments -Wait -PassThru

        if ($SuccessExitCodes -notcontains $ProcessResult.ExitCode) {
            throw ('Install failed. Exit code: {0}' -f $ProcessResult.ExitCode)
        }

        if ($ProcessResult.ExitCode -in 1641, 3010) {
            $RestartRequired = $true
        }
    }

    if ($WhatIfPreference) {
        $Status = 'WhatIf'
    }

    [pscustomobject]@{
        PackagePath         = $PackagePath
        RemovedProductCount = $RemovedProducts.Count
        RemovedProducts     = $RemovedProducts -join '; '
        RestartRequired     = $RestartRequired
        LogDirectory        = $LogDirectory
        Status              = $Status
        Reason              = ''
    }
}

try {
    Invoke-AdobeAcrobatRefresh `
        -RequireAdmin $RequireAdmin `
        -IsAdministrator $IsAdministrator `
        -PackagePath $PackagePath `
        -PackageArguments $PackageArguments `
        -LogDirectory $LogDirectory `
        -MsiExecPath $MsiExecPath `
        -ProductNamePatterns $ProductNamePatterns `
        -RegistryPaths $RegistryPaths `
        -ProcessNames $ProcessNames `
        -SuccessExitCodes $SuccessExitCodes
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}

