Set-StrictMode -Version 3.0

$script:RepoRoot = Split-Path -Path $PSScriptRoot -Parent

function Invoke-WhatIfScriptObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('pwsh', 'powershell')]
        [string]$Shell,

        [Parameter(Mandatory = $true)]
        [string]$RelativeScriptPath
    )

    $ScriptPath = Join-Path -Path $script:RepoRoot -ChildPath $RelativeScriptPath
    if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
        throw ('Script not found: {0}' -f $ScriptPath)
    }

    $ShellPath = if ($Shell -eq 'powershell') {
        Join-Path -Path $env:SystemRoot -ChildPath 'System32\WindowsPowerShell\v1.0\powershell.exe'
    }
    else {
        (Get-Command -Name 'pwsh.exe' -ErrorAction Stop).Source
    }

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
        }
    }

    [pscustomobject]@{
        OutputLines = $OutputLines
        Json        = $JsonLine
        Object      = $Object
    }
}
