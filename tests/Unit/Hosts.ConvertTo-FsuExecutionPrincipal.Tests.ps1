<#
.SYNOPSIS
    Unit tests for ConvertTo-FsuExecutionPrincipal (ARCHITECTURE.md §6).
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repoRoot '0.1.6/Private/Errors/New-FsuErrorRecord.ps1')
    . (Join-Path $repoRoot '0.1.6/Private/Configuration/Test-FsuConfiguration.ps1')
    . (Join-Path $repoRoot '0.1.6/Private/Hosts/PowerShellUniversal/ConvertTo-FsuExecutionPrincipal.ps1')
    . (Join-Path $PSScriptRoot 'FsuIdentityFixtures.ps1')

    $script:configuration = Test-FsuConfiguration -Config (New-FsuValidConfigHashtable)
    $script:expectedPrincipalId = 'entra:11111111-1111-1111-1111-111111111111:aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
}

Describe 'ConvertTo-FsuExecutionPrincipal: documented Entra maps' {

    It 'normalizes SAML objectidentifier, tenantid, and name into entra:tenant:object' {
        $invocation = New-FsuTestHostInvocation -Surface Api -ClaimsPrincipal (New-FsuSamlClaimsPrincipal)
        $principal = ConvertTo-FsuExecutionPrincipal -HostInvocation $invocation -Configuration $configuration

        $principal.PSObject.TypeNames | Should -Contain 'Freshservice.ExecutionPrincipal'
        $principal.PrincipalId | Should -Be $expectedPrincipalId
        $principal.UserPrincipalName | Should -Be 'alice@contoso.com'
        $principal.ExecutionType | Should -Be 'Interactive'
        $principal.AuthenticationType | Should -Be 'SAML'
    }

    It 'normalizes OIDC oid, tid, and preferred_username into the same PrincipalId' {
        $invocation = New-FsuTestHostInvocation -Surface App -ClaimsPrincipal (New-FsuOidcClaimsPrincipal)
        $principal = ConvertTo-FsuExecutionPrincipal -HostInvocation $invocation -Configuration $configuration

        $principal.PrincipalId | Should -Be $expectedPrincipalId
        $principal.UserPrincipalName | Should -Be 'alice@contoso.com'
        $principal.ExecutionType | Should -Be 'Interactive'
        $principal.AuthenticationType | Should -Be 'OIDC'
    }

    It 'produces the same PrincipalId for the same Entra user under SAML and OIDC' {
        $saml = ConvertTo-FsuExecutionPrincipal -HostInvocation (New-FsuTestHostInvocation -Surface Api -ClaimsPrincipal (New-FsuSamlClaimsPrincipal)) -Configuration $configuration
        $oidc = ConvertTo-FsuExecutionPrincipal -HostInvocation (New-FsuTestHostInvocation -Surface Api -ClaimsPrincipal (New-FsuOidcClaimsPrincipal)) -Configuration $configuration
        $saml.PrincipalId | Should -Be $oidc.PrincipalId
    }

    It 'normalizes mixed-case GUID claims to lowercase' {
        $claims = New-FsuSamlClaimsPrincipal -ObjectId 'AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA' -TenantId '11111111-1111-1111-1111-111111111111'
        $principal = ConvertTo-FsuExecutionPrincipal -HostInvocation (New-FsuTestHostInvocation -Surface Api -ClaimsPrincipal $claims) -Configuration $configuration
        $principal.PrincipalId | Should -Be $expectedPrincipalId
    }

    It 'derives tenant from a trusted issuer when the tenant claim is absent' {
        $claims = New-FsuTestClaimsPrincipal -Issuer 'https://sts.windows.net/11111111-1111-1111-1111-111111111111/' -Claim @{
            'http://schemas.microsoft.com/identity/claims/objectidentifier' = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
            'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name' = 'alice@contoso.com'
        }
        $principal = ConvertTo-FsuExecutionPrincipal -HostInvocation (New-FsuTestHostInvocation -Surface Api -ClaimsPrincipal $claims) -Configuration $configuration
        $principal.PrincipalId | Should -Be $expectedPrincipalId
    }

    It 'uses OIDC upn when preferred_username is absent' {
        $claims = New-FsuTestClaimsPrincipal -Issuer 'https://login.microsoftonline.com/11111111-1111-1111-1111-111111111111/v2.0' -Claim @{
            oid = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
            tid = '11111111-1111-1111-1111-111111111111'
            upn = 'alice@contoso.com'
        }
        $principal = ConvertTo-FsuExecutionPrincipal -HostInvocation (New-FsuTestHostInvocation -Surface Api -ClaimsPrincipal $claims) -Configuration $configuration
        $principal.UserPrincipalName | Should -Be 'alice@contoso.com'
        $principal.AuthenticationType | Should -Be 'OIDC'
    }
}

Describe 'ConvertTo-FsuExecutionPrincipal: system and unauthenticated surfaces' {

    It 'classifies a schedule without claims as System' {
        $invocation = New-FsuTestHostInvocation -Surface Schedule -JobIdentityName 'schedule-account'
        $principal = ConvertTo-FsuExecutionPrincipal -HostInvocation $invocation -Configuration $configuration
        $principal.PrincipalId | Should -Be 'system'
        $principal.UserPrincipalName | Should -Be 'schedule-account'
        $principal.ExecutionType | Should -Be 'System'
        $principal.AuthenticationType | Should -Be 'System'
    }

    It 'classifies an API identity with no claims as System (app token / automation)' {
        $invocation = New-FsuTestHostInvocation -Surface Api -Identity 'app-token-caller'
        $principal = ConvertTo-FsuExecutionPrincipal -HostInvocation $invocation -Configuration $configuration
        $principal.ExecutionType | Should -Be 'System'
        $principal.AuthenticationType | Should -Be 'System'
        $principal.UserPrincipalName | Should -Be 'app-token-caller'
    }

    It 'denies an App invocation with no claims even when system fallback exists' {
        $invocation = New-FsuTestHostInvocation -Surface App -User $null
        { ConvertTo-FsuExecutionPrincipal -HostInvocation $invocation -Configuration $configuration } |
            Should -Throw '*trusted PSU identity*'
    }

    It 'denies a missing invocation' {
        { ConvertTo-FsuExecutionPrincipal -HostInvocation $null -Configuration $configuration } |
            Should -Throw '*invocation*'
    }

    It 'denies Unknown surface with no claims' {
        $invocation = New-FsuTestHostInvocation -Surface Unknown
        { ConvertTo-FsuExecutionPrincipal -HostInvocation $invocation -Configuration $configuration } |
            Should -Throw '*trusted PSU identity*'
    }
}

Describe 'ConvertTo-FsuExecutionPrincipal: fail-closed claim validation' {

    It 'does not use email as a credential-map key' {
        $claims = New-FsuTestClaimsPrincipal -Claim @{
            'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress' = 'alice@contoso.com'
            email = 'alice@contoso.com'
        }
        { ConvertTo-FsuExecutionPrincipal -HostInvocation (New-FsuTestHostInvocation -Surface Api -ClaimsPrincipal $claims) -Configuration $configuration } |
            Should -Throw '*immutable object identifier*'
    }

    It 'rejects conflicting object identifiers' {
        $claims = New-FsuTestClaimsPrincipal -Claim @{
            'http://schemas.microsoft.com/identity/claims/objectidentifier' = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
            oid = 'bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'
            'http://schemas.microsoft.com/identity/claims/tenantid' = '11111111-1111-1111-1111-111111111111'
            'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name' = 'alice@contoso.com'
        }
        { ConvertTo-FsuExecutionPrincipal -HostInvocation (New-FsuTestHostInvocation -Surface Api -ClaimsPrincipal $claims) -Configuration $configuration } |
            Should -Throw '*conflicting immutable object*'
    }

    It 'rejects a principal mixing a trusted-issuer claim with identity claims from an untrusted source' {
        # The 'iss'/tenant claims are co-asserted under a trusted issuer, but
        # the object-id and name claims are attributed to a different,
        # untrusted source within the same ClaimsPrincipal. The trusted iss
        # claim must not vouch for identity claims it did not actually carry.
        $claims = New-FsuMixedIssuerClaimsPrincipal
        { ConvertTo-FsuExecutionPrincipal -HostInvocation (New-FsuTestHostInvocation -Surface Api -ClaimsPrincipal $claims) -Configuration $configuration } |
            Should -Throw '*issuer*'
    }

    It 'rejects an untrusted issuer' {
        $claims = New-FsuSamlClaimsPrincipal -Issuer 'https://sts.windows.net/99999999-9999-9999-9999-999999999999/'
        { ConvertTo-FsuExecutionPrincipal -HostInvocation (New-FsuTestHostInvocation -Surface Api -ClaimsPrincipal $claims) -Configuration $configuration } |
            Should -Throw '*issuer*'
    }

    It 'rejects an untrusted tenant' {
        $claims = New-FsuSamlClaimsPrincipal -TenantId '99999999-9999-9999-9999-999999999999'
        { ConvertTo-FsuExecutionPrincipal -HostInvocation (New-FsuTestHostInvocation -Surface Api -ClaimsPrincipal $claims) -Configuration $configuration } |
            Should -Throw '*tenant*'
    }

    It 'rejects SAML when AllowedTypes is only OIDC' {
        $oidcOnly = Test-FsuConfiguration -Config (New-FsuValidConfigHashtable -AllowedTypes @('OIDC'))
        $invocation = New-FsuTestHostInvocation -Surface Api -ClaimsPrincipal (New-FsuSamlClaimsPrincipal)
        { ConvertTo-FsuExecutionPrincipal -HostInvocation $invocation -Configuration $oidcOnly } |
            Should -Throw '*authentication type*'
    }

    It 'rejects a missing readable username' {
        $claims = New-FsuTestClaimsPrincipal -Claim @{
            'http://schemas.microsoft.com/identity/claims/objectidentifier' = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
            'http://schemas.microsoft.com/identity/claims/tenantid' = '11111111-1111-1111-1111-111111111111'
        }
        { ConvertTo-FsuExecutionPrincipal -HostInvocation (New-FsuTestHostInvocation -Surface Api -ClaimsPrincipal $claims) -Configuration $configuration } |
            Should -Throw '*readable username*'
    }

    It 'ignores a spoofed PrincipalId property on the invocation object' {
        $invocation = New-FsuTestHostInvocation -Surface Api -ClaimsPrincipal (New-FsuSamlClaimsPrincipal)
        $invocation | Add-Member -NotePropertyName PrincipalId -NotePropertyValue 'entra:evil-tenant:evil-object'
        $invocation | Add-Member -NotePropertyName AuthenticationType -NotePropertyValue 'OIDC'
        $invocation | Add-Member -NotePropertyName Stage -NotePropertyValue 'Dev'
        $principal = ConvertTo-FsuExecutionPrincipal -HostInvocation $invocation -Configuration $configuration
        $principal.PrincipalId | Should -Be $expectedPrincipalId
        $principal.AuthenticationType | Should -Be 'SAML'
    }
}

Describe 'ConvertTo-FsuExecutionPrincipal: Authentication is optional' {

    BeforeAll {
        # A minimal config omits Authentication, so its validated form carries
        # Authentication = $null and the interactive per-user path is disabled.
        $script:noAuthConfig = Test-FsuConfiguration -Config @{
            SchemaVersion = '1.0'
            Stage = 'Prod'
            Tenant = 'acme'
            DefaultSecret = 'FreshService.System.Prod'
            AllowSystemFallback = $true
        }
    }

    It 'resolves an interactive caller as System when the config has no Authentication policy' {
        $invocation = New-FsuTestHostInvocation -Surface App -User 'alice' -ClaimsPrincipal (New-FsuOidcClaimsPrincipal)
        $principal = ConvertTo-FsuExecutionPrincipal -HostInvocation $invocation -Configuration $noAuthConfig
        $principal.ExecutionType | Should -Be 'System'
        $principal.PrincipalId | Should -Be 'system'
        $principal.AuthenticationType | Should -Be 'System'
    }

    It 'resolves a job caller as System (named by the job identity) with no Authentication policy' {
        $invocation = New-FsuTestHostInvocation -Surface Schedule -JobIdentityName 'drjob'
        $principal = ConvertTo-FsuExecutionPrincipal -HostInvocation $invocation -Configuration $noAuthConfig
        $principal.ExecutionType | Should -Be 'System'
        $principal.UserPrincipalName | Should -Be 'drjob'
    }
}
