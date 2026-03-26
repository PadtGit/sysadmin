. (Resolve-Path (Join-Path $PSScriptRoot '..\TestHelpers.ps1')).Path

Describe 'V7 logged spool cleanup behavior' {

    BeforeAll {
        . (Resolve-Path (Join-Path $PSScriptRoot '..\TestHelpers.ps1')).Path
        $script:ModuleInfo = Import-ScriptModuleForTest -RelativeScriptPath 'PowerShell Script\Printer\restart.SpoolDeleteQV4.ps1'
    }

    AfterAll {
        if ($null -ne $script:ModuleInfo) {
            Remove-Module -Name $script:ModuleInfo.ModuleName -Force -ErrorAction SilentlyContinue
        }
    }

    It 'resolves a secure log path and suppresses service and file mutations during WhatIf preview' {
        $moduleName = $script:ModuleInfo.ModuleName

        InModuleScope $moduleName {
            param($serviceName, $spoolDirectory, $logDirectory, $storageRoot, $logPath)

            $script:ScriptConfig = @{
                StorageRoot = $storageRoot
            }

            $service = [pscustomobject]@{
                Status = [System.ServiceProcess.ServiceControllerStatus]::Running
            }
            $spoolFile = [System.IO.FileInfo]::new((Join-Path $spoolDirectory 'job1.spl'))

            Mock Resolve-SecureDirectory { $Path }
            Mock Get-UniqueChildPath { $logPath }
            Mock Get-Service { $service }
            Mock Get-ChildItem { @($spoolFile) } -ParameterFilter { $LiteralPath -eq $spoolDirectory -and $File }
            Mock Start-Transcript {}
            Mock Stop-Transcript {}
            Mock Stop-Service {}
            Mock Start-Service {}
            Mock Remove-Item {}

            $invokeParams = @{
                ServiceName    = $serviceName
                SpoolDirectory = $spoolDirectory
                TimeoutSeconds = 30
                LogDirectory   = $logDirectory
                LogFilePrefix  = 'print-queue'
            }
            if ((Get-Command Invoke-ClearPrintQueueLogged).Parameters.ContainsKey('StorageRoot')) {
                $invokeParams.StorageRoot = $storageRoot
            }

            $result = Invoke-ClearPrintQueueLogged @invokeParams `
                -WhatIf

            $result.LogPath | Should -Be $logPath
            $result.DeletedFiles | Should -Be 0

            if ($null -ne $result.PSObject.Properties['WhatIfRun']) {
                $result.WhatIfRun | Should -BeTrue
                $result.Success | Should -BeTrue
                $result.Service | Should -Be $serviceName
            }
            else {
                $result.ServiceWasUp | Should -BeTrue
                $result.ServiceName | Should -Be $serviceName
            }

            Assert-MockCalled Resolve-SecureDirectory -Times 1 -Exactly -Scope It -ParameterFilter {
                $Path -eq $logDirectory -and $AllowedRoots[0] -eq $storageRoot
            }
            Assert-MockCalled Get-UniqueChildPath -Times 1 -Exactly -Scope It -ParameterFilter {
                $Directory -eq $logDirectory -and $FileNamePrefix -eq 'print-queue' -and $Extension -eq '.log'
            }
            Assert-MockCalled Start-Transcript -Times 0 -Exactly -Scope It
            Assert-MockCalled Stop-Service -Times 0 -Exactly -Scope It
            Assert-MockCalled Remove-Item -Times 0 -Exactly -Scope It
            Assert-MockCalled Start-Service -Times 0 -Exactly -Scope It
        } -Parameters @{
            serviceName    = 'Spooler'
            spoolDirectory = 'C:\Windows\System32\spool\PRINTERS'
            logDirectory   = 'C:\ProgramData\sysadmin-main\Logs\Printer'
            storageRoot    = 'C:\ProgramData\sysadmin-main'
            logPath        = 'C:\ProgramData\sysadmin-main\Logs\Printer\print-queue-20250102.log'
        }
    }

    It 'does not restart the service when this invocation never stopped it' {
        $moduleName = $script:ModuleInfo.ModuleName

        InModuleScope $moduleName {
            param($serviceName, $spoolDirectory, $logDirectory, $storageRoot, $logPath)

            $script:ScriptConfig = @{
                StorageRoot = $storageRoot
            }

            $service = [pscustomobject]@{
                Status = [System.ServiceProcess.ServiceControllerStatus]::Stopped
            }

            Mock Resolve-SecureDirectory { $Path }
            Mock Get-UniqueChildPath { $logPath }
            Mock Get-Service { $service }
            Mock Get-ChildItem { @() } -ParameterFilter { $LiteralPath -eq $spoolDirectory -and $File }
            Mock Start-Transcript {}
            Mock Stop-Transcript {}
            Mock Stop-Service {}
            Mock Start-Service {}
            Mock Remove-Item {}

            $invokeParams = @{
                ServiceName    = $serviceName
                SpoolDirectory = $spoolDirectory
                TimeoutSeconds = 30
                LogDirectory   = $logDirectory
                LogFilePrefix  = 'print-queue'
            }
            if ((Get-Command Invoke-ClearPrintQueueLogged).Parameters.ContainsKey('StorageRoot')) {
                $invokeParams.StorageRoot = $storageRoot
            }

            $result = Invoke-ClearPrintQueueLogged @invokeParams

            $result.DeletedFiles | Should -Be 0
            if ($result.PSObject.Properties.Name -contains 'ServiceWasUp') {
                $result.ServiceWasUp | Should -BeFalse
            }

            Assert-MockCalled Start-Transcript -Times 1 -Exactly -Scope It
            Assert-MockCalled Stop-Transcript -Times 1 -Exactly -Scope It
            Assert-MockCalled Stop-Service -Times 0 -Exactly -Scope It
            Assert-MockCalled Start-Service -Times 0 -Exactly -Scope It
        } -Parameters @{
            serviceName    = 'Spooler'
            spoolDirectory = 'C:\Windows\System32\spool\PRINTERS'
            logDirectory   = 'C:\ProgramData\sysadmin-main\Logs\Printer'
            storageRoot    = 'C:\ProgramData\sysadmin-main'
            logPath        = 'C:\ProgramData\sysadmin-main\Logs\Printer\print-queue-20250102.log'
        }
    }

    It 'restarts the service only when stopped by this run and removes spool artifacts including FP temp files' {
        $moduleName = $script:ModuleInfo.ModuleName

        InModuleScope $moduleName {
            param($serviceName, $spoolDirectory, $logDirectory, $storageRoot, $logPath)

            $script:ScriptConfig = @{
                StorageRoot = $storageRoot
            }

            $service = [pscustomobject]@{
                Status = [System.ServiceProcess.ServiceControllerStatus]::Running
            }
            Add-Member -InputObject $service -MemberType ScriptMethod -Name Refresh -Value { } -Force
            Add-Member -InputObject $service -MemberType ScriptMethod -Name WaitForStatus -Value {
                param($Status, $Timeout)
            } -Force

            $splPath = Join-Path $spoolDirectory 'job1.spl'
            $shdPath = Join-Path $spoolDirectory 'job2.shd'
            $fpTmpPath = Join-Path $spoolDirectory 'FP12345.tmp'
            $randomTmpPath = Join-Path $spoolDirectory 'random.tmp'
            $files = @(
                [pscustomobject]@{ FullName = $splPath; Extension = '.spl'; Name = 'job1.spl' },
                [pscustomobject]@{ FullName = $shdPath; Extension = '.shd'; Name = 'job2.shd' },
                [pscustomobject]@{ FullName = $fpTmpPath; Extension = '.tmp'; Name = 'FP12345.tmp' },
                [pscustomobject]@{ FullName = $randomTmpPath; Extension = '.tmp'; Name = 'random.tmp' }
            )

            Mock Resolve-SecureDirectory { $Path }
            Mock Get-UniqueChildPath { $logPath }
            Mock Get-Service { $service }
            Mock Get-ChildItem { $files } -ParameterFilter { $LiteralPath -eq $spoolDirectory -and $File }
            Mock Start-Transcript {}
            Mock Stop-Transcript {}
            Mock Stop-Service {}
            Mock Start-Service {}
            Mock Remove-Item {}

            $invokeParams = @{
                ServiceName    = $serviceName
                SpoolDirectory = $spoolDirectory
                TimeoutSeconds = 30
                LogDirectory   = $logDirectory
                LogFilePrefix  = 'print-queue'
            }
            if ((Get-Command Invoke-ClearPrintQueueLogged).Parameters.ContainsKey('StorageRoot')) {
                $invokeParams.StorageRoot = $storageRoot
            }

            $result = Invoke-ClearPrintQueueLogged @invokeParams

            $result.DeletedFiles | Should -Be 3
            if ($result.PSObject.Properties.Name -contains 'Success') {
                $result.Success | Should -BeTrue
            }

            Assert-MockCalled Start-Transcript -Times 1 -Exactly -Scope It
            Assert-MockCalled Stop-Transcript -Times 1 -Exactly -Scope It
            Assert-MockCalled Stop-Service -Times 1 -Exactly -Scope It
            Assert-MockCalled Start-Service -Times 1 -Exactly -Scope It
            Assert-MockCalled Remove-Item -Times 1 -Exactly -Scope It -ParameterFilter { $LiteralPath -eq $splPath }
            Assert-MockCalled Remove-Item -Times 1 -Exactly -Scope It -ParameterFilter { $LiteralPath -eq $shdPath }
            Assert-MockCalled Remove-Item -Times 1 -Exactly -Scope It -ParameterFilter { $LiteralPath -eq $fpTmpPath }
            Assert-MockCalled Remove-Item -Times 0 -Exactly -Scope It -ParameterFilter { $LiteralPath -eq $randomTmpPath }
        } -Parameters @{
            serviceName    = 'Spooler'
            spoolDirectory = 'C:\Windows\System32\spool\PRINTERS'
            logDirectory   = 'C:\ProgramData\sysadmin-main\Logs\Printer'
            storageRoot    = 'C:\ProgramData\sysadmin-main'
            logPath        = 'C:\ProgramData\sysadmin-main\Logs\Printer\print-queue-20250102.log'
        }
    }
}


