@{
    IncludeDefaultRules = $true
    Severity = @(
        'Error'
        'Warning'
        'Information'
    )
    IncludeRules = @()
    ExcludeRules = @(
        'PSAvoidUsingWriteHost'
        'PSAlignAssignmentStatement'
        'PSAvoidLongLines'
        'PSAvoidUsingDoubleQuotesForConstantString'
        'PSReviewUnusedParameter'
        'PSUseApprovedVerbs'
        'PSUseBOMForUnicodeEncodedFile'
        'PSUseConsistentIndentation'
        'PSUseConsistentWhitespace'
        'PSUseConstrainedLanguageMode'
        'PSUseSingularNouns'
    )
    CustomRulePath = @()
    RecurseCustomRulePath = $false
    Rules = @{
        PSAlignAssignmentStatement = @{
            Enable = $false
        }
        PSAvoidAssignmentToAutomaticVariable = @{
            Enable = $true
        }
        PSAvoidDefaultValueForMandatoryParameter = @{
            Enable = $true
        }
        PSAvoidDefaultValueSwitchParameter = @{
            Enable = $true
        }
        PSAvoidExclaimOperator = @{
            Enable = $true
        }
        PSAvoidGlobalAliases = @{
            Enable = $true
        }
        PSAvoidGlobalFunctions = @{
            Enable = $true
        }
        PSAvoidGlobalVars = @{
            Enable = $true
        }
        PSAvoidInvokingEmptyMembers = @{
            Enable = $true
        }
        PSAvoidLongLines = @{
            Enable = $false
        }
        PSAvoidMultipleTypeAttributes = @{
            Enable = $true
        }
        PSAvoidNullOrEmptyHelpMessageAttribute = @{
            Enable = $true
        }
        PSAvoidOverwritingBuiltInCmdlets = @{
            Enable = $true
        }
        PSAvoidReservedWordsAsFunctionNames = @{
            Enable = $true
        }
        PSAvoidSemicolonsAsLineTerminators = @{
            Enable = $true
        }
        PSAvoidShouldContinueWithoutForce = @{
            Enable = $true
        }
        PSAvoidTrailingWhitespace = @{
            Enable = $true
        }
        PSAvoidUsingAllowUnencryptedAuthentication = @{
            Enable = $true
        }
        PSAvoidUsingBrokenHashAlgorithms = @{
            Enable = $true
        }
        PSAvoidUsingCmdletAliases = @{
            Enable = $true
        }
        PSAvoidUsingComputerNameHardcoded = @{
            Enable = $true
        }
        PSAvoidUsingConvertToSecureStringWithPlainText = @{
            Enable = $true
        }
        PSAvoidUsingDeprecatedManifestFields = @{
            Enable = $true
        }
        PSAvoidUsingDoubleQuotesForConstantString = @{
            Enable = $false
        }
        PSAvoidUsingEmptyCatchBlock = @{
            Enable = $true
        }
        PSAvoidUsingInvokeExpression = @{
            Enable = $true
        }
        PSAvoidUsingPlainTextForPassword = @{
            Enable = $true
        }
        PSAvoidUsingPositionalParameters = @{
            Enable = $true
        }
        PSAvoidUsingUsernameAndPasswordParams = @{
            Enable = $true
        }
        PSAvoidUsingWMICmdlet = @{
            Enable = $true
        }
        PSAvoidUsingWriteHost = @{
            Enable = $true
        }
        PSDSCDscExamplesPresent = @{
            Enable = $true
        }
        PSDSCDscTestsPresent = @{
            Enable = $true
        }
        PSDSCReturnCorrectTypesForDSCFunctions = @{
            Enable = $true
        }
        PSDSCStandardDSCFunctionsInResource = @{
            Enable = $true
        }
        PSDSCUseIdenticalMandatoryParametersForDSC = @{
            Enable = $true
        }
        PSDSCUseIdenticalParametersForDSC = @{
            Enable = $true
        }
        PSDSCUseVerboseMessageInDSCResource = @{
            Enable = $true
        }
        PSMisleadingBacktick = @{
            Enable = $true
        }
        PSMissingModuleManifestField = @{
            Enable = $true
        }
        PSPlaceCloseBrace = @{
            Enable = $true
        }
        PSPlaceOpenBrace = @{
            Enable = $true
        }
        PSPossibleIncorrectComparisonWithNull = @{
            Enable = $true
        }
        PSPossibleIncorrectUsageOfAssignmentOperator = @{
            Enable = $true
        }
        PSPossibleIncorrectUsageOfRedirectionOperator = @{
            Enable = $true
        }
        PSProvideCommentHelp = @{
            Enable = $true
        }
        PSReservedCmdletChar = @{
            Enable = $true
        }
        PSReservedParams = @{
            Enable = $true
        }
        PSReviewUnusedParameter = @{
            Enable = $false
        }
        PSShouldProcess = @{
            Enable = $true
        }
        PSUseApprovedVerbs = @{
            Enable = $true
        }
        PSUseBOMForUnicodeEncodedFile = @{
            Enable = $true
        }
        PSUseCmdletCorrectly = @{
            Enable = $true
        }
        # Keep compatibility rules disabled during the runtime-branch split so
        # the branch preserves the existing analyzer baseline while the
        # flattened single-runtime layout settles.
        PSUseCompatibleCmdlets = @{
            Enable = $false
        }
        PSUseCompatibleCommands = @{
            Enable = $false
        }
        PSUseCompatibleSyntax = @{
            Enable = $false
        }
        PSUseCompatibleTypes = @{
            Enable = $false
        }
        PSUseConsistentIndentation = @{
            Enable = $true
        }
        PSUseConsistentParameterSetName = @{
            Enable = $true
        }
        PSUseConsistentParametersKind = @{
            Enable = $true
        }
        PSUseConsistentWhitespace = @{
            Enable = $false
        }
        PSUseConstrainedLanguageMode = @{
            Enable = $false
        }
        # PSScriptAnalyzer 1.25.0 can throw NullReferenceException in this
        # repo when PSUseCorrectCasing inspects some scripts, so keep the
        # rule disabled until the pinned analyzer version changes.
        PSUseCorrectCasing = @{
            Enable = $false
        }
        PSUseDeclaredVarsMoreThanAssignments = @{
            Enable = $true
        }
        PSUseLiteralInitializerForHashtable = @{
            Enable = $true
        }
        PSUseOutputTypeCorrectly = @{
            Enable = $true
        }
        PSUseProcessBlockForPipelineCommand = @{
            Enable = $true
        }
        PSUsePSCredentialType = @{
            Enable = $true
        }
        PSUseShouldProcessForStateChangingFunctions = @{
            Enable = $true
        }
        PSUseSingleValueFromPipelineParameter = @{
            Enable = $true
        }
        PSUseSingularNouns = @{
            Enable = $false
        }
        PSUseSupportsShouldProcess = @{
            Enable = $true
        }
        PSUseToExportFieldsInManifest = @{
            Enable = $true
        }
        PSUseUsingScopeModifierInNewRunspaces = @{
            Enable = $true
        }
        PSUseUTF8EncodingForHelpFile = @{
            Enable = $true
        }
    }
}
