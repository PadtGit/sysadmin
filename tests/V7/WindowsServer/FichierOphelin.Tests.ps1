Describe 'V7 installer orphan cleanup contract' {
    . (Resolve-Path (Join-Path $PSScriptRoot '..\..\TestHelpers.ps1')).Path

    It 'preserves the structured result contract and collision-safe rename logic' {
        $RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
        $ScriptPath = Join-Path $RepoRoot 'PowerShell Script\V7\WindowsServer\FichierOphelin.ps1'
        $Content = Get-Content -LiteralPath $ScriptPath -Raw

        $Content | Should Match 'BackupFolder'
        $Content | Should Match 'Status'
        $Content | Should Match 'Reason'
        $Content | Should Match 'yyyyMMddHHmmssfff'
        $Content | Should Match 'Quarantine\\InstallerOrphans'
        $Content | Should Match 'Resolve-SecureDirectory'
        $Content | Should Match 'Test-IsReparsePoint'
        $Content | Should Not Match 'C:\\InstallerOrphans'
    }
}
