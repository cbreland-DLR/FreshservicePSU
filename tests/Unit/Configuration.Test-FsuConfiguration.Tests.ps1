<#
.SYNOPSIS
    Unit tests for Test-FsuConfiguration (ARCHITECTURE.md §7,
    IMPLEMENTATION_PLAN.md Phase 3).
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repoRoot 'FreshservicePSU/Private/Errors/New-FsuErrorRecord.ps1')
    . (Join-Path $repoRoot 'FreshservicePSU/Private/Configuration/Test-FsuConfiguration.ps1')

    function New-FsuValidConfigHashtable {
        [System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Test fixture builder; no system state is changed.')]
        param()

        return @{
            SchemaVersion = '1.0'
            Stage = 'Prod'
            Tenant = 'acme'
            BaseUri = 'https://acme.freshservice.com/api/v2/'
            DefaultSecret = 'FreshService.System.Prod'
            AllowSystemFallback = $true
            Authentication = @{
                AllowedTypes = @('SAML', 'OIDC')
                TrustedTenants = @('11111111-1111-1111-1111-111111111111')
                TrustedIssuers = @('https://sts.windows.net/11111111-1111-1111-1111-111111111111/')
            }
            Users = @{
                'entra:11111111-1111-1111-1111-111111111111:aaaa' = 'FreshService.Alice.Prod'
            }
        }
    }
}

Describe 'Test-FsuConfiguration: success path' {

    It 'returns a Freshservice.Configuration object for a valid config' {
        $result = Test-FsuConfiguration -Config (New-FsuValidConfigHashtable)
        $result.PSObject.TypeNames | Should -Contain 'Freshservice.Configuration'
        $result.Stage | Should -Be 'Prod'
        $result.Tenant | Should -Be 'acme'
    }

    It 'accepts Stage Dev' {
        $config = New-FsuValidConfigHashtable
        $config.Stage = 'Dev'
        $result = Test-FsuConfiguration -Config $config
        $result.Stage | Should -Be 'Dev'
    }
}

Describe 'Test-FsuConfiguration: fail-closed modes' {

    BeforeEach {
        $script:config = New-FsuValidConfigHashtable
    }

    It 'throws on a non-dictionary config' {
        { Test-FsuConfiguration -Config 'not a hashtable' } | Should -Throw
    }

    It 'throws on a null config' {
        { Test-FsuConfiguration -Config $null } | Should -Throw
    }

    It 'throws on an unsupported SchemaVersion' {
        $config.SchemaVersion = '2.0'
        { Test-FsuConfiguration -Config $config } | Should -Throw '*SchemaVersion*'
    }

    It 'throws on an unknown top-level property' {
        $config.WorkspaceId = 123
        { Test-FsuConfiguration -Config $config } | Should -Throw '*Unknown*'
    }

    It 'throws on a missing top-level property' {
        $config.Remove('DefaultSecret')
        { Test-FsuConfiguration -Config $config } | Should -Throw '*missing*'
    }

    It 'throws on an unknown Authentication property' {
        $config.Authentication['ExtraProperty'] = 'x'
        { Test-FsuConfiguration -Config $config } | Should -Throw '*Authentication*'
    }

    It 'throws on a missing Authentication property' {
        $config.Authentication.Remove('TrustedIssuers')
        { Test-FsuConfiguration -Config $config } | Should -Throw '*Authentication*'
    }

    It 'throws on a non-HTTPS BaseUri' {
        $config.BaseUri = 'http://acme.freshservice.com/api/v2/'
        { Test-FsuConfiguration -Config $config } | Should -Throw '*HTTPS*'
    }

    It 'throws on a BaseUri outside /api/v2/' {
        $config.BaseUri = 'https://acme.freshservice.com/api/v1/'
        { Test-FsuConfiguration -Config $config } | Should -Throw '*api/v2*'
    }

    # A "contains /api/v2/" check accepts both of these. The first is the one
    # that matters: configuration selects the tenant, so a validator that
    # accepts an arbitrary host with a decoy path is a directed-traffic hole.
    It 'throws on a BaseUri whose /api/v2/ is a decoy under another host path' {
        $config.BaseUri = 'https://attacker.example.com/decoy/api/v2/'
        { Test-FsuConfiguration -Config $config } | Should -Throw '*api/v2*'
    }

    It 'throws on a BaseUri carrying a resource path below /api/v2/' {
        $config.BaseUri = 'https://acme.freshservice.com/api/v2/tickets/'
        { Test-FsuConfiguration -Config $config } | Should -Throw '*api/v2*'
    }

    # The exact path is satisfied here; only binding the host to the tenant
    # stops every authenticated request going to another host.
    It 'throws when the BaseUri host is not the configured tenant' {
        $config.BaseUri = 'https://attacker.example.com/api/v2/'
        { Test-FsuConfiguration -Config $config } | Should -Throw '*does not match the configured tenant*'
    }

    It 'throws on a BaseUri carrying userinfo, a query, or a fragment' -ForEach @(
        @{ Uri = 'https://user:pass@acme.freshservice.com/api/v2/' }
        @{ Uri = 'https://acme.freshservice.com/api/v2/?impersonate=admin' }
        @{ Uri = 'https://acme.freshservice.com/api/v2/#frag' }
    ) {
        $config.BaseUri = $Uri
        { Test-FsuConfiguration -Config $config } | Should -Throw '*userinfo*'
    }

    It 'throws when a case-sensitive dictionary carries two spellings of one property' {
        $ambiguous = [System.Collections.Specialized.OrderedDictionary]::new([System.StringComparer]::Ordinal)
        foreach ($entry in $config.GetEnumerator()) {
            $ambiguous[$entry.Key] = $entry.Value
        }
        $ambiguous['stage'] = 'Dev'
        { Test-FsuConfiguration -Config $ambiguous } | Should -Throw '*unique*'
    }

    It 'throws when an Authentication list is a bare string rather than an array' {
        $config.Authentication['AllowedTypes'] = 'SAML'
        { Test-FsuConfiguration -Config $config } | Should -Throw '*must be an array*'
    }

    It 'throws when an Authentication list is empty' {
        $config.Authentication['TrustedTenants'] = @()
        { Test-FsuConfiguration -Config $config } | Should -Throw '*at least one entry*'
    }

    It 'throws on a non-string entry inside an Authentication list' {
        $config.Authentication['TrustedTenants'] = @(42)
        { Test-FsuConfiguration -Config $config } | Should -Throw '*non-empty strings*'
    }

    It 'throws on an authentication type the module does not implement' {
        $config.Authentication['AllowedTypes'] = @('SAML', 'Password')
        { Test-FsuConfiguration -Config $config } | Should -Throw '*Password*'
    }

    It 'throws on a TrustedIssuers entry that is not an absolute HTTPS URI' {
        $config.Authentication['TrustedIssuers'] = @('not a uri')
        { Test-FsuConfiguration -Config $config } | Should -Throw '*absolute HTTPS URI*'
    }

    It 'throws on a malformed BaseUri' {
        $config.BaseUri = 'not a uri'
        { Test-FsuConfiguration -Config $config } | Should -Throw
    }

    It 'throws on duplicate Users keys differing only by case in a case-sensitive ordered dictionary (an ordinary hashtable cannot even hold both keys, since PowerShell hashtables are already case-insensitive)' {
        $ordered = [System.Collections.Specialized.OrderedDictionary]::new([System.StringComparer]::Ordinal)
        $ordered['entra:tenant:AAAA'] = 'FreshService.Alice.Prod'
        $ordered['entra:tenant:aaaa'] = 'FreshService.Bob.Prod'
        $config.Users = $ordered
        { Test-FsuConfiguration -Config $config } | Should -Throw '*unique*'
    }

    It 'throws on an invalid Stage value' {
        $config.Stage = 'Staging'
        { Test-FsuConfiguration -Config $config } | Should -Throw '*Stage*'
    }

    It 'throws on a non-boolean AllowSystemFallback' {
        $config.AllowSystemFallback = 'yes'
        { Test-FsuConfiguration -Config $config } | Should -Throw
    }

    It 'throws on an empty DefaultSecret' {
        $config.DefaultSecret = ''
        { Test-FsuConfiguration -Config $config } | Should -Throw
    }

    It 'never returns a partially-valid object on failure (the config variable is untouched by a throwing call)' {
        $config.SchemaVersion = '2.0'
        $threw = $false
        try {
            $result = Test-FsuConfiguration -Config $config
        } catch {
            $threw = $true
        }
        $threw | Should -Be $true
        Get-Variable -Name result -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
    }
}
