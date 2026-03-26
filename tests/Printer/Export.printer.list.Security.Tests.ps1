Describe 'V5 printer export hardening' {
    . (Resolve-Path (Join-Path $PSScriptRoot '..\TestHelpers.ps1')).Path

    BeforeAll {
$script:BasicModuleInfo = Import-ScriptModuleForTest -RelativeScriptPath 'PowerShell Script\Printer\Export.printer.list.BASIC.ps1'
    }

    AfterAll {
        if ($null -ne $script:BasicModuleInfo) {
            Remove-Module -Name $script:BasicModuleInfo.ModuleName -Force -ErrorAction SilentlyContinue
        }
    }

    It 'uses a secured per-user path and unique file name for the basic export preview' {
$Result = Invoke-WhatIfScriptObject -RelativeScriptPath 'PowerShell Script\Printer\Export.printer.list.BASIC.ps1'

        $Result.Object | Should -Not -BeNullOrEmpty
        $Result.Object.OutputPath | Should -Match 'sysadmin-main\\Exports\\Printers\\printers-basic-'
        $Result.Object.OutputPath | Should -Not -Match 'C:\\Temp'
    }

    It 'uses a secured per-user path and unique file name for the full export preview' {
$Result = Invoke-WhatIfScriptObject -RelativeScriptPath 'PowerShell Script\Printer\Export.printer.list.FULL.ps1'

        $Result.Object | Should -Not -BeNullOrEmpty
        $Result.Object.OutputPath | Should -Match 'sysadmin-main\\Exports\\Printers\\printers-full-'
        $Result.Object.OutputPath | Should -Not -Match 'C:\\Temp'
    }

    It 'restricts the export directory in code' {
$BasicContent = Get-Content -LiteralPath (Join-Path (Get-SysadminMainRepoRoot) 'PowerShell Script\Printer\Export.printer.list.BASIC.ps1') -Raw
$FullContent = Get-Content -LiteralPath (Join-Path (Get-SysadminMainRepoRoot) 'PowerShell Script\Printer\Export.printer.list.FULL.ps1') -Raw

        $BasicContent | Should -Match 'Resolve-SecureDirectory'
        $BasicContent | Should -Match 'Set-RestrictedDirectoryAcl'
        $FullContent | Should -Match 'Resolve-SecureDirectory'
        $FullContent | Should -Match 'Set-RestrictedDirectoryAcl'
    }

    It 'does not rewrite ACLs when the export directory already exists' {
        $moduleName = $script:BasicModuleInfo.ModuleName

        InModuleScope $moduleName {
            param($storageRoot, $outputDirectory)

            $storageRootItem = [System.IO.DirectoryInfo]::new($storageRoot)
            $outputDirectoryItem = [System.IO.DirectoryInfo]::new($outputDirectory)

            Mock Test-Path {
                if ($LiteralPath -eq $storageRoot -or $LiteralPath -eq $outputDirectory) {
                    return $true
                }

                return $false
            }
            Mock Get-Item {
                if ($LiteralPath -eq $storageRoot) {
                    return $storageRootItem
                }

                return $outputDirectoryItem
            }
            Mock Test-IsReparsePoint { $false }
            Mock New-Item {}
            Mock Set-RestrictedDirectoryAcl {}

            $resolvedPath = Resolve-SecureDirectory -Path $outputDirectory -AllowedRoots @($storageRoot)

            $resolvedPath | Should -Be $outputDirectory
            Assert-MockCalled New-Item -Times 0 -Exactly -Scope It
            Assert-MockCalled Set-RestrictedDirectoryAcl -Times 0 -Exactly -Scope It
        } -Parameters @{
            storageRoot     = 'C:\Users\Test\AppData\Local\sysadmin-main'
            outputDirectory = 'C:\Users\Test\AppData\Local\sysadmin-main\Exports\Printers'
        }
    }

    It 'hardens a newly created export directory once' {
        $moduleName = $script:BasicModuleInfo.ModuleName

        InModuleScope $moduleName {
            param($storageRoot, $outputDirectory)

            $storageRootItem = [System.IO.DirectoryInfo]::new($storageRoot)

            Mock Test-Path {
                if ($LiteralPath -eq $storageRoot) {
                    return $true
                }

                return $false
            }
            Mock Get-Item { $storageRootItem } -ParameterFilter { $LiteralPath -eq $storageRoot }
            Mock Test-IsReparsePoint { $false }
            Mock New-Item { [pscustomobject]@{ FullName = $Path } }
            Mock Set-RestrictedDirectoryAcl {}

            $resolvedPath = Resolve-SecureDirectory -Path $outputDirectory -AllowedRoots @($storageRoot)

            $resolvedPath | Should -Be $outputDirectory
            Assert-MockCalled New-Item -Times 1 -Exactly -Scope It -ParameterFilter {
                $ItemType -eq 'Directory' -and $Path -eq $outputDirectory -and $Force
            }
            Assert-MockCalled Set-RestrictedDirectoryAcl -Times 1 -Exactly -Scope It -ParameterFilter {
                $Path -eq $outputDirectory
            }
        } -Parameters @{
            storageRoot     = 'C:\Users\Test\AppData\Local\sysadmin-main'
            outputDirectory = 'C:\Users\Test\AppData\Local\sysadmin-main\Exports\Printers'
        }
    }
}
