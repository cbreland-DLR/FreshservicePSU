<#
.SYNOPSIS
    Unit tests for Get-FsuExecutionContext (ARCHITECTURE.md §9).
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repoRoot '0.1.6/Private/Errors/New-FsuErrorRecord.ps1')
    . (Join-Path $repoRoot '0.1.6/Private/Configuration/Test-FsuConfiguration.ps1')
    . (Join-Path $repoRoot '0.1.6/Private/Execution/New-FsuRetryPolicy.ps1')
    . (Join-Path $repoRoot '0.1.6/Private/Execution/Get-FsuSecret.ps1')
    . (Join-Path $repoRoot '0.1.6/Private/Execution/Resolve-FsuCredential.ps1')
    . (Join-Path $repoRoot '0.1.6/Private/Hosts/PowerShellUniversal/Get-FsuCallerVariable.ps1')
    . (Join-Path $repoRoot '0.1.6/Private/Hosts/PowerShellUniversal/Get-FsuHostInvocation.ps1')
    . (Join-Path $repoRoot '0.1.6/Private/Hosts/PowerShellUniversal/ConvertTo-FsuExecutionPrincipal.ps1')
    . (Join-Path $repoRoot '0.1.6/Private/Execution/Get-FsuExecutionContext.ps1')
    . (Join-Path $PSScriptRoot 'FsuIdentityFixtures.ps1')

    $script:plaintext = 'context-api-key-DO-NOT-LEAK-aa19'
}

Describe 'Get-FsuExecutionContext: success path' {

    It 'returns an immutable-in-practice context for an interactive SAML caller' {
        $resolver = New-FsuTestSecretResolver -Plaintext $plaintext
        $context = Get-FsuExecutionContext `
            -Config (New-FsuValidConfigHashtable) `
            -HostInvocation (New-FsuTestHostInvocation -Surface Api -ClaimsPrincipal (New-FsuSamlClaimsPrincipal)) `
            -SecretResolver $resolver `
            -CorrelationId 'corr-context-1'

        $context.PSObject.TypeNames | Should -Contain 'Freshservice.Context'
        $context.Stage | Should -Be 'Prod'
        $context.Tenant | Should -Be 'acme'
        $context.BaseUri | Should -Be 'https://acme.freshservice.com/api/v2/'
        $context.CorrelationId | Should -Be 'corr-context-1'
        $context.Principal.PrincipalId | Should -Be 'entra:11111111-1111-1111-1111-111111111111:aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
        $context.Principal.AuthenticationType | Should -Be 'SAML'
        $context.Credential.CredentialType | Should -Be 'User'
        $context.RetryPolicy.Mode | Should -Be 'Interactive'
        $context.RetryPolicy.TotalBudgetSeconds | Should -Be 20.0
        $context.Credential.Secret | Should -BeOfType [securestring]
    }

    It 'uses the noninteractive retry budget for scheduled execution' {
        $resolver = New-FsuTestSecretResolver -Plaintext $plaintext
        $context = Get-FsuExecutionContext `
            -Config (New-FsuValidConfigHashtable) `
            -HostInvocation (New-FsuTestHostInvocation -Surface Schedule -JobIdentityName 'scheduler') `
            -SecretResolver $resolver

        $context.Principal.ExecutionType | Should -Be 'System'
        $context.Credential.CredentialType | Should -Be 'System'
        $context.Credential.UsedFallback | Should -BeFalse
        $context.RetryPolicy.Mode | Should -Be 'Noninteractive'
        $context.RetryPolicy.TotalBudgetSeconds | Should -Be 180.0
        $context.CorrelationId | Should -Match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    }
}

Describe 'Get-FsuExecutionContext: fail closed before secret resolution' {

    It 'does not resolve a secret when the invocation is unauthenticated' {
        $resolver = { param($Name) throw "SecretResolver should not have been invoked for $Name" }
        { Get-FsuExecutionContext -Config (New-FsuValidConfigHashtable) -HostInvocation (New-FsuTestHostInvocation -Surface App) -SecretResolver $resolver } |
            Should -Throw '*trusted PSU identity*'
    }

    It 'does not resolve a secret when configuration is invalid' {
        $bad = New-FsuValidConfigHashtable
        $bad.BaseUri = 'http://acme.freshservice.com/api/v2/'
        $resolver = { param($Name) throw "SecretResolver should not have been invoked for $Name" }
        { Get-FsuExecutionContext -Config $bad -HostInvocation (New-FsuTestHostInvocation -Surface Api -ClaimsPrincipal (New-FsuSamlClaimsPrincipal)) -SecretResolver $resolver } |
            Should -Throw '*HTTPS*'
    }

    It 'fails when neither Config nor FreshservicePSUConfig is present' {
        $resolver = { param($Name) throw "SecretResolver should not have been invoked for $Name" }
        { Get-FsuExecutionContext -HostInvocation (New-FsuTestHostInvocation -Surface Api -ClaimsPrincipal (New-FsuSamlClaimsPrincipal)) -SecretResolver $resolver } |
            Should -Throw '*FreshservicePSUConfig*'
    }

    It 'rejects a spoofed Freshservice.Configuration object carrying an attacker host, despite the trusted type name' {
        # The type name alone must not be trusted as proof of provenance: a
        # caller-scope variable can carry any PSTypeNames value. A forged
        # object with the right type name but an attacker BaseUri host must
        # still fail HTTPS/path/host validation rather than skip it.
        $spoofed = [PSCustomObject]@{
            PSTypeName = 'Freshservice.Configuration'
            SchemaVersion = '1.0'
            Stage = 'Prod'
            Tenant = 'acme'
            BaseUri = 'https://attacker.example.com/api/v2/'
            DefaultSecret = 'FreshService.System.Prod'
            AllowSystemFallback = $true
            Authentication = [PSCustomObject]@{
                PSTypeName = 'Freshservice.Configuration.Authentication'
                AllowedTypes = @('SAML', 'OIDC')
                TrustedTenants = @('11111111-1111-1111-1111-111111111111')
                TrustedIssuers = @('https://sts.windows.net/11111111-1111-1111-1111-111111111111/')
            }
            Users = @{}
        }
        $resolver = { param($Name) throw "SecretResolver should not have been invoked for $Name" }
        { Get-FsuExecutionContext -Config $spoofed -HostInvocation (New-FsuTestHostInvocation -Surface Api -ClaimsPrincipal (New-FsuSamlClaimsPrincipal)) -SecretResolver $resolver } |
            Should -Throw '*does not match the configured tenant*'
    }
}

Describe 'Get-FsuExecutionContext: isolation and redaction' {

    It 'does not retain or exchange credentials across sequential calls' {
        $alice = Get-FsuExecutionContext `
            -Config (New-FsuValidConfigHashtable) `
            -HostInvocation (New-FsuTestHostInvocation -Surface Api -ClaimsPrincipal (New-FsuSamlClaimsPrincipal)) `
            -SecretResolver (New-FsuTestSecretResolver -Plaintext 'alice-key-DO-NOT-LEAK-1') `
            -CorrelationId 'corr-alice'

        $otherClaims = New-FsuSamlClaimsPrincipal -ObjectId 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb' -Name 'bob@contoso.com'
        $bob = Get-FsuExecutionContext `
            -Config (New-FsuValidConfigHashtable) `
            -HostInvocation (New-FsuTestHostInvocation -Surface Api -ClaimsPrincipal $otherClaims) `
            -SecretResolver (New-FsuTestSecretResolver -Plaintext 'bob-fallback-DO-NOT-LEAK-2') `
            -CorrelationId 'corr-bob'

        $alice.CorrelationId | Should -Be 'corr-alice'
        $bob.CorrelationId | Should -Be 'corr-bob'
        $alice.Principal.PrincipalId | Should -Not -Be $bob.Principal.PrincipalId
        $alice.Credential.CredentialType | Should -Be 'User'
        $bob.Credential.CredentialType | Should -Be 'System'
        $alice.Credential.UsedFallback | Should -BeFalse
        $bob.Credential.UsedFallback | Should -BeTrue
    }

    It 'does not put the API key plaintext in formatted or serialized context output' {
        $context = Get-FsuExecutionContext `
            -Config (New-FsuValidConfigHashtable) `
            -HostInvocation (New-FsuTestHostInvocation -Surface Api -ClaimsPrincipal (New-FsuSamlClaimsPrincipal)) `
            -SecretResolver (New-FsuTestSecretResolver -Plaintext $plaintext)

        $formatted = $context | Out-String
        $json = $context | ConvertTo-Json -Depth 6 -WarningAction SilentlyContinue
        $formatted | Should -Not -Match ([regex]::Escape($plaintext))
        $json | Should -Not -Match ([regex]::Escape($plaintext))
        $formatted | Should -Not -Match 'Authorization'
    }

    It 'does not expose PrincipalId, Stage, Tenant, or AuthenticationType as parameters' {
        $parameters = (Get-Command Get-FsuExecutionContext).Parameters.Keys
        @('PrincipalId', 'Stage', 'Tenant', 'AuthenticationType', 'ApiKey', 'Secret', 'ActingSecretName') |
            ForEach-Object { $parameters | Should -Not -Contain $_ }
    }
}

Describe 'Get-FsuExecutionContext: app-forwarded acting secret' {

    It 'honors an ambient FreshServiceActingSecret on a scheduled (job) invocation' {
        $FreshServiceActingSecret = 'FreshService.User.aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
        $context = Get-FsuExecutionContext `
            -Config (New-FsuValidConfigHashtable) `
            -HostInvocation (New-FsuTestHostInvocation -Surface Schedule -JobIdentityName 'drjob') `
            -SecretResolver (New-FsuTestSecretResolver)

        $context.Principal.ExecutionType | Should -Be 'System'
        $context.Credential.CredentialType | Should -Be 'DelegatedUser'
        $context.Credential.SecretName | Should -Be 'FreshService.User.aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
    }

    It 'ignores an ambient FreshServiceActingSecret for an interactive caller (validated identity wins)' {
        $FreshServiceActingSecret = 'FreshService.User.some-other-oid'
        $context = Get-FsuExecutionContext `
            -Config (New-FsuValidConfigHashtable) `
            -HostInvocation (New-FsuTestHostInvocation -Surface Api -ClaimsPrincipal (New-FsuSamlClaimsPrincipal)) `
            -SecretResolver (New-FsuTestSecretResolver)

        $context.Credential.CredentialType | Should -Be 'User'
        $context.Credential.SecretName | Should -Be 'FreshService.Alice.Prod'
    }

    It 'ignores a blank ambient FreshServiceActingSecret and uses the system default' {
        $FreshServiceActingSecret = '   '
        $context = Get-FsuExecutionContext `
            -Config (New-FsuValidConfigHashtable) `
            -HostInvocation (New-FsuTestHostInvocation -Surface Schedule -JobIdentityName 'drjob') `
            -SecretResolver (New-FsuTestSecretResolver)

        $context.Credential.CredentialType | Should -Be 'System'
        $context.Credential.SecretName | Should -Be 'FreshService.System.Prod'
    }
}

Describe 'Get-FsuHostInvocation' {

    It 'classifies a UAJob-backed caller as Schedule' {
        $UAJob = [PSCustomObject]@{ Identity = [PSCustomObject]@{ Name = 'job-user' } }
        $snapshot = Get-FsuHostInvocation
        $snapshot.PSObject.TypeNames | Should -Contain 'Freshservice.HostInvocation'
        $snapshot.Surface | Should -Be 'Schedule'
        $snapshot.JobIdentityName | Should -Be 'job-user'
    }

    It 'returns Unknown when no PSU automatic variables are present' {
        # This It block does not define ClaimsPrincipal, Identity, User, or UAJob.
        $snapshot = Get-FsuHostInvocation
        $snapshot.Surface | Should -Be 'Unknown'
        $snapshot.ClaimsPrincipal | Should -BeNullOrEmpty
    }
}
