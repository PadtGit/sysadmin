Describe 'V7 Adobe Acrobat refresh hardening' {
    . (Resolve-Path (Join-Path $PSScriptRoot '..\..\TestHelpers.ps1')).Path

    It 'requires signature and publisher validation before running the installer' {
        $ScriptPath = Join-Path $script:RepoRoot 'PowerShell Script\V7\Adobe\Install.AdobeAcrobat.Clean.ps1'
        $Content = Get-Content -LiteralPath $ScriptPath -Raw

        $Content | Should Match '#Requires -RunAsAdministrator'
        $Content | Should Match 'Get-AuthenticodeSignature'
        $Content | Should Match 'Test-TrustedPublisher'
        $Content | Should Match 'TrustedPublisherPatterns'
        $Content | Should Match 'System32\\msiexec\.exe'
    }

    It 'stores logs under a secured ProgramData root' {
        $ScriptPath = Join-Path $script:RepoRoot 'PowerShell Script\V7\Adobe\Install.AdobeAcrobat.Clean.ps1'
        $Content = Get-Content -LiteralPath $ScriptPath -Raw

        $Content | Should Match 'CommonApplicationData'
        $Content | Should Match 'sysadmin-main\\Logs\\AdobeAcrobat'
        $Content | Should Match 'Resolve-SecureDirectory'
        $Content | Should Match 'Set-RestrictedDirectoryAcl'
        $Content | Should Not Match 'C:\\Temp\\AdobeAcrobat'
    }
}
