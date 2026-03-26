. (Resolve-Path (Join-Path $PSScriptRoot '..\..\TestHelpers.ps1')).Path

Describe 'V7 advanced cleanup' {

    BeforeAll {
        $script:ModuleInfo = Import-ScriptModuleForTest -RelativeScriptPath 'PowerShell Script\V7\windows-maintenance\Nettoyage.Avance.Windows.Sauf.logserreur.ps1'
    }

    AfterAll {
        if ($null -ne $script:ModuleInfo) {
            Remove-Module -Name $script:ModuleInfo.ModuleName -Force -ErrorAction SilentlyContinue
        }
    }

    It 'uses the ASCII filename, expanded trusted cache coverage, and safe preview result shape' {
        $result = Invoke-WhatIfScriptObject -Shell pwsh -RelativeScriptPath 'PowerShell Script\V7\windows-maintenance\Nettoyage.Avance.Windows.Sauf.logserreur.ps1'
        $scriptPath = Join-Path (Get-SysadminMainRepoRoot) 'PowerShell Script\V7\windows-maintenance\Nettoyage.Avance.Windows.Sauf.logserreur.ps1'
        $content = Get-Content -LiteralPath $scriptPath -Raw

        $result.Object | Should -Not -BeNullOrEmpty
        (@('Skipped', 'WhatIf') -contains $result.Object.Status) | Should -Be $true
        @('CleanupPathCount', 'RemovedCount', 'RemoveWindowsOld', 'ComponentCleanup', 'Status', 'Reason') |
            ForEach-Object { $result.Object.PSObject.Properties.Name | Should -Contain $_ }

        $content | Should -Match 'CleanupSpecs'
        $content | Should -Match 'Resolve-TrustedDirectoryPath'
        $content | Should -Match 'Get-SafeChildItems'
        $content | Should -Match 'Google\\Chrome\\User Data\\Default\\Cache'
        $content | Should -Match 'Microsoft\\Edge\\User Data\\Default\\Cache'
        $content | Should -Match 'Microsoft\\Teams\\Cache'
        $content | Should -Match 'Mozilla\\Firefox\\Profiles'
        $content | Should -Match 'MSTeams_\*'
        $content | Should -Not -Match '\$env:TEMP'

        if ($result.Object.Status -eq 'Skipped') {
            $result.Object.Reason | Should -Be 'AdminPreviewRequired'
        }
    }

    It 'counts only successful removals and skips Windows.old trust resolution when removal is disabled' {
        $moduleName = $script:ModuleInfo.ModuleName

        InModuleScope $moduleName {
            param($cleanupPathOne, $cleanupPathTwo, $thumbCacheDirectory, $windowsOldPath, $localRoot)

            $successPath = Join-Path $cleanupPathOne 'ok.tmp'
            $failurePath = Join-Path $cleanupPathTwo 'locked.tmp'
            $cleanupItemSuccess = [pscustomobject]@{ FullName = $successPath }
            $cleanupItemFailure = [pscustomobject]@{ FullName = $failurePath }

            $script:ResolvedPaths = @()
            $script:RemovedPaths = @()

            Mock Resolve-TrustedDirectoryPath {
                param($Path, $AllowedRoots)
                $script:ResolvedPaths += $Path
                $Path
            }
            Mock Get-SafeChildItems {
                param($Path)
                if ($Path -eq $cleanupPathOne) { return @($cleanupItemSuccess) }
                if ($Path -eq $cleanupPathTwo) { return @($cleanupItemFailure) }
                @()
            }
            Mock Get-ChildItem { @() } -ParameterFilter {
                $LiteralPath -eq $thumbCacheDirectory -and $File -and $Filter -eq 'thumbcache_*.db'
            }
            Mock Clear-RecycleBin {}
            Mock Remove-Item {
                $script:RemovedPaths += $LiteralPath
                if ($LiteralPath -eq $cleanupItemFailure.FullName) {
                    throw 'simulated remove failure'
                }
            }

            $invokeParams = @{
                RequireAdmin       = $false
                IsAdministrator    = $true
                CleanupSpecs       = @(
                    @{ Path = $cleanupPathOne; AllowedRoots = @($localRoot) },
                    @{ Path = $cleanupPathTwo; AllowedRoots = @($localRoot) }
                )
                ThumbCacheDirectory = $thumbCacheDirectory
                ThumbCacheFilter    = 'thumbcache_*.db'
                WindowsOldPath      = $windowsOldPath
                RemoveWindowsOld    = $false
                RunComponentCleanup = $false
                DismPath            = 'C:\Windows\System32\Dism.exe'
            }
            if ((Get-Command Invoke-AdvancedWindowsCleanup).Parameters.ContainsKey('LocalApplicationDataPath')) {
                $invokeParams.LocalApplicationDataPath = $localRoot
            }

            $result = Invoke-AdvancedWindowsCleanup @invokeParams

            $result.CleanupPathCount | Should -Be 2
            $result.RemovedCount | Should -Be 1
            $result.RemoveWindowsOld | Should -BeFalse
            $result.ComponentCleanup | Should -BeFalse
            $result.Status | Should -Be 'Completed'
            $result.Reason | Should -Be ''

            $script:RemovedPaths.Count | Should -Be 2
            ($script:RemovedPaths -contains $successPath) | Should -BeTrue
            ($script:RemovedPaths -contains $failurePath) | Should -BeTrue
            Assert-MockCalled Clear-RecycleBin -Times 1 -Exactly -Scope It
            ($script:ResolvedPaths -contains $windowsOldPath) | Should -BeFalse
        } -Parameters @{
            cleanupPathOne     = 'C:\Users\Bob\AppData\Local\One'
            cleanupPathTwo     = 'C:\Users\Bob\AppData\Local\Two'
            thumbCacheDirectory = 'C:\Users\Bob\AppData\Local\Microsoft\Windows\Explorer'
            windowsOldPath     = 'C:\Windows.old'
            localRoot          = 'C:\Users\Bob\AppData\Local'
        }
    }
}
