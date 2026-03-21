Describe 'V5 logged spool cleanup hardening' {
    . (Resolve-Path (Join-Path $PSScriptRoot '..\..\TestHelpers.ps1')).Path

    It 'writes transcripts under a secured ProgramData root with unique names' {
        $ScriptPath = Join-Path $script:RepoRoot 'PowerShell Script\V5\Printer\restart.SpoolDeleteQV4.ps1'
        $Content = Get-Content -LiteralPath $ScriptPath -Raw

        $Content | Should Match 'CommonApplicationData'
        $Content | Should Match 'sysadmin-main\\Logs\\Printer'
        $Content | Should Match 'New-UniqueChildPath'
        $Content | Should Match 'NoClobber'
        $Content | Should Match 'Set-RestrictedDirectoryAcl'
        $Content | Should Not Match 'C:\\Temp\\print-queue\.log'
    }

    It 'only restarts the service when this invocation stopped it' {
        $ScriptPath = Join-Path $script:RepoRoot 'PowerShell Script\V5\Printer\restart.SpoolDeleteQV4.ps1'
        $Content = Get-Content -LiteralPath $ScriptPath -Raw

        $Content | Should Match '\$ServiceWasStopped = \$false'
        $Content | Should Match '\$ServiceWasStopped = \$true'
        $Content | Should Match 'if \(\$ServiceWasStopped -and \$PSCmdlet\.ShouldProcess\(\$ServiceName, ''Start service''\)\)'
    }
}
