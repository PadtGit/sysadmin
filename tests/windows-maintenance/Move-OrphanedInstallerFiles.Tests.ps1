. (Resolve-Path (Join-Path $PSScriptRoot '..\TestHelpers.ps1')).Path

Describe 'V7 installer orphan move behavior' {

    BeforeAll {
        . (Resolve-Path (Join-Path $PSScriptRoot '..\TestHelpers.ps1')).Path
        $script:ModuleInfo = Import-ScriptModuleForTest -RelativeScriptPath 'PowerShell Script\windows-maintenance\Move-OrphanedInstallerFiles.ps1'
    }

    AfterAll {
        if ($null -ne $script:ModuleInfo) {
            Remove-Module -Name $script:ModuleInfo.ModuleName -Force -ErrorAction SilentlyContinue
        }
    }

    It 'skips reparse points and suppresses Move-Item during WhatIf preview' {
        $moduleName = $script:ModuleInfo.ModuleName

        InModuleScope $moduleName {
            param($installerPath, $backupPath, $storageRoot, $orphanPath, $reparsePath)

            $script:ScriptConfig = @{
                StorageRoot = $storageRoot
            }

            $fakeProduct = [pscustomobject]@{}
            $fakeProduct | Add-Member -MemberType ScriptMethod -Name InstallProperty -Value { param($Name) 'C:\TestData\Installer\known.msi' }
            $fakeProduct | Add-Member -MemberType ScriptMethod -Name ProductCode -Value { '' }

            $fakeInstaller = [pscustomobject]@{}
            $fakeInstaller | Add-Member -MemberType ScriptMethod -Name ProductsEx -Value ({ param($UserSid, $ProductCode, $Context) @($fakeProduct) }.GetNewClosure())
            $fakeInstaller | Add-Member -MemberType ScriptMethod -Name PatchesEx -Value ({ param($ProductCode, $UserSid, $Context, $State) @() }.GetNewClosure())

            $installerDirectory = [System.IO.DirectoryInfo]::new($installerPath)
            $orphanFile = [System.IO.FileInfo]::new($orphanPath)
            $reparseFile = [System.IO.FileInfo]::new($reparsePath)

            Mock New-Object { $fakeInstaller } -ParameterFilter { $ComObject -eq 'WindowsInstaller.Installer' }
            Mock Resolve-SecureDirectory { $Path }
            Mock Test-Path {
                if ($LiteralPath -eq $installerPath) {
                    return $true
                }

                return $false
            }
            Mock Get-Item { $installerDirectory } -ParameterFilter { $LiteralPath -eq $installerPath }
            Mock Get-ChildItem { @($orphanFile, $reparseFile) } -ParameterFilter { $LiteralPath -eq $installerPath -and $File }
            Mock Test-IsReparsePoint {
                param($Item)

                $Item.FullName -eq $reparsePath
            }
            Mock Move-Item {}

            $result = Invoke-MoveOrphanedInstallerFiles `
                -RequireAdmin $false `
                -IsAdministrator $false `
                -InstallerPath $installerPath `
                -BackupPath $backupPath `
                -Contexts @(1) `
                -PatchState 7 `
                -WhatIf

            $result.FileCount | Should -Be 1
            $result.OrphanCount | Should -Be 1
            $result.MovedCount | Should -Be 0
            $result.Status | Should -Be 'WhatIf'

            Assert-MockCalled Move-Item -Times 0 -Exactly -Scope It
        } -Parameters @{
            installerPath = 'C:\TestData\Installer'
            backupPath    = 'C:\ProgramData\sysadmin-main\Quarantine\InstallerOrphans'
            storageRoot   = 'C:\ProgramData\sysadmin-main'
            orphanPath    = 'C:\TestData\Installer\orphan.msi'
            reparsePath   = 'C:\TestData\Installer\skip.msp'
        }
    }

    It 'adds a timestamp suffix before moving when the quarantine target already exists' {
        $moduleName = $script:ModuleInfo.ModuleName

        InModuleScope $moduleName {
            param($installerPath, $backupPath, $storageRoot, $orphanPath, $destinationPath, $renamedDestinationPath)

            $script:ScriptConfig = @{
                StorageRoot = $storageRoot
            }

            $fakeProduct = [pscustomobject]@{}
            $fakeProduct | Add-Member -MemberType ScriptMethod -Name InstallProperty -Value { param($Name) 'C:\TestData\Installer\known.msi' }
            $fakeProduct | Add-Member -MemberType ScriptMethod -Name ProductCode -Value { '' }

            $fakeInstaller = [pscustomobject]@{}
            $fakeInstaller | Add-Member -MemberType ScriptMethod -Name ProductsEx -Value ({ param($UserSid, $ProductCode, $Context) @($fakeProduct) }.GetNewClosure())
            $fakeInstaller | Add-Member -MemberType ScriptMethod -Name PatchesEx -Value ({ param($ProductCode, $UserSid, $Context, $State) @() }.GetNewClosure())

            $installerDirectory = [System.IO.DirectoryInfo]::new($installerPath)
            $orphanFile = [System.IO.FileInfo]::new($orphanPath)

            Mock New-Object { $fakeInstaller } -ParameterFilter { $ComObject -eq 'WindowsInstaller.Installer' }
            Mock Resolve-SecureDirectory { $Path }
            Mock Test-Path {
                if ($LiteralPath -eq $installerPath) {
                    return $true
                }

                if ($LiteralPath -eq $destinationPath) {
                    return $true
                }

                return $false
            }
            Mock Get-Item { $installerDirectory } -ParameterFilter { $LiteralPath -eq $installerPath }
            Mock Get-ChildItem { @($orphanFile) } -ParameterFilter { $LiteralPath -eq $installerPath -and $File }
            Mock Test-IsReparsePoint { $false }
            Mock Get-Date { [datetime]'2025-01-02T03:04:05.678' }
            Mock Move-Item {}

            $result = Invoke-MoveOrphanedInstallerFiles `
                -RequireAdmin $false `
                -IsAdministrator $false `
                -InstallerPath $installerPath `
                -BackupPath $backupPath `
                -Contexts @(1) `
                -PatchState 7

            $result.MovedCount | Should -Be 1
            $result.Status | Should -Be 'Completed'

            Assert-MockCalled Move-Item -Times 1 -Exactly -Scope It
            Assert-MockCalled Get-Date -Times 1 -Exactly -Scope It
        } -Parameters @{
            installerPath           = 'C:\TestData\Installer'
            backupPath              = 'C:\ProgramData\sysadmin-main\Quarantine\InstallerOrphans'
            storageRoot             = 'C:\ProgramData\sysadmin-main'
            orphanPath              = 'C:\TestData\Installer\orphan.msi'
            destinationPath         = 'C:\ProgramData\sysadmin-main\Quarantine\InstallerOrphans\orphan.msi'
            renamedDestinationPath  = 'C:\ProgramData\sysadmin-main\Quarantine\InstallerOrphans\orphan_20250102030405678.msi'
        }
    }

    It 'returns a skipped result without creating quarantine when no installer references exist' {
        $moduleName = $script:ModuleInfo.ModuleName

        InModuleScope $moduleName {
            param($installerPath, $backupPath, $storageRoot)

            $script:ScriptConfig = @{
                StorageRoot = $storageRoot
            }

            $fakeInstaller = [pscustomobject]@{}
            $fakeInstaller | Add-Member -MemberType ScriptMethod -Name ProductsEx -Value { param($UserSid, $ProductCode, $Context) @() }
            $fakeInstaller | Add-Member -MemberType ScriptMethod -Name PatchesEx -Value { param($ProductCode, $UserSid, $Context, $State) @() }

            $installerDirectory = [System.IO.DirectoryInfo]::new($installerPath)

            Mock New-Object { $fakeInstaller } -ParameterFilter { $ComObject -eq 'WindowsInstaller.Installer' }
            Mock Test-Path { $LiteralPath -eq $installerPath }
            Mock Get-Item { $installerDirectory } -ParameterFilter { $LiteralPath -eq $installerPath }
            Mock Test-IsReparsePoint { $false }
            Mock Resolve-SecureDirectory { $Path }
            Mock Move-Item {}

            $result = Invoke-MoveOrphanedInstallerFiles `
                -RequireAdmin $false `
                -IsAdministrator $false `
                -InstallerPath $installerPath `
                -BackupPath $backupPath `
                -Contexts @(1) `
                -PatchState 7

            $result.Status | Should -Be 'Skipped'
            $result.Reason | Should -Be 'NoReferencesFound'
            $result.OrphanCount | Should -Be 0
            $result.MovedCount | Should -Be 0

            Assert-MockCalled Resolve-SecureDirectory -Times 0 -Exactly -Scope It
            Assert-MockCalled Move-Item -Times 0 -Exactly -Scope It
        } -Parameters @{
            installerPath = 'C:\TestData\Installer'
            backupPath    = 'C:\ProgramData\sysadmin-main\Quarantine\InstallerOrphans'
            storageRoot   = 'C:\ProgramData\sysadmin-main'
        }
    }
}


