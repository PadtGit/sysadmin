#Requires -Version 7.0
#Requires -RunAsAdministrator

[CmdletBinding(SupportsShouldProcess)]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$ScriptConfig = @{
    PackagePath         = 'C:\Install\Adobe\AcrobatInstaller.msi'
    PackageArguments    = ''
    LogDirectory        = 'C:\Temp\AdobeAcrobat'
    ProductNamePatterns = @(
        'Adobe Acrobat*',
        'Adobe Acrobat Reader*',
        'Adobe Reader*',
        'Acrobat DC*',
        'Acrobat Reader DC*'
    )
    RegistryPaths       = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    ProcessNames        = @(
        'Acrobat',
        'AcroRd32',
        'AcroCEF',
        'RdrCEF',
        'AdobeARM'
    )
    SuccessExitCodes    = @(0, 1641, 3010)
}

function Invoke-RefreshAdobeAcrobat {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$PackagePath,

        [Parameter(Mandatory)]
        [string]$PackageArguments,

        [Parameter(Mandatory)]
        [string]$LogDirectory,

        [Parameter(Mandatory)]
        [string[]]$ProductNamePatterns,

        [Parameter(Mandatory)]
        [string[]]$RegistryPaths,

        [Parameter(Mandatory)]
        [string[]]$ProcessNames,

        [Parameter(Mandatory)]
        [int[]]$SuccessExitCodes
    )

    if (-not (Test-Path -LiteralPath $PackagePath)) {
        throw 'Update $ScriptConfig.PackagePath before running the script.'
    }

    if (-not (Test-Path -LiteralPath $LogDirectory)) {
        New-Item -ItemType Directory -Path $LogDirectory -Force | Out-Null
    }

    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $matchingProducts = @()
    $restartRequired = $false

    foreach ($registryPath in $RegistryPaths) {
        $matchingProducts += Get-ItemProperty -Path $registryPath -ErrorAction SilentlyContinue | Where-Object {
            $displayName = [string]$_.DisplayName
            -not [string]::IsNullOrWhiteSpace($displayName) -and ($ProductNamePatterns | Where-Object { $displayName -like $_ }).Count -gt 0
        }
    }

    $matchingProducts = @(
        $matchingProducts |
            Sort-Object -Property PSPath -Unique
    )

    $runningProcesses = @(Get-Process -Name $ProcessNames -ErrorAction SilentlyContinue)
    foreach ($process in $runningProcesses) {
        if ($PSCmdlet.ShouldProcess($process.ProcessName, 'Stop Adobe process')) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        }
    }

    $removedProducts = @()
    foreach ($product in $matchingProducts) {
        $rawCommand = [string]$product.QuietUninstallString
        if ([string]::IsNullOrWhiteSpace($rawCommand)) {
            $rawCommand = [string]$product.UninstallString
        }

        if ([string]::IsNullOrWhiteSpace($rawCommand) -and $product.PSChildName -match '^\{[A-F0-9-]+\}$') {
            $rawCommand = "msiexec.exe /x $($product.PSChildName)"
        }

        if ([string]::IsNullOrWhiteSpace($rawCommand)) {
            throw ("No uninstall command found for {0}." -f $product.DisplayName)
        }

        $commandMatch = [regex]::Match($rawCommand, '^(?<File>"[^"]+"|\S+)(?<Args>.*)$')
        if (-not $commandMatch.Success) {
            throw ("Unable to parse uninstall command for {0}." -f $product.DisplayName)
        }

        $uninstallFilePath = $commandMatch.Groups['File'].Value.Trim('"')
        $uninstallArguments = $commandMatch.Groups['Args'].Value.Trim()
        $uninstallLogPath = Join-Path -Path $LogDirectory -ChildPath ("Uninstall-{0}-{1}.log" -f $timestamp, ($product.PSChildName -replace '[^A-Za-z0-9-]', '_'))

        if ($uninstallFilePath -match '(?i)msiexec(\.exe)?$') {
            $uninstallArguments = $uninstallArguments -replace '(^|\s)/I(\s|$)', '$1/X$2'
            $uninstallArguments = $uninstallArguments -replace '(^|\s)/i(\s|$)', '$1/x$2'

            if ($uninstallArguments -notmatch '(^|\s)/x(\s|$)' -and $uninstallArguments -notmatch '(^|\s)/X(\s|$)' -and $product.PSChildName -match '^\{[A-F0-9-]+\}$') {
                $uninstallArguments = "/x $($product.PSChildName) $uninstallArguments".Trim()
            }

            if ($uninstallArguments -notmatch '(^|\s)/qn(\s|$)') {
                $uninstallArguments = "$uninstallArguments /qn"
            }

            if ($uninstallArguments -notmatch '(^|\s)/norestart(\s|$)') {
                $uninstallArguments = "$uninstallArguments /norestart"
            }

            if ($uninstallArguments -notmatch '(^|\s)/L') {
                $uninstallArguments = "$uninstallArguments /L*v `"$uninstallLogPath`""
            }
        }

        if ($PSCmdlet.ShouldProcess($product.DisplayName, 'Uninstall previous Adobe product')) {
            $uninstallProcess = Start-Process -FilePath $uninstallFilePath -ArgumentList $uninstallArguments -Wait -PassThru -NoNewWindow
            if ($uninstallProcess.ExitCode -notin $SuccessExitCodes) {
                throw ("Uninstall failed for {0}. Exit code: {1}" -f $product.DisplayName, $uninstallProcess.ExitCode)
            }

            if ($uninstallProcess.ExitCode -in 1641, 3010) {
                $restartRequired = $true
            }

            $removedProducts += $product.DisplayName
        }
    }

    $installFilePath = $PackagePath
    $installArguments = $PackageArguments
    $installLogPath = Join-Path -Path $LogDirectory -ChildPath ("Install-{0}.log" -f $timestamp)

    if ([System.IO.Path]::GetExtension($PackagePath) -ieq '.msi') {
        $installFilePath = 'msiexec.exe'
        $installArguments = "/i `"$PackagePath`" /qn /norestart /L*v `"$installLogPath`""
    }
    elseif ([string]::IsNullOrWhiteSpace($installArguments)) {
        throw 'Set $ScriptConfig.PackageArguments for non-MSI packages.'
    }

    if ($PSCmdlet.ShouldProcess($PackagePath, 'Install latest Adobe Acrobat package')) {
        $installProcess = Start-Process -FilePath $installFilePath -ArgumentList $installArguments -Wait -PassThru -NoNewWindow
        if ($installProcess.ExitCode -notin $SuccessExitCodes) {
            throw ("Install failed. Exit code: {0}" -f $installProcess.ExitCode)
        }

        if ($installProcess.ExitCode -in 1641, 3010) {
            $restartRequired = $true
        }
    }

    [pscustomobject]@{
        RemovedProductCount = $removedProducts.Count
        RemovedProducts     = $removedProducts -join '; '
        InstalledPackage    = $PackagePath
        RestartRequired     = $restartRequired
        LogDirectory        = $LogDirectory
    }
}

try {
    Invoke-RefreshAdobeAcrobat `
        -PackagePath $ScriptConfig.PackagePath `
        -PackageArguments $ScriptConfig.PackageArguments `
        -LogDirectory $ScriptConfig.LogDirectory `
        -ProductNamePatterns $ScriptConfig.ProductNamePatterns `
        -RegistryPaths $ScriptConfig.RegistryPaths `
        -ProcessNames $ScriptConfig.ProcessNames `
        -SuccessExitCodes $ScriptConfig.SuccessExitCodes
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
