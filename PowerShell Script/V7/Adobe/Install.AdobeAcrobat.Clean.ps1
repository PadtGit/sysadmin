#Requires -Version 7.0
#Requires -RunAsAdministrator

[CmdletBinding(SupportsShouldProcess)]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$CommonApplicationDataPath = [Environment]::GetFolderPath('CommonApplicationData')

$ScriptConfig = @{
    PackagePath              = 'C:\Install\Adobe\AcrobatInstaller.msi'
    PackageArguments         = ''
    StorageRoot              = Join-Path -Path $CommonApplicationDataPath -ChildPath 'sysadmin-main'
    LogDirectory             = Join-Path -Path $CommonApplicationDataPath -ChildPath 'sysadmin-main\Logs\AdobeAcrobat'
    TrustedPublisherPatterns = @(
        'Adobe*'
    )
    MsiexecPath              = Join-Path -Path $env:SystemRoot -ChildPath 'System32\msiexec.exe'
    ProductNamePatterns      = @(
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

function Test-PathWithinAllowedRoot {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string[]]$AllowedRoots
    )

    $normalizedPath = [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
    foreach ($allowedRoot in $AllowedRoots) {
        if ([string]::IsNullOrWhiteSpace($allowedRoot)) {
            continue
        }

        $normalizedRoot = [System.IO.Path]::GetFullPath($allowedRoot).TrimEnd('\')
        if ($normalizedPath.Equals($normalizedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }

        if ($normalizedPath.StartsWith(($normalizedRoot + '\'), [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    return $false
}

function Test-IsReparsePoint {
    param(
        [Parameter(Mandatory)]
        [System.IO.FileSystemInfo]$Item
    )

    return (($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Set-RestrictedDirectoryAcl {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $directory = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if (-not $directory.PSIsContainer) {
        throw ('Secure directory path must be a directory: {0}' -f $Path)
    }

    if (Test-IsReparsePoint -Item $directory) {
        throw ('Secure directory path must not be a reparse point: {0}' -f $Path)
    }

    $currentUserSid = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $administratorsSid = [Security.Principal.SecurityIdentifier]::new([Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid, $null)
    $systemSid = [Security.Principal.SecurityIdentifier]::new([Security.Principal.WellKnownSidType]::LocalSystemSid, $null)
    $inheritanceFlags = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
    $propagationFlags = [System.Security.AccessControl.PropagationFlags]::None
    $rights = [System.Security.AccessControl.FileSystemRights]::FullControl
    $accessType = [System.Security.AccessControl.AccessControlType]::Allow
    $acl = [System.Security.AccessControl.DirectorySecurity]::new()
    $acl.SetAccessRuleProtection($true, $false)

    foreach ($sidGroup in @($currentUserSid, $administratorsSid, $systemSid) | Group-Object Value) {
        $rule = [System.Security.AccessControl.FileSystemAccessRule]::new(
            $sidGroup.Group[0],
            $rights,
            $inheritanceFlags,
            $propagationFlags,
            $accessType
        )
        [void]$acl.AddAccessRule($rule)
    }

    if ($PSCmdlet.ShouldProcess($directory.FullName, 'Apply restricted directory ACL')) {
        Set-Acl -LiteralPath $directory.FullName -AclObject $acl
    }
}

function Resolve-SecureDirectory {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string[]]$AllowedRoots
    )

    $normalizedPath = [System.IO.Path]::GetFullPath($Path)
    if (-not (Test-PathWithinAllowedRoot -Path $normalizedPath -AllowedRoots $AllowedRoots)) {
        throw ('Directory path is outside the trusted root: {0}' -f $normalizedPath)
    }

    foreach ($allowedRoot in $AllowedRoots) {
        if ([string]::IsNullOrWhiteSpace($allowedRoot) -or -not (Test-Path -LiteralPath $allowedRoot -PathType Container)) {
            continue
        }

        $allowedRootItem = Get-Item -LiteralPath $allowedRoot -Force -ErrorAction Stop
        if (Test-IsReparsePoint -Item $allowedRootItem) {
            throw ('Trusted root must not be a reparse point: {0}' -f $allowedRootItem.FullName)
        }
    }

    if (Test-Path -LiteralPath $normalizedPath -PathType Container) {
        $directoryItem = Get-Item -LiteralPath $normalizedPath -Force -ErrorAction Stop
        if (Test-IsReparsePoint -Item $directoryItem) {
            throw ('Directory path must not be a reparse point: {0}' -f $normalizedPath)
        }
    }
    elseif (-not $WhatIfPreference) {
        New-Item -ItemType Directory -Path $normalizedPath -Force | Out-Null
    }

    if (-not $WhatIfPreference -and (Test-Path -LiteralPath $normalizedPath -PathType Container)) {
        Set-RestrictedDirectoryAcl -Path $normalizedPath
    }

    return $normalizedPath
}

function Test-TrustedPublisher {
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Signature]$Signature,

        [Parameter(Mandatory)]
        [string[]]$PublisherPatterns
    )

    if ($Signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
        return $false
    }

    if ($null -eq $Signature.SignerCertificate) {
        return $false
    }

    $publisherCandidates = @(
        $Signature.SignerCertificate.GetNameInfo([System.Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false),
        $Signature.SignerCertificate.Subject,
        $Signature.SignerCertificate.Issuer
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($publisherCandidate in $publisherCandidates) {
        foreach ($publisherPattern in $PublisherPatterns) {
            if ($publisherCandidate -like $publisherPattern) {
                return $true
            }
        }
    }

    return $false
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
        [string[]]$TrustedPublisherPatterns,

        [Parameter(Mandatory)]
        [string]$MsiexecPath,

        [Parameter(Mandatory)]
        [string[]]$ProductNamePatterns,

        [Parameter(Mandatory)]
        [string[]]$RegistryPaths,

        [Parameter(Mandatory)]
        [string[]]$ProcessNames,

        [Parameter(Mandatory)]
        [int[]]$SuccessExitCodes
    )

    if (-not (Test-Path -LiteralPath $PackagePath -PathType Leaf)) {
        throw 'Update $ScriptConfig.PackagePath before running the script.'
    }

    if (-not (Test-Path -LiteralPath $MsiexecPath -PathType Leaf)) {
        throw ('Windows Installer executable not found: {0}' -f $MsiexecPath)
    }

    $packageItem = Get-Item -LiteralPath $PackagePath -Force -ErrorAction Stop
    if (Test-IsReparsePoint -Item $packageItem) {
        throw ('Package path must not be a reparse point: {0}' -f $packageItem.FullName)
    }

    $signature = Get-AuthenticodeSignature -FilePath $packageItem.FullName
    if (-not (Test-TrustedPublisher -Signature $signature -PublisherPatterns $TrustedPublisherPatterns)) {
        $publisherName = if ($null -ne $signature.SignerCertificate) {
            $signature.SignerCertificate.GetNameInfo([System.Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false)
        }
        else {
            ''
        }

        throw (
            'Package signature validation failed. Status: {0}. Publisher: {1}' -f
            $signature.Status,
            $(if ([string]::IsNullOrWhiteSpace($publisherName)) { '<unknown>' } else { $publisherName })
        )
    }

    $logDirectoryPath = Resolve-SecureDirectory -Path $LogDirectory -AllowedRoots @($ScriptConfig.StorageRoot)
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
            $rawCommand = "`"$MsiexecPath`" /x $($product.PSChildName)"
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
        $uninstallLogPath = Join-Path -Path $logDirectoryPath -ChildPath ("Uninstall-{0}-{1}.log" -f $timestamp, ($product.PSChildName -replace '[^A-Za-z0-9-]', '_'))

        if ($uninstallFilePath -match '(?i)msiexec(\.exe)?$') {
            $uninstallFilePath = $MsiexecPath
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
    $installLogPath = Join-Path -Path $logDirectoryPath -ChildPath ("Install-{0}.log" -f $timestamp)

    if ([System.IO.Path]::GetExtension($PackagePath) -ieq '.msi') {
        $installFilePath = $MsiexecPath
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
        LogDirectory        = $logDirectoryPath
    }
}

try {
    Invoke-RefreshAdobeAcrobat `
        -PackagePath $ScriptConfig.PackagePath `
        -PackageArguments $ScriptConfig.PackageArguments `
        -LogDirectory $ScriptConfig.LogDirectory `
        -TrustedPublisherPatterns $ScriptConfig.TrustedPublisherPatterns `
        -MsiexecPath $ScriptConfig.MsiexecPath `
        -ProductNamePatterns $ScriptConfig.ProductNamePatterns `
        -RegistryPaths $ScriptConfig.RegistryPaths `
        -ProcessNames $ScriptConfig.ProcessNames `
        -SuccessExitCodes $ScriptConfig.SuccessExitCodes
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
