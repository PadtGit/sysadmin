#Requires -Version 5.1

<#
.SYNOPSIS
    Runs PSScriptAnalyzer against one or more paths and writes JSON, SARIF,
    and plain-text reports.

.DESCRIPTION
    Resolves each target path, validates the settings file via AST, checks the
    PSScriptAnalyzer module version, runs analysis, and writes three artifact
    files: plain-text summary, JSON findings, and SARIF 2.1.0 (consumed by
    GitHub Advanced Security, Azure DevOps, and OpenAI Codex workflows).

    Safe on both Windows and Linux CI runners (PowerShell 5.1 and 7.x).
    Path separators are normalised via Join-Path - no hardcoded \ or /.

.PARAMETER Path
    One or more paths to analyse. Accepts .ps1/.psm1/.psd1 files or
    directories. Defaults to the current directory.

.PARAMETER SettingsPath
    Path to PSScriptAnalyzerSettings.psd1.
    Defaults to PSScriptAnalyzerSettings.psd1 in the same directory as this
    script.

.PARAMETER Recurse
    Scan directories recursively.

.PARAMETER IncludePath
    Wildcard filter - only files whose full path matches are analysed.

.PARAMETER ExcludePath
    Wildcard filter - files whose full path matches are skipped.

.PARAMETER IncludeRule
    Runtime rule whitelist - overrides settings at invocation time.

.PARAMETER ExcludeRule
    Runtime rule blacklist - overrides settings at invocation time.

.PARAMETER CustomRulePath
    One or more paths to custom PSScriptAnalyzer rule modules.

.PARAMETER RecurseCustomRulePath
    Search CustomRulePath directories recursively for rule modules.

.PARAMETER IncludeDefaultRules
    Force-enable built-in default rules (supplements the settings file).

.PARAMETER OutTxtPath
    Path for the plain-text report.
    Defaults to artifacts/validation/psscriptanalyzer.txt under the repo root.

.PARAMETER OutJsonPath
    Path for the JSON findings report.
    Defaults to artifacts/validation/psscriptanalyzer.json under the repo root.

.PARAMETER OutSarifPath
    Path for the SARIF 2.1.0 report.
    Defaults to artifacts/validation/psscriptanalyzer.sarif under the repo root.

.PARAMETER EnableExit
    When set, the script exits with a non-zero code based on ExitCodeMode.
    Without this switch the script returns the results object instead.

.PARAMETER ExitCodeMode
    Controls which findings trigger a non-zero exit (requires -EnableExit).
    AllDiagnostics : exit code = total finding count (max 255).
    ErrorsOnly     : exit code = Error-severity count (max 255). [default]
    AnyError       : exit 1 if any Error-severity finding exists.

.PARAMETER AutoInstallModule
    Install PSScriptAnalyzer automatically if not found.

.PARAMETER RequiredPSScriptAnalyzerVersion
    Required PSScriptAnalyzer module version. Default: 1.25.0.

.PARAMETER PSScriptAnalyzerModulePath
    Explicit path to PSScriptAnalyzer module - use for pinned/offline installs.

.EXAMPLE
    .\Invoke-PSScriptAnalyzer.ps1

.EXAMPLE
    .\Invoke-PSScriptAnalyzer.ps1 -Recurse -EnableExit -ExitCodeMode AnyError

.EXAMPLE
    .\Invoke-PSScriptAnalyzer.ps1 -Path 'PowerShell Script' -EnableExit
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string[]]$Path = @('.'),

    [Parameter()]
    [string]$SettingsPath = '',

    [Parameter()]
    [switch]$Recurse,

    [Parameter()]
    [string[]]$IncludePath,

    [Parameter()]
    [string[]]$ExcludePath,

    [Parameter()]
    [string[]]$IncludeRule,

    [Parameter()]
    [string[]]$ExcludeRule,

    [Parameter()]
    [string[]]$CustomRulePath,

    [Parameter()]
    [switch]$RecurseCustomRulePath,

    [Parameter()]
    [switch]$IncludeDefaultRules,

    [Parameter()]
    [string]$OutTxtPath = '',

    [Parameter()]
    [string]$OutJsonPath = '',

    [Parameter()]
    [string]$OutSarifPath = '',

    [Parameter()]
    [switch]$EnableExit,

    [Parameter()]
    [ValidateSet('AllDiagnostics', 'ErrorsOnly', 'AnyError')]
    [string]$ExitCodeMode = 'ErrorsOnly',

    [Parameter()]
    [switch]$AutoInstallModule,

    [Parameter()]
    [Alias('MinimumPSScriptAnalyzerVersion')]
    [version]$RequiredPSScriptAnalyzerVersion = [version]'1.25.0',

    [Parameter()]
    [string]$PSScriptAnalyzerModulePath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Console helpers
# ---------------------------------------------------------------------------
function Write-Section {
    param([string]$Title)
    Write-Host ''
    Write-Host ('=' * 72) -ForegroundColor DarkGray
    Write-Host "  $Title" -ForegroundColor Cyan
    Write-Host ('=' * 72) -ForegroundColor DarkGray
}

function Write-Finding {
    param([object]$Finding)
    $Colour = switch ($Finding.Severity.ToString()) {
        'Error'       { 'Red' }
        'Warning'     { 'Yellow' }
        'Information' { 'Cyan' }
        default       { 'White' }
    }
    Write-Host (
        '[{0}] {1} ({2}:{3})  {4}' -f
        $Finding.Severity, $Finding.RuleName,
        $Finding.ScriptName, $Finding.Line, $Finding.Message
    ) -ForegroundColor $Colour
}

function Get-AnalyzerFailureDiagnostic {
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string]$Message
    )

    return [pscustomobject]@{
        Message     = $Message
        Extent      = $null
        RuleName    = 'PSScriptAnalyzerInvocationFailure'
        Severity    = 'Error'
        ScriptName  = $FilePath
        ScriptPath  = $FilePath
        Line        = $null
        Column      = $null
    }
}

# ---------------------------------------------------------------------------
# Resolve script root - guard against empty $PSScriptRoot (piped/stdin invoke)
# ---------------------------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($PSScriptRoot)) {
    $ScriptRoot = $PWD.Path
    Write-Warning '$PSScriptRoot is empty - using current working directory as script root.'
}
else {
    $ScriptRoot = $PSScriptRoot
}

$RepoRoot = Split-Path -Path $ScriptRoot -Parent

# ---------------------------------------------------------------------------
# Default output paths - cross-platform via chained Join-Path
# ---------------------------------------------------------------------------
if ([string]::IsNullOrWhiteSpace($SettingsPath)) {
    $SettingsPath = Join-Path -Path $ScriptRoot -ChildPath 'PSScriptAnalyzerSettings.psd1'
}

if ([string]::IsNullOrWhiteSpace($OutTxtPath)) {
    $OutTxtPath = Join-Path -Path $RepoRoot -ChildPath 'artifacts' |
        Join-Path -ChildPath 'validation' |
        Join-Path -ChildPath 'psscriptanalyzer.txt'
}

if ([string]::IsNullOrWhiteSpace($OutJsonPath)) {
    $OutJsonPath = Join-Path -Path $RepoRoot -ChildPath 'artifacts' |
        Join-Path -ChildPath 'validation' |
        Join-Path -ChildPath 'psscriptanalyzer.json'
}

if ([string]::IsNullOrWhiteSpace($OutSarifPath)) {
    $OutSarifPath = Join-Path -Path $RepoRoot -ChildPath 'artifacts' |
        Join-Path -ChildPath 'validation' |
        Join-Path -ChildPath 'psscriptanalyzer.sarif'
}

foreach ($OutPath in @($OutTxtPath, $OutJsonPath, $OutSarifPath)) {
    $OutDir = Split-Path -Path $OutPath -Parent
    if (-not [string]::IsNullOrWhiteSpace($OutDir) -and
        -not (Test-Path -LiteralPath $OutDir -PathType Container)) {
        New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
    }
}

# ---------------------------------------------------------------------------
# AST-based settings parser - safe across PS editions, no execution required
# ---------------------------------------------------------------------------
function ConvertFrom-AstLiteral {
    param(
        [Parameter(Mandatory)]
        [System.Management.Automation.Language.Ast]$Ast
    )
    switch ($Ast.GetType().FullName) {
        'System.Management.Automation.Language.PipelineAst' {
            $Elements = @($Ast.PipelineElements)
            if ($Elements.Count -ne 1) {
                throw "Unsupported pipeline in settings: $($Ast.Extent.Text)"
            }
            return ConvertFrom-AstLiteral $Elements[0]
        }
        'System.Management.Automation.Language.CommandExpressionAst' {
            return ConvertFrom-AstLiteral $Ast.Expression
        }
        'System.Management.Automation.Language.ArrayExpressionAst' {
            return @($Ast.SubExpression.Statements | ForEach-Object {
                ConvertFrom-AstLiteral $_
            })
        }
        'System.Management.Automation.Language.HashtableAst' {
            $Table = @{}
            foreach ($Pair in $Ast.KeyValuePairs) {
                $Table[[string](ConvertFrom-AstLiteral $Pair.Item1)] = ConvertFrom-AstLiteral $Pair.Item2
            }
            return $Table
        }
        'System.Management.Automation.Language.ArrayLiteralAst' {
            return @($Ast.Elements | ForEach-Object { ConvertFrom-AstLiteral $_ })
        }
        'System.Management.Automation.Language.StringConstantExpressionAst' { return $Ast.Value }
        'System.Management.Automation.Language.ConstantExpressionAst'       { return $Ast.Value }
        'System.Management.Automation.Language.VariableExpressionAst' {
            switch ($Ast.VariablePath.UserPath.ToLowerInvariant()) {
                'true'  { return $true }
                'false' { return $false }
                'null'  { return $null }
                default { throw "Unsupported variable in settings: $($Ast.Extent.Text)" }
            }
        }
        default {
            throw "Unsupported AST node in settings: $($Ast.GetType().Name) => $($Ast.Extent.Text)"
        }
    }
}

function Read-AnalyzerSettings {
    param(
        [Parameter(Mandatory)]
        [string]$FilePath
    )
    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
        throw "Settings file not found: $FilePath"
    }
    $Tokens = $null
    $Errors = $null
    $Ast = [System.Management.Automation.Language.Parser]::ParseFile(
        $FilePath, [ref]$Tokens, [ref]$Errors
    )
    if (@($Errors).Count -gt 0) {
        $First = $Errors | Select-Object -First 1
        throw "Settings parse error at $($First.Extent.StartLineNumber):$($First.Extent.StartColumnNumber) - $($First.Message)"
    }
    $HashAst = $Ast.Find(
        { param($Node) $Node -is [System.Management.Automation.Language.HashtableAst] },
        $true
    ) | Select-Object -First 1
    if (-not $HashAst) {
        throw "No hashtable literal found in settings file: $FilePath"
    }
    $Parsed = ConvertFrom-AstLiteral $HashAst
    $ValidKeys = @('CustomRulePath', 'ExcludeRules', 'IncludeDefaultRules',
                   'IncludeRules', 'RecurseCustomRulePath', 'Rules', 'Severity')
    foreach ($Key in @($Parsed.Keys)) {
        if ($ValidKeys -notcontains $Key) {
            throw "Unsupported settings key '$Key'. Valid keys: $($ValidKeys -join ', ')"
        }
    }
    return $Parsed
}

function Normalize-AnalyzerSettings {
    param(
        [Parameter(Mandatory)]
        [hashtable]$SettingsObject
    )

    foreach ($Key in @('Severity', 'IncludeRules', 'ExcludeRules', 'CustomRulePath')) {
        if ($SettingsObject.ContainsKey($Key)) {
            $SettingsObject[$Key] = @($SettingsObject[$Key] | ForEach-Object { [string]$_ })
        }
    }

    foreach ($Key in @('IncludeDefaultRules', 'RecurseCustomRulePath')) {
        if ($SettingsObject.ContainsKey($Key)) {
            $SettingsObject[$Key] = [bool]$SettingsObject[$Key]
        }
    }

    if ($SettingsObject.ContainsKey('Rules') -and $SettingsObject.Rules -is [hashtable]) {
        foreach ($RuleName in @($SettingsObject.Rules.Keys)) {
            $RuleSettings = $SettingsObject.Rules[$RuleName]
            if ($RuleSettings -is [hashtable] -and $RuleSettings.ContainsKey('Enable')) {
                $RuleSettings.Enable = [bool]$RuleSettings.Enable
            }
        }
    }

    return $SettingsObject
}

function Get-CompatibilityRulesMissingTargetProfiles {
    param(
        [Parameter(Mandatory)]
        [hashtable]$SettingsObject
    )

    $CompatibilityRules = @(
        'PSUseCompatibleCmdlets',
        'PSUseCompatibleCommands',
        'PSUseCompatibleSyntax',
        'PSUseCompatibleTypes'
    )
    $MissingRules = [System.Collections.Generic.List[string]]::new()

    if (-not $SettingsObject.ContainsKey('Rules') -or $SettingsObject.Rules -isnot [hashtable]) {
        return $MissingRules
    }

    foreach ($RuleName in $CompatibilityRules) {
        if (-not $SettingsObject.Rules.ContainsKey($RuleName)) {
            continue
        }

        $RuleSettings = $SettingsObject.Rules[$RuleName]
        if ($RuleSettings -isnot [hashtable]) {
            continue
        }

        $IsEnabled = $true
        if ($RuleSettings.ContainsKey('Enable')) {
            $IsEnabled = [bool]$RuleSettings.Enable
        }

        $TargetProfiles = @()
        if ($RuleSettings.ContainsKey('TargetProfiles')) {
            $TargetProfiles = @(
                $RuleSettings.TargetProfiles |
                    Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } |
                    ForEach-Object { [string]$_ }
            )
        }

        if ($IsEnabled -and @($TargetProfiles).Count -eq 0) {
            $MissingRules.Add($RuleName)
        }
    }

    return $MissingRules
}

# ---------------------------------------------------------------------------
# Module check and optional install
# ---------------------------------------------------------------------------
function Import-AnalyzerModule {
    param(
        [version]$RequiredVersion,
        [switch]$AllowInstall,
        [string]$ModulePath
    )
    if (-not [string]::IsNullOrWhiteSpace($ModulePath)) {
        if (-not (Test-Path -LiteralPath $ModulePath)) {
            throw "PSScriptAnalyzer module path not found: $ModulePath"
        }
        $ImportedModule = Import-Module -Name $ModulePath -Force -PassThru -ErrorAction Stop |
            Sort-Object Version -Descending |
            Select-Object -First 1
        if ($ImportedModule.Version -ne $RequiredVersion) {
            throw "PSScriptAnalyzer $($ImportedModule.Version) loaded from module path - required version is $RequiredVersion."
        }
        return
    }
    $Mod = Get-Module -ListAvailable -Name PSScriptAnalyzer |
        Where-Object { $_.Version -eq $RequiredVersion } |
        Select-Object -First 1
    if (-not $Mod) {
        if (-not $AllowInstall) {
            throw "PSScriptAnalyzer $RequiredVersion is not installed. Use -AutoInstallModule to install automatically."
        }
        Write-Host "  Installing PSScriptAnalyzer $RequiredVersion..." -ForegroundColor DarkGray
        Install-Module -Name PSScriptAnalyzer -Repository PSGallery -Scope CurrentUser -RequiredVersion $RequiredVersion -Force
        $Mod = Get-Module -ListAvailable -Name PSScriptAnalyzer |
            Where-Object { $_.Version -eq $RequiredVersion } |
            Select-Object -First 1
    }
    if (-not $Mod) {
        throw "PSScriptAnalyzer $RequiredVersion could not be resolved after installation."
    }
    Import-Module -Name PSScriptAnalyzer -RequiredVersion $RequiredVersion -Force -ErrorAction Stop
}

# ---------------------------------------------------------------------------
# SARIF 2.1.0 builder
# ---------------------------------------------------------------------------
function ConvertTo-Sarif {
    param(
        [Parameter(Mandatory)]
        [object[]]$Diagnostics,
        [Parameter(Mandatory)]
        [string]$ProjectRoot
    )
    $Mod = Get-Module -Name PSScriptAnalyzer |
        Sort-Object Version -Descending |
        Select-Object -First 1
    $Version = $Mod.Version.ToString()

    $RulesMetadata = @()
    $UniqueRules = $Diagnostics |
        Where-Object { $_.RuleName } |
        Select-Object -ExpandProperty RuleName |
        Sort-Object -Unique
    foreach ($RuleId in $UniqueRules) {
        $RulesMetadata += [ordered]@{
            id                   = $RuleId
            name                 = $RuleId
            shortDescription     = @{ text = $RuleId }
            defaultConfiguration = @{ level = 'warning' }
        }
    }

    $SarifResults = @()
    foreach ($D in $Diagnostics) {
        $Level = switch ($D.Severity.ToString()) {
            'Error'       { 'error' }
            'Warning'     { 'warning' }
            'Information' { 'note' }
            'ParseError'  { 'error' }
            default       { 'warning' }
        }
        $Msg = if ($D.Message) { [string]$D.Message } else { [string]$D }
        $Uri = $null
        if ($D.ScriptName) {
            $Full = $null
            try {
                if (Test-Path -LiteralPath $D.ScriptName) {
                    $Full = (Resolve-Path -LiteralPath $D.ScriptName -ErrorAction Stop).Path
                }
            }
            catch {
                $Full = $null
            }

            if ($Full) {
                if ($Full.StartsWith($ProjectRoot)) {
                    $Uri = $Full.Substring($ProjectRoot.Length).TrimStart('\', '/').Replace('\', '/')
                }
                else {
                    $Uri = $Full.Replace('\', '/')
                }
            }
            else {
                $Uri = ([string]$D.ScriptName).Replace('\', '/')
            }
        }
        $Region = @{}
        if ($D.Line   -and [int]$D.Line   -gt 0) { $Region.startLine   = [int]$D.Line }
        if ($D.Column -and [int]$D.Column -gt 0) { $Region.startColumn = [int]$D.Column }

        $Result = [ordered]@{
            ruleId  = $D.RuleName
            level   = $Level
            message = @{ text = $Msg }
        }
        if ($Uri) {
            $Phys = [ordered]@{ artifactLocation = @{ uri = $Uri } }
            if (@($Region.Keys).Count -gt 0) { $Phys.region = $Region }
            $Result.locations = @(@{ physicalLocation = $Phys })
        }
        $SarifResults += $Result
    }

    $RootUri = 'file:///' + $ProjectRoot.Replace('\', '/').TrimEnd('/') + '/'
    return [ordered]@{
        '$schema' = 'https://json.schemastore.org/sarif-2.1.0.json'
        version   = '2.1.0'
        runs      = @(
            @{
                tool = @{
                    driver = [ordered]@{
                        name            = 'PSScriptAnalyzer'
                        semanticVersion = $Version
                        rules           = $RulesMetadata
                    }
                }
                originalUriBaseIds = @{
                    PROJECTROOT = @{ uri = $RootUri }
                }
                results = $SarifResults
            }
        )
    }
}

# ---------------------------------------------------------------------------
# Target file resolver - handles files and directories, wildcard filters
# ---------------------------------------------------------------------------
function Resolve-AnalyzerTargets {
    param(
        [string[]]$InputPaths,
        [switch]$DoRecurse,
        [string[]]$IncludePattern,
        [string[]]$ExcludePattern
    )
    $Extensions = @('.ps1', '.psm1', '.psd1')
    $List = [System.Collections.Generic.List[string]]::new()

    foreach ($P in $InputPaths) {
        if ([string]::IsNullOrWhiteSpace($P)) { continue }
        try {
            $Resolved = Resolve-Path -Path $P -ErrorAction Stop
        }
        catch {
            Write-Warning "Path not found, skipping: $P"
            continue
        }
        foreach ($R in $Resolved) {
            if (Test-Path -LiteralPath $R -PathType Leaf) {
                if ([System.IO.Path]::GetExtension($R) -in $Extensions) {
                    $List.Add([string]$R)
                }
            }
            elseif (Test-Path -LiteralPath $R -PathType Container) {
                $GciParams = @{
                    LiteralPath = [string]$R
                    File        = $true
                    ErrorAction = 'Stop'
                }
                if ($DoRecurse) { $GciParams.Recurse = $true }
                Get-ChildItem @GciParams |
                    Where-Object { $_.Extension -in $Extensions } |
                    ForEach-Object { $List.Add($_.FullName) }
            }
        }
    }

    $Result = $List | Sort-Object -Unique

    if ($IncludePattern) {
        $Result = $Result | Where-Object {
            $FilePath = $_
            foreach ($Pat in $IncludePattern) {
                if ($FilePath -like $Pat) { return $true }
            }
            return $false
        }
    }
    if ($ExcludePattern) {
        $Result = $Result | Where-Object {
            $FilePath = $_
            foreach ($Pat in $ExcludePattern) {
                if ($FilePath -like $Pat) { return $false }
            }
            return $true
        }
    }
    return $Result
}

# ---------------------------------------------------------------------------
# PS version advisory (PSScriptAnalyzer 1.25.0 works best on PS 7.2.11+)
# ---------------------------------------------------------------------------
if ($PSVersionTable.PSEdition -eq 'Core' -and
    $PSVersionTable.PSVersion -lt [version]'7.2.11') {
    Write-Warning 'PowerShell 7.2.11 or newer is recommended for PSScriptAnalyzer 1.25.0.'
}

# ---------------------------------------------------------------------------
# Load module
# ---------------------------------------------------------------------------
Import-AnalyzerModule `
    -RequiredVersion $RequiredPSScriptAnalyzerVersion `
    -AllowInstall:$AutoInstallModule `
    -ModulePath  $PSScriptAnalyzerModulePath

$LoadedModule = Get-Module -Name PSScriptAnalyzer |
    Sort-Object Version -Descending |
    Select-Object -First 1
Write-Host "PSScriptAnalyzer v$($LoadedModule.Version) loaded." -ForegroundColor DarkGray

# ---------------------------------------------------------------------------
# Load and patch settings
# ---------------------------------------------------------------------------
$Settings = $null
if (Test-Path -LiteralPath $SettingsPath -PathType Leaf) {
    $Settings = Normalize-AnalyzerSettings -SettingsObject (Read-AnalyzerSettings -FilePath $SettingsPath)
}
else {
    Write-Warning "Settings file not found: $SettingsPath - falling back to built-in defaults."
}

if ($Settings) {
    if ($CustomRulePath)        { $Settings.CustomRulePath        = $CustomRulePath }
    if ($RecurseCustomRulePath) { $Settings.RecurseCustomRulePath = $true }
    if ($IncludeDefaultRules)   { $Settings.IncludeDefaultRules   = $true }

    $CompatibilityRulesMissingTargetProfiles = @(
        Get-CompatibilityRulesMissingTargetProfiles -SettingsObject $Settings
    )
    if (@($CompatibilityRulesMissingTargetProfiles).Count -gt 0) {
        throw (
            "Compatibility rules enabled without TargetProfiles in '{0}': {1}. " +
            'Add TargetProfiles for those rules or disable them before running analyzer validation.'
        ) -f $SettingsPath, ($CompatibilityRulesMissingTargetProfiles -join ', ')
    }
}

# ---------------------------------------------------------------------------
# Validate rule names against installed module
# ---------------------------------------------------------------------------
try {
    $KnownRules = Get-ScriptAnalyzerRule |
        Select-Object -ExpandProperty RuleName |
        Sort-Object -Unique
    $RuleRefs = [System.Collections.Generic.List[string]]::new()
    if ($Settings -and $Settings.Rules)        { foreach ($K in $Settings.Rules.Keys)        { $RuleRefs.Add($K) } }
    if ($Settings -and $Settings.IncludeRules) { foreach ($R in $Settings.IncludeRules)      { $RuleRefs.Add($R) } }
    if ($Settings -and $Settings.ExcludeRules) { foreach ($R in $Settings.ExcludeRules)      { $RuleRefs.Add($R) } }
    if ($IncludeRule)                          { foreach ($R in $IncludeRule)                 { $RuleRefs.Add($R) } }
    if ($ExcludeRule)                          { foreach ($R in $ExcludeRule)                 { $RuleRefs.Add($R) } }
    $InvalidRules = $RuleRefs |
        Where-Object { $_ -and ($KnownRules -notcontains $_) } |
        Sort-Object -Unique
    if ($InvalidRules) {
        Write-Warning "Unknown rule names detected: $($InvalidRules -join ', ')"
    }
}
catch {
    Write-Warning "Rule name validation skipped: $_"
}

# ---------------------------------------------------------------------------
# Resolve target files
# ---------------------------------------------------------------------------
$DefaultExcludePath = @(
    '*\.git\*',
    '*/.git/*',
    '*\artifacts\*',
    '*/artifacts/*'
)

$EffectiveExcludePath = @($ExcludePath) + $DefaultExcludePath

$TargetFiles = Resolve-AnalyzerTargets `
    -InputPaths      $Path `
    -DoRecurse:      $Recurse `
    -IncludePattern  $IncludePath `
    -ExcludePattern  $EffectiveExcludePath

if (-not $TargetFiles -or @($TargetFiles).Count -eq 0) {
    Write-Host 'No PowerShell files found for analysis.'
    Set-Content -LiteralPath $OutTxtPath -Value 'No PowerShell files found for analysis.' -Encoding UTF8
    if ($EnableExit) { exit 0 }
    return
}

# ---------------------------------------------------------------------------
# Run analysis
# ---------------------------------------------------------------------------
Write-Section 'PSScriptAnalyzer - Running'

$AllResults = [System.Collections.Generic.List[object]]::new()
$UseRuntimeSettingsOverrides = (@($CustomRulePath).Count -gt 0) -or $RecurseCustomRulePath -or $IncludeDefaultRules
$SettingsArgument = $null

if ($Settings) {
    if ($UseRuntimeSettingsOverrides) {
        $SettingsArgument = $Settings
    }
    else {
        $SettingsArgument = $SettingsPath
    }
}

foreach ($File in $TargetFiles) {
    Write-Host "  Scanning: $File" -ForegroundColor DarkGray
    $Splat = @{}
    if ($SettingsArgument) {
        $Splat.Settings = $SettingsArgument
    }
    else {
        $Splat.IncludeDefaultRules = $true
    }
    if ($IncludeRule) { $Splat.IncludeRule = $IncludeRule }
    if ($ExcludeRule) { $Splat.ExcludeRule = $ExcludeRule }

    try {
        $Found = Invoke-ScriptAnalyzer -Path $File @Splat
        foreach ($Item in @($Found)) {
            if ($null -ne $Item) { $AllResults.Add($Item) }
        }
    }
    catch {
        $AnalyzerErrorMessage = "Analyzer error on '$File': $_"
        Write-Warning $AnalyzerErrorMessage
        $AllResults.Add((Get-AnalyzerFailureDiagnostic -FilePath $File -Message $AnalyzerErrorMessage))
    }
}

# ---------------------------------------------------------------------------
# Sort results
# ---------------------------------------------------------------------------
$SeverityOrder = @{ Error = 0; Warning = 1; Information = 2; ParseError = 0 }
$Results = @($AllResults |
    Sort-Object -Property @(
        { $SeverityOrder[$_.Severity.ToString()] },
        'RuleName', 'ScriptName', 'Line'
    ))

$ResultCount      = @($Results).Count
$ErrorCount       = @($Results | Where-Object { $_.Severity -eq 'Error'       }).Count
$WarningCount     = @($Results | Where-Object { $_.Severity -eq 'Warning'     }).Count
$InformationCount = @($Results | Where-Object { $_.Severity -eq 'Information' }).Count

# ---------------------------------------------------------------------------
# Console - summary + findings
# ---------------------------------------------------------------------------
Write-Section 'PSScriptAnalyzer - Summary'
Write-Host ('  {0,-15} {1}' -f 'Error',       $ErrorCount)       -ForegroundColor $(if ($ErrorCount -gt 0)       { 'Red'    } else { 'Green' })
Write-Host ('  {0,-15} {1}' -f 'Warning',     $WarningCount)     -ForegroundColor $(if ($WarningCount -gt 0)     { 'Yellow' } else { 'Green' })
Write-Host ('  {0,-15} {1}' -f 'Information', $InformationCount) -ForegroundColor $(if ($InformationCount -gt 0) { 'Cyan'   } else { 'Green' })
Write-Host ('  {0,-15} {1}' -f 'Total',       $ResultCount)      -ForegroundColor DarkGray

if ($ResultCount -gt 0) {
    Write-Section 'PSScriptAnalyzer - Findings'
    foreach ($Finding in $Results) {
        Write-Finding -Finding $Finding
    }
}
else {
    Write-Host ''
    Write-Host '  No findings. All checks passed.' -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# Write plain-text report
# ---------------------------------------------------------------------------
$Timestamp   = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$ReportLines = [System.Collections.Generic.List[string]]::new()
$ReportLines.Add('PSScriptAnalyzer Report')
$ReportLines.Add("Generated  : $Timestamp")
$ReportLines.Add("Settings   : $(if ($Settings) { $SettingsPath } else { '(built-in defaults)' })")
$ReportLines.Add("Module     : PSScriptAnalyzer v$($LoadedModule.Version)")
$ReportLines.Add("RepoRoot   : $RepoRoot")
$ReportLines.Add('')
$ReportLines.Add('--- Summary ---')
$ReportLines.Add("Error       : $ErrorCount")
$ReportLines.Add("Warning     : $WarningCount")
$ReportLines.Add("Information : $InformationCount")
$ReportLines.Add("Total       : $ResultCount")
$ReportLines.Add('')
$ReportLines.Add('--- Findings ---')
$ReportLines.Add('')
if ($ResultCount -gt 0) {
    $Table = $Results |
        Format-Table -AutoSize Severity, RuleName, ScriptName, Line, Message |
        Out-String
    $ReportLines.Add($Table.TrimEnd())
}
else {
    $ReportLines.Add('No findings.')
}
Set-Content -LiteralPath $OutTxtPath -Value $ReportLines -Encoding UTF8

# ---------------------------------------------------------------------------
# Write JSON report
# ---------------------------------------------------------------------------
ConvertTo-Json -InputObject @($Results) -Depth 8 -Compress |
    Set-Content -LiteralPath $OutJsonPath -Encoding UTF8

# ---------------------------------------------------------------------------
# Write SARIF 2.1.0 report
# ---------------------------------------------------------------------------
$ProjectRoot = (Get-Location).ProviderPath.TrimEnd('\', '/')
if ($ResultCount -gt 0) {
    $SarifObj = ConvertTo-Sarif -Diagnostics @($Results) -ProjectRoot $ProjectRoot
}
else {
    # Emit a valid empty SARIF document
    $SarifObj = [ordered]@{
        '$schema' = 'https://json.schemastore.org/sarif-2.1.0.json'
        version   = '2.1.0'
        runs      = @(@{
            tool    = @{ driver = @{ name = 'PSScriptAnalyzer'; semanticVersion = $LoadedModule.Version.ToString(); rules = @() } }
            results = @()
        })
    }
}
$SarifObj | ConvertTo-Json -Depth 20 |
    Set-Content -Path $OutSarifPath -Encoding UTF8

# ---------------------------------------------------------------------------
# Console - artifact paths
# ---------------------------------------------------------------------------
Write-Host ''
Write-Host "  TXT  : $OutTxtPath"   -ForegroundColor DarkGray
Write-Host "  JSON : $OutJsonPath"  -ForegroundColor DarkGray
Write-Host "  SARIF: $OutSarifPath" -ForegroundColor DarkGray

# ---------------------------------------------------------------------------
# Exit code
# ---------------------------------------------------------------------------
if ($EnableExit) {
    $ExitCode = switch ($ExitCodeMode) {
        'AllDiagnostics' { [Math]::Min($ResultCount, 255) }
        'AnyError'       { if ($ErrorCount -gt 0) { 1 } else { 0 } }
        default          { [Math]::Min($ErrorCount, 255) }   # ErrorsOnly
    }
    if ($ExitCode -ne 0) {
        Write-Host ''
        Write-Host "  Exiting with code $ExitCode (ExitCodeMode = $ExitCodeMode)." -ForegroundColor Red
    }
    exit $ExitCode
}

# Return results object for pipeline / interactive use
$Results

