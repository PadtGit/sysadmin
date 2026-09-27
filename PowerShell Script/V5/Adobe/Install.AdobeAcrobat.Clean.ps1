#Requires -Version 5.1

[CmdletBinding(SupportsShouldProcess = $true)]
param()

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

$CommonApplicationDataPath = [Environment]::GetFolderPath('CommonApplicationData')

$RequireAdmin = $true
$IsAdministrator = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$PackagePath = 'C:\Install\Adobe\AcrobatInstaller.msi'
$PackageArguments = ''
$StorageRoot = Join-Path -Path $CommonApplicationDataPath -ChildPath 'sysadmin-main'
$LogDirectory = Join-Path -Path $CommonApplicationDataPath -ChildPath 'sysadmin-main\Logs\AdobeAcrobat'
$TrustedPublisherPatterns = @(
    'Adobe*'
)
$MsiexecPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\msiexec.exe'
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

function Test-PathWithinAllowedRoot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string[]]$AllowedRoots
    )

    $NormalizedPath = [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
    foreach ($AllowedRoot in $AllowedRoots) {
        if ([string]::IsNullOrWhiteSpace($AllowedRoot)) {
            continue
        }

        $NormalizedRoot = [System.IO.Path]::GetFullPath($AllowedRoot).TrimEnd('\')
        if ($NormalizedPath.Equals($NormalizedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }

        if ($NormalizedPath.StartsWith(($NormalizedRoot + '\'), [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }

    return $false
}

function Test-IsReparsePoint {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.FileSystemInfo]$Item
    )

    return (($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Set-RestrictedDirectoryAcl {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $Directory = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    if (-not $Directory.PSIsContainer) {
        throw ('Secure directory path must be a directory: {0}' -f $Path)
    }

    if (Test-IsReparsePoint -Item $Directory) {
        throw ('Secure directory path must not be a reparse point: {0}' -f $Path)
    }

    $CurrentUserSid = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $AdministratorsSid = [Security.Principal.SecurityIdentifier]::new([Security.Principal.WellKnownSidType]::BuiltinAdministratorsSid, $null)
    $SystemSid = [Security.Principal.SecurityIdentifier]::new([Security.Principal.WellKnownSidType]::LocalSystemSid, $null)
    $InheritanceFlags = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
    $PropagationFlags = [System.Security.AccessControl.PropagationFlags]::None
    $Rights = [System.Security.AccessControl.FileSystemRights]::FullControl
    $AccessType = [System.Security.AccessControl.AccessControlType]::Allow
    $Acl = [System.Security.AccessControl.DirectorySecurity]::new()
    $Acl.SetAccessRuleProtection($true, $false)

    foreach ($SidGroup in @($CurrentUserSid, $AdministratorsSid, $SystemSid) | Group-Object Value) {
        $Rule = [System.Security.AccessControl.FileSystemAccessRule]::new(
            $SidGroup.Group[0],
            $Rights,
            $InheritanceFlags,
            $PropagationFlags,
            $AccessType
        )
        [void]$Acl.AddAccessRule($Rule)
    }

    if ($PSCmdlet.ShouldProcess($Directory.FullName, 'Apply restricted directory ACL')) {
        Set-Acl -LiteralPath $Directory.FullName -AclObject $Acl
    }
}

function Resolve-SecureDirectory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string[]]$AllowedRoots
    )

    $NormalizedPath = [System.IO.Path]::GetFullPath($Path)
    if (-not (Test-PathWithinAllowedRoot -Path $NormalizedPath -AllowedRoots $AllowedRoots)) {
        throw ('Directory path is outside the trusted root: {0}' -f $NormalizedPath)
    }

    foreach ($AllowedRoot in $AllowedRoots) {
        if ([string]::IsNullOrWhiteSpace($AllowedRoot) -or -not (Test-Path -LiteralPath $AllowedRoot -PathType Container)) {
            continue
        }

        $AllowedRootItem = Get-Item -LiteralPath $AllowedRoot -Force -ErrorAction Stop
        if (Test-IsReparsePoint -Item $AllowedRootItem) {
            throw ('Trusted root must not be a reparse point: {0}' -f $AllowedRootItem.FullName)
        }
    }

    $CreatedDirectory = $false

    if (Test-Path -LiteralPath $NormalizedPath -PathType Container) {
        $DirectoryItem = Get-Item -LiteralPath $NormalizedPath -Force -ErrorAction Stop
        if (Test-IsReparsePoint -Item $DirectoryItem) {
            throw ('Directory path must not be a reparse point: {0}' -f $NormalizedPath)
        }
    }
    elseif (-not $WhatIfPreference) {
        New-Item -ItemType Directory -Path $NormalizedPath -Force | Out-Null
        $CreatedDirectory = $true
    }

    if ($CreatedDirectory) {
        Set-RestrictedDirectoryAcl -Path $NormalizedPath
    }

    return $NormalizedPath
}

function Test-TrustedPublisher {
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Signature]$Signature,

        [Parameter(Mandatory = $true)]
        [string[]]$PublisherPatterns
    )

    if ($Signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid) {
        return $false
    }

    if ($null -eq $Signature.SignerCertificate) {
        return $false
    }

    $PublisherCandidates = @(
        $Signature.SignerCertificate.GetNameInfo([System.Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false),
        $Signature.SignerCertificate.Subject,
        $Signature.SignerCertificate.Issuer
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($PublisherCandidate in $PublisherCandidates) {
        foreach ($PublisherPattern in $PublisherPatterns) {
            if ($PublisherCandidate -like $PublisherPattern) {
                return $true
            }
        }
    }

    return $false
}

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
        [string[]]$TrustedPublisherPatterns,

        [Parameter(Mandatory = $true)]
        [string]$MsiexecPath,

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

    if (-not (Test-Path -LiteralPath $MsiexecPath -PathType Leaf)) {
        throw ('Windows Installer executable not found: {0}' -f $MsiexecPath)
    }

    $PackageItem = Get-Item -LiteralPath $PackagePath -Force -ErrorAction Stop
    if (Test-IsReparsePoint -Item $PackageItem) {
        throw ('Package path must not be a reparse point: {0}' -f $PackageItem.FullName)
    }

    $Signature = Get-AuthenticodeSignature -FilePath $PackageItem.FullName
    if (-not (Test-TrustedPublisher -Signature $Signature -PublisherPatterns $TrustedPublisherPatterns)) {
        $PublisherName = if ($null -ne $Signature.SignerCertificate) {
            $Signature.SignerCertificate.GetNameInfo([System.Security.Cryptography.X509Certificates.X509NameType]::SimpleName, $false)
        }
        else {
            ''
        }

        throw (
            'Package signature validation failed. Status: {0}. Publisher: {1}' -f
            $Signature.Status,
            $(if ([string]::IsNullOrWhiteSpace($PublisherName)) { '<unknown>' } else { $PublisherName })
        )
    }

    $SecureLogDirectory = Resolve-SecureDirectory -Path $LogDirectory -AllowedRoots @($StorageRoot)
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
            $RawCommand = '"{0}" /x {1}' -f $MsiexecPath, $Product.PSChildName
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
        $UninstallLogPath = Join-Path -Path $SecureLogDirectory -ChildPath ('Uninstall-{0}-{1}.log' -f $TimeStamp, ($Product.PSChildName -replace '[^A-Za-z0-9-]', '_'))

        if ($UninstallFilePath -match '(?i)msiexec(\.exe)?$') {
            $UninstallFilePath = $MsiexecPath
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
    $InstallLogPath = Join-Path -Path $SecureLogDirectory -ChildPath ('Install-{0}.log' -f $TimeStamp)

    if ([System.IO.Path]::GetExtension($PackagePath) -ieq '.msi') {
        $InstallFilePath = $MsiexecPath
        $InstallArguments = '/i "{0}" /qn /norestart /L*v "{1}"' -f $PackagePath, $InstallLogPath
    }
    elseif ([string]::IsNullOrWhiteSpace($InstallArguments)) {
        if ($WhatIfPreference) {
            return [pscustomobject]@{
                PackagePath         = $PackagePath
                RemovedProductCount = $RemovedProducts.Count
                RemovedProducts     = $RemovedProducts -join '; '
                RestartRequired     = $RestartRequired
                LogDirectory        = $SecureLogDirectory
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
        LogDirectory        = $SecureLogDirectory
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
        -TrustedPublisherPatterns $TrustedPublisherPatterns `
        -MsiexecPath $MsiexecPath `
        -ProductNamePatterns $ProductNamePatterns `
        -RegistryPaths $RegistryPaths `
        -ProcessNames $ProcessNames `
        -SuccessExitCodes $SuccessExitCodes
}
catch {
    Write-Error $_.Exception.Message
    exit 1
}
