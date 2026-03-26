. (Resolve-Path (Join-Path $PSScriptRoot '..\TestHelpers.ps1')).Path

Describe 'Invoke-PSScriptAnalyzer helper' {

    BeforeAll {
        $script:RepoRoot = Get-SysadminMainRepoRoot
        $script:ToolPath = Join-Path $script:RepoRoot 'tools\Invoke-PSScriptAnalyzer.ps1'
        $script:SettingsPath = Join-Path $script:RepoRoot 'tools\PSScriptAnalyzerSettings.psd1'
        $script:PwshPath = (Get-Command -Name 'pwsh.exe' -ErrorAction Stop).Source
    }

    It 'fails validation when analyzer invocation crashes and records the failure in JSON output' {
        $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $tempRoot -Force

        try {
            $sampleScriptPath = Join-Path $tempRoot 'Sample.ps1'
            $ruleModulePath = Join-Path $tempRoot 'ThrowingRule.psm1'
            $txtPath = Join-Path $tempRoot 'psscriptanalyzer.txt'
            $jsonPath = Join-Path $tempRoot 'psscriptanalyzer.json'
            $sarifPath = Join-Path $tempRoot 'psscriptanalyzer.sarif'

            Set-Content -LiteralPath $sampleScriptPath -Encoding UTF8 -Value "Write-Output 'hi'"
            Set-Content -LiteralPath $ruleModulePath -Encoding UTF8 -Value @'
function Measure-ThrowingRule {
    [CmdletBinding()]
    param(
        [System.Management.Automation.Language.ScriptBlockAst]$ScriptBlockAst,
        [string]$FileName
    )

    throw 'Synthetic analyzer failure'
}
'@

            $outputLines = @(
                & $script:PwshPath `
                    -NoProfile `
                    -ExecutionPolicy Bypass `
                    -File $script:ToolPath `
                    -Path $sampleScriptPath `
                    -SettingsPath $script:SettingsPath `
                    -CustomRulePath $ruleModulePath `
                    -IncludeRule 'Measure-ThrowingRule' `
                    -OutTxtPath $txtPath `
                    -OutJsonPath $jsonPath `
                    -OutSarifPath $sarifPath `
                    -EnableExit `
                    -ExitCodeMode AnyError 2>&1 |
                    ForEach-Object { $_.ToString() }
            )
            $exitCode = $LASTEXITCODE

            $exitCode | Should -Be 1
            ($outputLines -join [Environment]::NewLine) | Should -Match 'Analyzer error on'

            $jsonText = Get-Content -LiteralPath $jsonPath -Raw
            $diagnostics = $jsonText | ConvertFrom-Json

            @($diagnostics).Count | Should -Be 1
            $diagnostics[0].RuleName | Should -Be 'PSScriptAnalyzerInvocationFailure'
            $diagnostics[0].Severity | Should -Be 'Error'
            $diagnostics[0].Message | Should -Match 'Synthetic analyzer failure'
        }
        finally {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'overwrites the JSON artifact with an empty array when no findings are returned' {
        $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $tempRoot -Force

        try {
            $sampleScriptPath = Join-Path $tempRoot 'Clean.ps1'
            $txtPath = Join-Path $tempRoot 'psscriptanalyzer.txt'
            $jsonPath = Join-Path $tempRoot 'psscriptanalyzer.json'
            $sarifPath = Join-Path $tempRoot 'psscriptanalyzer.sarif'

            Set-Content -LiteralPath $sampleScriptPath -Encoding UTF8 -Value "Write-Output 'clean'"
            Set-Content -LiteralPath $jsonPath -Encoding UTF8 -Value '[{"RuleName":"StaleFinding"}]'

            $outputLines = @(
                & $script:PwshPath `
                    -NoProfile `
                    -ExecutionPolicy Bypass `
                    -File $script:ToolPath `
                    -Path $sampleScriptPath `
                    -SettingsPath $script:SettingsPath `
                    -OutTxtPath $txtPath `
                    -OutJsonPath $jsonPath `
                    -OutSarifPath $sarifPath 2>&1 |
                    ForEach-Object { $_.ToString() }
            )
            $exitCode = $LASTEXITCODE

            $exitCode | Should -Be 0
            ($outputLines -join [Environment]::NewLine) | Should -Match 'No findings\. All checks passed\.'
            ((Get-Content -LiteralPath $jsonPath -Raw).Trim()) | Should -Be '[]'
        }
        finally {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It 'does not surface analyzer invocation failures for the previously crashing repo files' {
        $tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ([guid]::NewGuid().ToString('N'))
        $null = New-Item -ItemType Directory -Path $tempRoot -Force

        try {
            $txtPath = Join-Path $tempRoot 'psscriptanalyzer.txt'
            $jsonPath = Join-Path $tempRoot 'psscriptanalyzer.json'
            $sarifPath = Join-Path $tempRoot 'psscriptanalyzer.sarif'
            $targetPaths = @(
                Join-Path $script:RepoRoot 'PowerShell Script\Printer\Restart.spool.delete.printerQ.ps1'
                Join-Path $script:RepoRoot 'PowerShell Script\windows-maintenance\Reset.Network.RebootPC.ps1'
            )
            $escapedTargetPaths = @(
                foreach ($targetPath in $targetPaths) {
                    "'{0}'" -f $targetPath.Replace("'", "''")
                }
            ) -join ', '
            $invocation = @"
`$paths = @($escapedTargetPaths)
& '$($script:ToolPath.Replace("'", "''"))' -Path `$paths -SettingsPath '$($script:SettingsPath.Replace("'", "''"))' -OutTxtPath '$($txtPath.Replace("'", "''"))' -OutJsonPath '$($jsonPath.Replace("'", "''"))' -OutSarifPath '$($sarifPath.Replace("'", "''"))' -EnableExit -ExitCodeMode AnyError
"@

            $outputLines = @(
                $invocation |
                    & $script:PwshPath `
                        -NoProfile `
                        -ExecutionPolicy Bypass `
                        -Command - 2>&1 |
                    ForEach-Object { $_.ToString() }
            )
            $exitCode = $LASTEXITCODE

            $exitCode | Should -Be 0
            ($outputLines -join [Environment]::NewLine) | Should -Not -Match 'Analyzer error on'

            $jsonText = Get-Content -LiteralPath $jsonPath -Raw
            $diagnostics = @($jsonText | ConvertFrom-Json)

            ($diagnostics | Where-Object { $_.RuleName -eq 'PSScriptAnalyzerInvocationFailure' }).Count | Should -Be 0
        }
        finally {
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
