@{
    IncludeDefaultRules = $true
    Severity = @(
        'Error'
        'Warning'
        'Information'
    )
    IncludeRules = @()
    ExcludeRules = @()
    CustomRulePath = @()
    RecurseCustomRulePath = $false
    Rules = @{
        PSAlignAssignmentStatement = @{
            Enable = $true
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
            Enable = $true
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
            Enable = $true
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
            Enable = $true
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
        PSUseCompatibleCmdlets = @{
            Enable = $true
        }
        PSUseCompatibleCommands = @{
            Enable = $true
        }
        PSUseCompatibleSyntax = @{
            Enable = $true
        }
        PSUseCompatibleTypes = @{
            Enable = $true
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
            Enable = $true
        }
        PSUseConstrainedLanguageMode = @{
            Enable = $true
        }
        PSUseCorrectCasing = @{
            Enable = $true
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
            Enable = $true
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
