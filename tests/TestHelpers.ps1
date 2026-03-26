Set-StrictMode -Version 3.0

$env:SYSADMIN_MAIN_REPO_ROOT = Split-Path -Path $PSScriptRoot -Parent

function Global:Get-SysadminMainRepoRoot {
    [CmdletBinding()]
    param()

    return $env:SYSADMIN_MAIN_REPO_ROOT
}

function Global:Import-ScriptModuleForTest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativeScriptPath,

        [string]$ModuleName
    )

    $ScriptPath = Join-Path -Path $env:SYSADMIN_MAIN_REPO_ROOT -ChildPath $RelativeScriptPath
    if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
        throw ('Script not found: {0}' -f $ScriptPath)
    }

    if ([string]::IsNullOrWhiteSpace($ModuleName)) {
        $BaseName = [System.IO.Path]::GetFileNameWithoutExtension($ScriptPath) -replace '[^A-Za-z0-9_]', '_'
        $ModuleName = 'TestModule_{0}_{1}' -f $BaseName, ([guid]::NewGuid().ToString('N'))
    }

    $Tokens = $null
    $ParseErrors = $null
    $Ast = [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$Tokens, [ref]$ParseErrors)
    if ($ParseErrors.Count -gt 0) {
        throw ('Failed to parse script for test import: {0}' -f $ScriptPath)
    }

    $ModuleSource = @(
        foreach ($Statement in $Ast.EndBlock.Statements) {
            if ($Statement -is [System.Management.Automation.Language.TryStatementAst]) {
                continue
            }

            $Statement.Extent.Text
        }
    ) -join ([Environment]::NewLine + [Environment]::NewLine)
    $ModuleSource = $ModuleSource -replace '\[System\.Runtime\.InteropServices\.Marshal\]::ReleaseComObject\(([^)]+)\) \| Out-Null', 'if ($1 -is [System.__ComObject]) { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($1) | Out-Null }'

    $ExistingModule = Get-Module -Name $ModuleName
    if ($null -ne $ExistingModule) {
        Remove-Module -Name $ModuleName -Force
    }

    $Module = New-Module -Name $ModuleName -ScriptBlock ([scriptblock]::Create($ModuleSource)) | Import-Module -Force -PassThru

    [pscustomobject]@{
        ModuleName = $Module.Name
        Module     = $Module
        ScriptPath = $ScriptPath
    }
}

function Global:Invoke-WhatIfScriptObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativeScriptPath
    )

    $ScriptPath = Join-Path -Path $env:SYSADMIN_MAIN_REPO_ROOT -ChildPath $RelativeScriptPath
    if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
        throw ('Script not found: {0}' -f $ScriptPath)
    }

    $ShellPath = Join-Path -Path $env:SystemRoot -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'

    $EscapedScriptPath = $ScriptPath.Replace("'", "''")
    $Invocation = @"
`$result = & '$EscapedScriptPath' -WhatIf
`$result | ConvertTo-Json -Compress -Depth 8
"@

    $OutputLines = @(
        $Invocation |
            & $ShellPath -NoProfile -ExecutionPolicy Bypass -Command - 2>&1 |
            ForEach-Object { $_.ToString() }
    )

    $JsonLine = $OutputLines | Select-Object -Last 1
    $Object = $null

    if (-not [string]::IsNullOrWhiteSpace($JsonLine)) {
        try {
            $Object = $JsonLine | ConvertFrom-Json
        }
        catch {
            Write-Verbose ('Failed to parse WhatIf JSON output for {0}.' -f $ScriptPath)
        }
    }

    [pscustomobject]@{
        OutputLines = $OutputLines
        Json        = $JsonLine
        Object      = $Object
    }
}
