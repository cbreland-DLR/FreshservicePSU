<#
.SYNOPSIS
    Unit tests for Resolve-FsuCredential (ARCHITECTURE.md §8).
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repoRoot '0.1.6/Private/Errors/New-FsuErrorRecord.ps1')
    . (Join-Path $repoRoot '0.1.6/Private/Configuration/Test-FsuConfiguration.ps1')
    . (Join-Path $repoRoot '0.1.6/Private/Execution/Get-FsuSecret.ps1')
    . (Join-Path $repoRoot '0.1.6/Private/Execution/Resolve-FsuCredential.ps1')
    . (Join-Path $PSScriptRoot 'FsuIdentityFixtures.ps1')

    $script:aliceKey = 'alice-personal-key-DO-NOT-LEAK-c1'
    $script:systemKey = 'system-key-DO-NOT-LEAK-c2'

    function New-FsuTestPrincipal {
        [System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Test fixture builder; no system state is changed.')]
        param(
            [string]$PrincipalId = 'entra:11111111-1111-1111-1111-111111111111:aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
            [string]$ExecutionType = 'Interactive',
            [string]$AuthenticationType = 'SAML',
            [string]$UserPrincipalName = 'alice@contoso.com'
        )

        [PSCustomObject]@{
            PSTypeName = 'Freshservice.ExecutionPrincipal'
            PrincipalId = $PrincipalId
            UserPrincipalName = $UserPrincipalName
            ExecutionType = $ExecutionType
            AuthenticationType = $AuthenticationType
        }
    }

    function New-FsuNamedSecretResolver {
        [System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Test fixture builder; no system state is changed.')]
        [System.Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'Test fixture builds synthetic secrets that are never a real credential.')]
        param()

        $tracker = [pscustomobject]@{ LastName = $null }
        $store = @{
            'FreshService.Alice.Prod' = $script:aliceKey
            'FreshService.System.Prod' = $script:systemKey
            'FreshService.System.Dev' = $script:systemKey
        }
        $resolver = {
            param($Name)
            $tracker.LastName = $Name
            if ($Name -eq 'FreshService.Broken.Prod') {
                throw 'vault miss'
            }
            if ($store.ContainsKey($Name)) {
                return ConvertTo-SecureString -String $store[$Name] -AsPlainText -Force
            }
            throw "unexpected secret name $Name"
        }.GetNewClosure()

        return [pscustomobject]@{
            Resolver = $resolver
            Tracker = $tracker
        }
    }
}

Describe 'Resolve-FsuCredential: selection policy' {

    BeforeEach {
        $script:configuration = Test-FsuConfiguration -Config (New-FsuValidConfigHashtable)
        $script:secretProbe = New-FsuNamedSecretResolver
        $script:resolver = $script:secretProbe.Resolver
    }

    It 'selects the personal secret when an interactive caller has a mapping' {
        $resolved = Resolve-FsuCredential -Principal (New-FsuTestPrincipal) -Configuration $configuration -SecretResolver $resolver
        $resolved.PSObject.TypeNames | Should -Contain 'Freshservice.ResolvedCredential'
        $resolved.CredentialType | Should -Be 'User'
        $resolved.SecretName | Should -Be 'FreshService.Alice.Prod'
        $resolved.UsedFallback | Should -BeFalse
        $script:secretProbe.Tracker.LastName | Should -Be 'FreshService.Alice.Prod'
    }

    It 'uses the system secret with UsedFallback when the caller has no mapping and fallback is allowed' {
        $principal = New-FsuTestPrincipal -PrincipalId 'entra:11111111-1111-1111-1111-111111111111:bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
        $resolved = Resolve-FsuCredential -Principal $principal -Configuration $configuration -SecretResolver $resolver
        $resolved.CredentialType | Should -Be 'System'
        $resolved.SecretName | Should -Be 'FreshService.System.Prod'
        $resolved.UsedFallback | Should -BeTrue
    }

    It 'denies an unmapped interactive caller when fallback is not allowed' {
        $config = Test-FsuConfiguration -Config (New-FsuValidConfigHashtable -AllowSystemFallback $false)
        $principal = New-FsuTestPrincipal -PrincipalId 'entra:11111111-1111-1111-1111-111111111111:bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
        { Resolve-FsuCredential -Principal $principal -Configuration $config -SecretResolver $resolver } |
            Should -Throw '*fallback is not allowed*'
        $script:secretProbe.Tracker.LastName | Should -BeNullOrEmpty
    }

    It 'does not fall back when a mapped personal secret cannot be loaded' {
        $configHash = New-FsuValidConfigHashtable
        $configHash.Users['entra:11111111-1111-1111-1111-111111111111:aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'] = 'FreshService.Broken.Prod'
        $config = Test-FsuConfiguration -Config $configHash
        { Resolve-FsuCredential -Principal (New-FsuTestPrincipal) -Configuration $config -SecretResolver $resolver } |
            Should -Throw '*could not be loaded*'
        $script:secretProbe.Tracker.LastName | Should -Be 'FreshService.Broken.Prod'
    }

    It 'uses the default system secret for scheduled execution without treating it as fallback' {
        $principal = New-FsuTestPrincipal -PrincipalId 'system' -ExecutionType System -AuthenticationType System -UserPrincipalName 'schedule-account'
        $resolved = Resolve-FsuCredential -Principal $principal -Configuration $configuration -SecretResolver $resolver
        $resolved.CredentialType | Should -Be 'System'
        $resolved.SecretName | Should -Be 'FreshService.System.Prod'
        $resolved.UsedFallback | Should -BeFalse
        $script:secretProbe.Tracker.LastName | Should -Be 'FreshService.System.Prod'
    }

    It 'looks up user mappings case-insensitively' {
        $principal = New-FsuTestPrincipal -PrincipalId 'ENTRA:11111111-1111-1111-1111-111111111111:AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA'
        $resolved = Resolve-FsuCredential -Principal $principal -Configuration $configuration -SecretResolver $resolver
        $resolved.CredentialType | Should -Be 'User'
        $resolved.SecretName | Should -Be 'FreshService.Alice.Prod'
    }
}

Describe 'Resolve-FsuCredential: stage isolation and redaction' {

    It 'refuses a Prod configuration that maps to a Dev secret name' {
        $configHash = New-FsuValidConfigHashtable -Stage Prod
        $configHash.Users['entra:11111111-1111-1111-1111-111111111111:aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'] = 'FreshService.Alice.Dev'
        $config = Test-FsuConfiguration -Config $configHash
        $resolver = { param($Name) throw "resolver invoked for $Name" }
        { Resolve-FsuCredential -Principal (New-FsuTestPrincipal) -Configuration $config -SecretResolver $resolver } |
            Should -Throw '*not valid for the configured stage*'
    }

    It 'refuses a Dev configuration whose default secret is labeled Prod' {
        $configHash = New-FsuValidConfigHashtable -Stage Dev
        $configHash.DefaultSecret = 'FreshService.System.Prod'
        $config = Test-FsuConfiguration -Config $configHash
        $principal = New-FsuTestPrincipal -PrincipalId 'system' -ExecutionType System -AuthenticationType System
        $resolver = { param($Name) throw "resolver invoked for $Name" }
        { Resolve-FsuCredential -Principal $principal -Configuration $config -SecretResolver $resolver } |
            Should -Throw '*not valid for the configured stage*'
    }

    It 'refuses a Dev configuration whose default secret uses a hyphen-separated Prod label' {
        $configHash = New-FsuValidConfigHashtable -Stage Dev
        $configHash.DefaultSecret = 'freshservice-prod-key'
        $config = Test-FsuConfiguration -Config $configHash
        $principal = New-FsuTestPrincipal -PrincipalId 'system' -ExecutionType System -AuthenticationType System
        $resolver = { param($Name) throw "resolver invoked for $Name" }
        { Resolve-FsuCredential -Principal $principal -Configuration $config -SecretResolver $resolver } |
            Should -Throw '*not valid for the configured stage*'
    }

    It 'refuses a Dev configuration whose default secret uses an uppercase dotted Prod label' {
        $configHash = New-FsuValidConfigHashtable -Stage Dev
        $configHash.DefaultSecret = 'Freshservice.PROD.Key'
        $config = Test-FsuConfiguration -Config $configHash
        $principal = New-FsuTestPrincipal -PrincipalId 'system' -ExecutionType System -AuthenticationType System
        $resolver = { param($Name) throw "resolver invoked for $Name" }
        { Resolve-FsuCredential -Principal $principal -Configuration $config -SecretResolver $resolver } |
            Should -Throw '*not valid for the configured stage*'
    }

    It 'refuses a Dev configuration whose default secret uses a camelCase Prod label' {
        $configHash = New-FsuValidConfigHashtable -Stage Dev
        $configHash.DefaultSecret = 'fsProdKey'
        $config = Test-FsuConfiguration -Config $configHash
        $principal = New-FsuTestPrincipal -PrincipalId 'system' -ExecutionType System -AuthenticationType System
        $resolver = { param($Name) throw "resolver invoked for $Name" }
        { Resolve-FsuCredential -Principal $principal -Configuration $config -SecretResolver $resolver } |
            Should -Throw '*not valid for the configured stage*'
    }

    It 'allows an unlabeled default secret name regardless of stage' {
        $configHash = New-FsuValidConfigHashtable -Stage Dev
        $configHash.DefaultSecret = 'fsSystemKey'
        $config = Test-FsuConfiguration -Config $configHash
        $principal = New-FsuTestPrincipal -PrincipalId 'system' -ExecutionType System -AuthenticationType System
        $resolver = (New-FsuNamedSecretResolver).Resolver
        # 'fsSystemKey' is not one of the resolver's known names, so reaching
        # a LoadFailed error (rather than a stage-mismatch error) proves the
        # unlabeled name passed the stage-affinity guard and the resolver
        # was actually invoked.
        { Resolve-FsuCredential -Principal $principal -Configuration $config -SecretResolver $resolver } | Should -Throw '*could not be loaded*'
    }

    It 'does not include the secret name or secret value in a load-failure message' {
        $configHash = New-FsuValidConfigHashtable
        $configHash.Users['entra:11111111-1111-1111-1111-111111111111:aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'] = 'FreshService.Broken.Prod'
        $config = Test-FsuConfiguration -Config $configHash
        $resolver = (New-FsuNamedSecretResolver).Resolver
        $caught = $null
        try {
            Resolve-FsuCredential -Principal (New-FsuTestPrincipal) -Configuration $config -SecretResolver $resolver
        } catch {
            $caught = $_
        }
        $caught | Should -Not -BeNullOrEmpty
        $text = $caught | Out-String
        $text | Should -Not -Match 'FreshService.Broken.Prod'
        $text | Should -Not -Match ([regex]::Escape($aliceKey))
        $text | Should -Not -Match ([regex]::Escape($systemKey))
        $text | Should -Not -Match 'vault miss'
    }
}

Describe 'Resolve-FsuCredential: app-forwarded acting secret (delegated per-user)' {

    BeforeEach {
        $script:configuration = Test-FsuConfiguration -Config (New-FsuValidConfigHashtable)
        $script:secretProbe = New-FsuNamedSecretResolver
        $script:resolver = $script:secretProbe.Resolver
    }

    It 'uses a forwarded acting secret on the system path as a delegated credential' {
        $principal = New-FsuTestPrincipal -PrincipalId 'system' -ExecutionType System -AuthenticationType System -UserPrincipalName 'drjob'
        $resolved = Resolve-FsuCredential -Principal $principal -Configuration $configuration -SecretResolver $resolver -ActingSecretName 'FreshService.Alice.Prod'
        $resolved.CredentialType | Should -Be 'DelegatedUser'
        $resolved.SecretName | Should -Be 'FreshService.Alice.Prod'
        $resolved.UsedFallback | Should -BeFalse
        $script:secretProbe.Tracker.LastName | Should -Be 'FreshService.Alice.Prod'
    }

    It 'ignores a forwarded acting secret for an interactive caller (validated identity wins)' {
        # Alice is mapped in Users to FreshService.Alice.Prod; forwarding a
        # different secret must NOT override her real interactive mapping.
        $resolved = Resolve-FsuCredential -Principal (New-FsuTestPrincipal) -Configuration $configuration -SecretResolver $resolver -ActingSecretName 'FreshService.System.Prod'
        $resolved.CredentialType | Should -Be 'User'
        $resolved.SecretName | Should -Be 'FreshService.Alice.Prod'
    }

    It 'still enforces stage affinity on a forwarded acting secret' {
        $principal = New-FsuTestPrincipal -PrincipalId 'system' -ExecutionType System -AuthenticationType System
        # Prod config + a Dev-labeled acting secret must be rejected before the resolver runs.
        { Resolve-FsuCredential -Principal $principal -Configuration $configuration -SecretResolver $resolver -ActingSecretName 'FreshService.Alice.Dev' } |
            Should -Throw '*not valid for the configured stage*'
        $script:secretProbe.Tracker.LastName | Should -BeNullOrEmpty
    }
}
