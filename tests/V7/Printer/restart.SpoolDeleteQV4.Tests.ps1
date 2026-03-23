. (Resolve-Path (Join-Path $PSScriptRoot '..\..\TestHelpers.ps1')).Path

Describe 'V7 logged spool cleanup behavior' {

    BeforeAll {
        . (Resolve-Path (Join-Path $PSScriptRoot '..\..\TestHelpers.ps1')).Path
        $script:ModuleInfo = Import-ScriptModuleForTest -RelativeScriptPath 'PowerShell Script\V7\Printer\restart.SpoolDeleteQV4.ps1'
    }

    AfterAll {
        if ($null -ne $script:ModuleInfo) {
            Remove-Module -Name $script:ModuleInfo.ModuleName -Force -ErrorAction SilentlyContinue
        }
    }

    It 'resolves a secure log path and suppresses transcript, service, and file mutations during WhatIf preview' {
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
            Mock New-UniqueChildPath { $logPath }
            Mock Get-Service { $service }
            Mock Get-ChildItem { @($spoolFile) } -ParameterFilter { $LiteralPath -eq $spoolDirectory -and $File }
            Mock Start-Transcript {}
            Mock Stop-Transcript {}
            Mock Stop-Service {}
            Mock Start-Service {}
            Mock Remove-Item {}

            $result = Invoke-ClearPrintQueueLogged `
                -ServiceName $serviceName `
                -SpoolDirectory $spoolDirectory `
                -TimeoutSeconds 30 `
                -LogDirectory $logDirectory `
                -LogFilePrefix 'print-queue' `
                -WhatIf

            $result.LogPath | Should -Be $logPath
            $result.DeletedFiles | Should -Be 0
            $result.ServiceWasUp | Should -BeTrue

            Assert-MockCalled Resolve-SecureDirectory -Times 1 -Exactly -Scope It -ParameterFilter {
                $Path -eq $logDirectory -and $AllowedRoots[0] -eq $storageRoot
            }
            Assert-MockCalled New-UniqueChildPath -Times 1 -Exactly -Scope It -ParameterFilter {
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
            Mock New-UniqueChildPath { $logPath }
            Mock Get-Service { $service }
            Mock Get-ChildItem { @() } -ParameterFilter { $LiteralPath -eq $spoolDirectory -and $File }
            Mock Start-Transcript {}
            Mock Stop-Transcript {}
            Mock Stop-Service {}
            Mock Start-Service {}
            Mock Remove-Item {}

            $result = Invoke-ClearPrintQueueLogged `
                -ServiceName $serviceName `
                -SpoolDirectory $spoolDirectory `
                -TimeoutSeconds 30 `
                -LogDirectory $logDirectory `
                -LogFilePrefix 'print-queue'

            $result.ServiceWasUp | Should -BeFalse
            $result.DeletedFiles | Should -Be 0

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
}
