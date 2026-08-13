# Taken with love from @juneb_get_help (https://raw.githubusercontent.com/juneb/PesterTDD/master/Module.Help.Tests.ps1)

# This legacy data-driven suite expects absent help nodes to evaluate to $null.
# Other test files enable strict mode in the shared Pester discovery session.
Set-StrictMode -Off

BeforeDiscovery {

    function global:FilterOutCommonParams {
        param ($Params)
        $commonParams = @(
            'Debug', 'ErrorAction', 'ErrorVariable', 'InformationAction', 'InformationVariable',
            'OutBuffer', 'OutVariable', 'PipelineVariable', 'Verbose', 'WarningAction',
            'WarningVariable', 'Confirm', 'Whatif', 'ProgressAction'
        )
        $params |
            Where-Object { $_ -and $_.PSObject.Properties['Name'] -and $_.Name -notin $commonParams } |
            Sort-Object -Property Name -Unique
    }

    function global:GetHelpParameterNodes {
        param ($Help)

        $parametersProperty = $Help.PSObject.Properties['Parameters']
        if (-not $parametersProperty -or -not $parametersProperty.Value) {
            return @()
        }

        $parameterProperty = $parametersProperty.Value.PSObject.Properties['Parameter']
        if (-not $parameterProperty) {
            return @()
        }

        @($parameterProperty.Value)
    }

    $projectRoot          = Split-Path -Path $PSScriptRoot -Parent
    $moduleName           = 'FreshservicePSU'
    $sourceManifest       = Join-Path -Path $projectRoot -ChildPath "$moduleName/$moduleName.psd1"

    # Get module commands
    # Remove all versions of the module from the session. Pester can't handle multiple versions.
    Get-Module $moduleName | Remove-Module -Force -ErrorAction Ignore
    Import-Module -Name $sourceManifest -Verbose:$false -ErrorAction Stop
    $params = @{
        Module      = (Get-Module $moduleName)
        CommandType = [System.Management.Automation.CommandTypes[]]'Cmdlet, Function' # Not alias
    }
    if ($PSVersionTable.PSVersion.Major -lt 6) {
        $params.CommandType[0] += 'Workflow'
    }
    $Script:commands = Get-Command @params

    ## When testing help, remember that help is cached at the beginning of each session.
    ## To test, restart session.
}

Describe "Test help for <_.Name>" -ForEach $commands {

    BeforeDiscovery {
        # Get command help, parameters, and links
        $Script:command               = $_
        $Script:commandHelp           = Get-Help $command.Name -ErrorAction SilentlyContinue
        $Script:commandParameters     = global:FilterOutCommonParams -Params $command.ParameterSets.Parameters
        $Script:commandParameterNames = @($commandParameters | Select-Object -ExpandProperty Name)
        $Script:helpParameters        = global:FilterOutCommonParams -Params (global:GetHelpParameterNodes -Help $commandHelp)
        $Script:helpParameterNames    = @($helpParameters | Select-Object -ExpandProperty Name)
        $Script:helpLinks             = if ($commandHelp.PSObject.Properties['relatedLinks']) {
            $commandHelp.relatedLinks.navigationLink.uri
        }
        else {
            @()
        }
    }

    BeforeAll {
        # These vars are needed in both discovery and test phases so we need to duplicate them here
        $Script:command                = $_
        $Script:commandName            = $_.Name
        $Script:commandHelp            = Get-Help $command.Name -ErrorAction SilentlyContinue
        $Script:commandParameters      = global:FilterOutCommonParams -Params $command.ParameterSets.Parameters
        $Script:commandParameterNames  = @($commandParameters | Select-Object -ExpandProperty Name)
        $Script:helpParameters         = global:FilterOutCommonParams -Params (global:GetHelpParameterNodes -Help $commandHelp)
        $Script:helpParameterNames     = @($helpParameters | Select-Object -ExpandProperty Name)
    }

    # If help is not found, synopsis in auto-generated help is the syntax diagram
    It 'Help is not auto-generated' {
        $commandHelp.Synopsis | Should -Not -BeLike '*`[`<CommonParameters`>`]*'
    }

    # Should be a description for every function
    It "Has description" {
        $commandHelp.Description | Should -Not -BeNullOrEmpty
    }

    # Should be at least one example
    It "Has example code" {
        ($commandHelp.Examples.Example | Select-Object -First 1).Code | Should -Not -BeNullOrEmpty
    }

    # Should be at least one example description
    It "Has example help" {
        ($commandHelp.Examples.Example.Remarks | Select-Object -First 1).Text | Should -Not -BeNullOrEmpty
    }

    It "Help link <_> is valid" -Tag 'Network' -ForEach $helpLinks {
        (Invoke-WebRequest -Uri $_ -UseBasicParsing).StatusCode | Should -Be '200'
    }

    Context "Parameter <_.Name>" -Foreach $commandParameters {

        BeforeAll {
            $Script:parameter         = $_
            $Script:parameterName     = $parameter.Name
            $Script:parameterHelp     = $commandHelp.parameters.parameter | Where-Object Name -eq $parameterName
            $Script:parameterHelpType = if ($parameterHelp.ParameterValue) { $parameterHelp.ParameterValue.Trim() }
        }

        # Should be a description for every parameter
        It "Has description" {
            $parameterHelp.Description.Text | Should -Not -BeNullOrEmpty
        }

        # Required value in Help should match IsMandatory property of parameter
        It "Has correct [mandatory] value" {
            $codeMandatory = $_.IsMandatory.toString()
            $parameterHelp.Required | Should -Be $codeMandatory
        }

        # Parameter type in help should match code
        It "Has correct parameter type" {
            $parameterHelpType | Should -Be $parameter.ParameterType.Name
        }
    }

    Context "Test <_> help parameter help for <commandName>" -Foreach $helpParameterNames {

        # Shouldn't find extra parameters in help.
        It "finds help parameter in code: <_>" {
            $_ -in $commandParameterNames | Should -Be $true
        }
    }
}
