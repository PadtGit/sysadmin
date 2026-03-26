. (Resolve-Path (Join-Path $PSScriptRoot '..\TestHelpers.ps1')).Path

Describe 'V7 named printer removal behavior' {

    BeforeAll {
        . (Resolve-Path (Join-Path $PSScriptRoot '..\TestHelpers.ps1')).Path
        $script:ModuleInfo = Import-ScriptModuleForTest -RelativeScriptPath 'PowerShell Script\Printer\Deleter.NamePrinter.ps1'
    }

    AfterAll {
        if ($null -ne $script:ModuleInfo) {
            Remove-Module -Name $script:ModuleInfo.ModuleName -Force -ErrorAction SilentlyContinue
        }
    }

    It 'returns a skipped result when the printer name pattern is not configured' {
        $moduleName = $script:ModuleInfo.ModuleName

        InModuleScope $moduleName {
            Mock Get-Printer {}
            Mock Remove-Printer {}

            $result = Invoke-RemovePrinterByName -NamePattern '*NAMEPRINTER*'

            $result.NamePattern | Should -Be '*NAMEPRINTER*'
            $result.Status | Should -Be 'Skipped'
            $result.Reason | Should -Be 'NamePatternNotConfigured'
            $result.PrinterCount | Should -Be 0
            $result.RemovedCount | Should -Be 0

            Assert-MockCalled Get-Printer -Times 0 -Exactly -Scope It
            Assert-MockCalled Remove-Printer -Times 0 -Exactly -Scope It
        }
    }
}


