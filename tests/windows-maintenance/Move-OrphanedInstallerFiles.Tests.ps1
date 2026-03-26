. (Resolve-Path (Join-Path $PSScriptRoot '..\TestHelpers.ps1')).Path

Describe 'V5 installer orphan move behavior' {

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
            param($installerPath, $backupPath, $storageRoot, $registryRoot, $referencedPath, $orphanPath, $reparsePath)

            $script:StorageRoot = $storageRoot

            $installerDirectory = [System.IO.DirectoryInfo]::new($installerPath)
            $registryKey = [pscustomobject]@{
                PSPath = 'HKLM:\Software\Test\Product'
            }
            $referencedFile = [System.IO.FileInfo]::new($referencedPath)
            $orphanFile = [System.IO.FileInfo]::new($orphanPath)
            $reparseFile = [System.IO.FileInfo]::new($reparsePath)

            Mock Resolve-SecureDirectory { $Path }
            Mock Test-Path {
                if ($LiteralPath -eq $installerPath) {
                    return $true
                }

                return $false
            }
            Mock Get-Item { $installerDirectory } -ParameterFilter { $LiteralPath -eq $installerPath }
            Mock Get-ChildItem {
                if ($Path -eq $registryRoot) {
                    return @($registryKey)
                }

                return @($referencedFile, $orphanFile, $reparseFile)
            } -ParameterFilter {
                ($Path -eq $registryRoot -and $Recurse) -or
                ($LiteralPath -eq $installerPath -and $File)
            }
            Mock Get-ItemProperty { [pscustomobject]@{ LocalPackage = $referencedPath } } -ParameterFilter { $LiteralPath -eq $registryKey.PSPath }
            Mock Test-IsReparsePoint {
                param($Item)

                $Item.FullName -eq $reparsePath
            }
            Mock Move-Item {}

            $result = Invoke-OrphanedInstallerMove `
                -RequireAdmin $false `
                -IsAdministrator $false `
                -InstallerPath $installerPath `
                -BackupPath $backupPath `
                -RegistryRoot $registryRoot `
                -AllowedExtensions @('.msi', '.msp') `
                -WhatIf

            $result.FileCount | Should -Be 2
            $result.OrphanCount | Should -Be 1
            $result.MovedCount | Should -Be 0
            $result.Status | Should -Be 'WhatIf'

            Assert-MockCalled Move-Item -Times 0 -Exactly -Scope It
        } -Parameters @{
            installerPath  = 'C:\TestData\Installer'
            backupPath     = 'C:\ProgramData\sysadmin-main\Quarantine\InstallerOrphans'
            storageRoot    = 'C:\ProgramData\sysadmin-main'
            registryRoot   = 'HKLM:\Software\Test'
            referencedPath = 'C:\TestData\Installer\kept.msi'
            orphanPath     = 'C:\TestData\Installer\orphan.msi'
            reparsePath    = 'C:\TestData\Installer\skip.msp'
        }
    }

    It 'adds a timestamp suffix before moving when the quarantine target already exists' {
        $moduleName = $script:ModuleInfo.ModuleName

        InModuleScope $moduleName {
            param($installerPath, $backupPath, $storageRoot, $registryRoot, $orphanPath, $destinationPath, $renamedDestinationPath)

            $script:StorageRoot = $storageRoot

            $installerDirectory = [System.IO.DirectoryInfo]::new($installerPath)
            $registryKey = [pscustomobject]@{
                PSPath = 'HKLM:\Software\Test\Product'
            }
            $orphanFile = [System.IO.FileInfo]::new($orphanPath)

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
            Mock Get-ChildItem {
                if ($Path -eq $registryRoot) {
                    return @($registryKey)
                }

                return @($orphanFile)
            } -ParameterFilter {
                ($Path -eq $registryRoot -and $Recurse) -or
                ($LiteralPath -eq $installerPath -and $File)
            }
            Mock Get-ItemProperty { [pscustomobject]@{ LocalPackage = 'C:\TestData\Installer\kept.msi' } } -ParameterFilter { $LiteralPath -eq $registryKey.PSPath }
            Mock Test-IsReparsePoint { $false }
            Mock Get-Date { [datetime]'2025-01-02T03:04:05.678' }
            Mock Move-Item {}

            $result = Invoke-OrphanedInstallerMove `
                -RequireAdmin $false `
                -IsAdministrator $false `
                -InstallerPath $installerPath `
                -BackupPath $backupPath `
                -RegistryRoot $registryRoot `
                -AllowedExtensions @('.msi', '.msp')

            $result.MovedCount | Should -Be 1
            $result.Status | Should -Be 'Completed'

            Assert-MockCalled Move-Item -Times 1 -Exactly -Scope It
            Assert-MockCalled Get-Date -Times 1 -Exactly -Scope It
        } -Parameters @{
            installerPath           = 'C:\TestData\Installer'
            backupPath              = 'C:\ProgramData\sysadmin-main\Quarantine\InstallerOrphans'
            storageRoot             = 'C:\ProgramData\sysadmin-main'
            registryRoot            = 'HKLM:\Software\Test'
            orphanPath              = 'C:\TestData\Installer\orphan.msi'
            destinationPath         = 'C:\ProgramData\sysadmin-main\Quarantine\InstallerOrphans\orphan.msi'
            renamedDestinationPath  = 'C:\ProgramData\sysadmin-main\Quarantine\InstallerOrphans\orphan_20250102030405678.msi'
        }
    }

    It 'returns a skipped result without creating quarantine when no installer references exist' {
        $moduleName = $script:ModuleInfo.ModuleName

        InModuleScope $moduleName {
            param($installerPath, $backupPath, $storageRoot, $registryRoot)

            $script:StorageRoot = $storageRoot

            $installerDirectory = [System.IO.DirectoryInfo]::new($installerPath)

            Mock Test-Path { $LiteralPath -eq $installerPath }
            Mock Get-Item { $installerDirectory } -ParameterFilter { $LiteralPath -eq $installerPath }
            Mock Get-ChildItem { @() } -ParameterFilter { $Path -eq $registryRoot -and $Recurse }
            Mock Test-IsReparsePoint { $false }
            Mock Resolve-SecureDirectory { $Path }
            Mock Move-Item {}

            $result = Invoke-OrphanedInstallerMove `
                -RequireAdmin $false `
                -IsAdministrator $false `
                -InstallerPath $installerPath `
                -BackupPath $backupPath `
                -RegistryRoot $registryRoot `
                -AllowedExtensions @('.msi', '.msp')

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
            registryRoot  = 'HKLM:\Software\Test'
        }
    }
}
