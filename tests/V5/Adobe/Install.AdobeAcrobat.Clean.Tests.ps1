Describe 'V5 Adobe Acrobat refresh hardening' {
    . (Resolve-Path (Join-Path $PSScriptRoot '..\..\TestHelpers.ps1')).Path

    It 'returns a safe preview object with a secured log directory' {
        $Result = Invoke-WhatIfScriptObject -Shell powershell -RelativeScriptPath 'PowerShell Script\V5\Adobe\Install.AdobeAcrobat.Clean.ps1'

        $Result.Object | Should Not BeNullOrEmpty
        $Result.Object.Status | Should Be 'Skipped'
        $Result.Object.Reason | Should Be 'PackagePathNotFound'
        $Result.Object.LogDirectory | Should Match 'sysadmin-main\\Logs\\AdobeAcrobat'
        $Result.Object.LogDirectory | Should Not Match 'C:\\Temp'
    }

    It 'requires signature and publisher validation before running the installer' {
        $ScriptPath = Join-Path $script:RepoRoot 'PowerShell Script\V5\Adobe\Install.AdobeAcrobat.Clean.ps1'
        $Content = Get-Content -LiteralPath $ScriptPath -Raw

        $Content | Should Match 'Get-AuthenticodeSignature'
        $Content | Should Match 'Test-TrustedPublisher'
        $Content | Should Match 'TrustedPublisherPatterns'
        $Content | Should Match 'System32\\msiexec\.exe'
    }
}
