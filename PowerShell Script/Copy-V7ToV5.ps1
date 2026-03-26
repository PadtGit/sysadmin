[CmdletBinding()]
param()

$BasePath = 'C:\Users\Bob\Documents\sysadmin-main\PowerShell Script'
$SourcePath = Join-Path -Path $BasePath -ChildPath 'V7'
$DestinationPath = Join-Path -Path $BasePath -ChildPath 'V5'

function Copy-ScriptTree {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,

        [Parameter(Mandatory = $true)]
        [string]$DestinationPath
    )

    if (-not (Test-Path -LiteralPath $SourcePath -PathType Container)) {
        throw "Source folder not found: $SourcePath"
    }

    if (-not (Test-Path -LiteralPath $DestinationPath -PathType Container)) {
        New-Item -Path $DestinationPath -ItemType Directory -Force | Out-Null
    }

    Get-ChildItem -LiteralPath $SourcePath -Force | ForEach-Object {
        $ItemPath = $_.FullName
        $TargetPath = Join-Path -Path $DestinationPath -ChildPath $_.Name

        Copy-Item -LiteralPath $ItemPath -Destination $TargetPath -Recurse -Force
    }
}

Copy-ScriptTree -SourcePath $SourcePath -DestinationPath $DestinationPath
