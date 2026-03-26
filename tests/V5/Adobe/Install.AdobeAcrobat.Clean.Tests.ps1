. (Resolve-Path (Join-Path $PSScriptRoot '..\..\TestHelpers.ps1')).Path

Describe 'V5 Adobe Acrobat refresh behavior' {

    BeforeAll {
        . (Resolve-Path (Join-Path $PSScriptRoot '..\..\TestHelpers.ps1')).Path
        $script:ModuleInfo = Import-ScriptModuleForTest -RelativeScriptPath 'PowerShell Script\V5\Adobe\Install.AdobeAcrobat.Clean.ps1'
    }

    AfterAll {
        if ($null -ne $script:ModuleInfo) {
            Remove-Module -Name $script:ModuleInfo.ModuleName -Force -ErrorAction SilentlyContinue
        }
    }

    It 'blocks installer execution when publisher validation fails' {
        $moduleName = $script:ModuleInfo.ModuleName
        $packagePath = Join-Path $env:TEMP ('codex-adobe-{0}.msi' -f [guid]::NewGuid().ToString('N'))

        Set-Content -LiteralPath $packagePath -Value 'unsigned test package'

        try {
            InModuleScope $moduleName {
                param($packagePath, $logDirectory, $msiexecPath)

                Mock Resolve-SecureDirectory { $Path }
                Mock Start-Process {}

                {
                    Invoke-AdobeAcrobatRefresh `
                        -RequireAdmin $false `
                        -IsAdministrator $false `
                        -PackagePath $packagePath `
                        -PackageArguments 'ignored' `
                        -LogDirectory $logDirectory `
                        -TrustedPublisherPatterns @('*') `
                        -MsiexecPath $msiexecPath `
                        -ProductNamePatterns @('Adobe Acrobat*') `
                        -RegistryPaths @('HKLM:\Software\Test\*') `
                        -ProcessNames @('Acrobat') `
                        -SuccessExitCodes @(0, 1641, 3010)
                } | Should -Throw '*Package signature validation failed*'

                Assert-MockCalled Resolve-SecureDirectory -Times 0 -Exactly -Scope It
                Assert-MockCalled Start-Process -Times 0 -Exactly -Scope It
            } -Parameters @{
                packagePath  = $packagePath
                logDirectory = 'C:\ProgramData\sysadmin-main\Logs\AdobeAcrobat'
                msiexecPath  = 'C:\Windows\System32\msiexec.exe'
            }
        }
        finally {
            Remove-Item -LiteralPath $packagePath -Force -ErrorAction SilentlyContinue
        }
    }

    It 'returns a WhatIf result and suppresses Start-Process during preview without elevation' {
        $moduleName = $script:ModuleInfo.ModuleName

        InModuleScope $moduleName {
            param($packagePath, $logDirectory, $storageRoot, $msiexecPath)

            $script:StorageRoot = $storageRoot

            Mock Resolve-SecureDirectory { $Path }
            Mock Get-ItemProperty { @() }
            Mock Get-Process { @() }
            Mock Start-Process {}

            $result = Invoke-AdobeAcrobatRefresh `
                -RequireAdmin $true `
                -IsAdministrator $false `
                -PackagePath $packagePath `
                -PackageArguments '/quiet' `
                -LogDirectory $logDirectory `
                -TrustedPublisherPatterns @('*') `
                -MsiexecPath $msiexecPath `
                -ProductNamePatterns @('Adobe Acrobat*') `
                -RegistryPaths @('HKLM:\Software\Test\*') `
                -ProcessNames @('Acrobat') `
                -SuccessExitCodes @(0, 1641, 3010) `
                -WhatIf

            $result.PackagePath | Should -Be $packagePath
            $result.LogDirectory | Should -Be $logDirectory
            $result.Status | Should -Be 'WhatIf'
            $result.Reason | Should -Be ''

            Assert-MockCalled Resolve-SecureDirectory -Times 1 -Exactly -Scope It -ParameterFilter {
                $Path -eq $logDirectory -and $AllowedRoots[0] -eq $storageRoot
            }
            Assert-MockCalled Start-Process -Times 0 -Exactly -Scope It
        } -Parameters @{
            packagePath  = 'C:\Windows\System32\notepad.exe'
            logDirectory = 'C:\ProgramData\sysadmin-main\Logs\AdobeAcrobat'
            storageRoot  = 'C:\ProgramData\sysadmin-main'
            msiexecPath  = 'C:\Windows\System32\msiexec.exe'
        }
    }

    It 'returns a skipped result when the package path is missing during a real run' {
        $moduleName = $script:ModuleInfo.ModuleName

        InModuleScope $moduleName {
            param($packagePath, $logDirectory, $msiexecPath)

            Mock Resolve-SecureDirectory { $Path }
            Mock Start-Process {}

            $result = Invoke-AdobeAcrobatRefresh `
                -RequireAdmin $false `
                -IsAdministrator $false `
                -PackagePath $packagePath `
                -PackageArguments '' `
                -LogDirectory $logDirectory `
                -TrustedPublisherPatterns @('Adobe*') `
                -MsiexecPath $msiexecPath `
                -ProductNamePatterns @('Adobe Acrobat*') `
                -RegistryPaths @('HKLM:\Software\Test\*') `
                -ProcessNames @('Acrobat') `
                -SuccessExitCodes @(0, 1641, 3010)

            $result.PackagePath | Should -Be $packagePath
            $result.Status | Should -Be 'Skipped'
            $result.Reason | Should -Be 'PackagePathNotFound'

            Assert-MockCalled Resolve-SecureDirectory -Times 0 -Exactly -Scope It
            Assert-MockCalled Start-Process -Times 0 -Exactly -Scope It
        } -Parameters @{
            packagePath  = 'C:\Install\Adobe\MissingInstaller.msi'
            logDirectory = 'C:\ProgramData\sysadmin-main\Logs\AdobeAcrobat'
            msiexecPath  = 'C:\Windows\System32\msiexec.exe'
        }
    }
}
