<#
.SYNOPSIS
    Unit tests for ConvertTo-FsuNormalizedError (ARCHITECTURE.md §11 "Errors").
#>

BeforeDiscovery {
    # Hashtables, not PSCustomObjects: Pester -ForEach binds hashtable keys
    # directly to test-scoped variables.
    $script:codeCases = @(
        @{ Code = 'missing_field'; StatusCode = 400; ExpectedId = 'FreshservicePSU.Error.MissingField'; ExpectedCategory = 'InvalidData' }
        @{ Code = 'invalid_value'; StatusCode = 400; ExpectedId = 'FreshservicePSU.Error.InvalidValue'; ExpectedCategory = 'InvalidData' }
        @{ Code = 'duplicate_value'; StatusCode = 400; ExpectedId = 'FreshservicePSU.Error.DuplicateValue'; ExpectedCategory = 'ResourceExists' }
        @{ Code = 'datatype_mismatch'; StatusCode = 400; ExpectedId = 'FreshservicePSU.Error.DatatypeMismatch'; ExpectedCategory = 'InvalidData' }
        @{ Code = 'invalid_field'; StatusCode = 400; ExpectedId = 'FreshservicePSU.Error.InvalidField'; ExpectedCategory = 'InvalidData' }
        @{ Code = 'invalid_json'; StatusCode = 400; ExpectedId = 'FreshservicePSU.Error.InvalidJson'; ExpectedCategory = 'InvalidData' }
        @{ Code = 'invalid_credentials'; StatusCode = 401; ExpectedId = 'FreshservicePSU.Error.InvalidCredentials'; ExpectedCategory = 'AuthenticationError' }
        @{ Code = 'access_denied'; StatusCode = 403; ExpectedId = 'FreshservicePSU.Error.AccessDenied'; ExpectedCategory = 'PermissionDenied' }
        @{ Code = 'require_feature'; StatusCode = 403; ExpectedId = 'FreshservicePSU.Error.RequireFeature'; ExpectedCategory = 'PermissionDenied' }
        @{ Code = 'account_suspended'; StatusCode = 403; ExpectedId = 'FreshservicePSU.Error.AccountSuspended'; ExpectedCategory = 'PermissionDenied' }
        @{ Code = 'ssl_required'; StatusCode = 403; ExpectedId = 'FreshservicePSU.Error.SslRequired'; ExpectedCategory = 'SecurityError' }
        @{ Code = 'readonly_field'; StatusCode = 400; ExpectedId = 'FreshservicePSU.Error.ReadonlyField'; ExpectedCategory = 'InvalidOperation' }
        @{ Code = 'password_lockout'; StatusCode = 401; ExpectedId = 'FreshservicePSU.Error.PasswordLockout'; ExpectedCategory = 'AuthenticationError' }
        @{ Code = 'password_expired'; StatusCode = 401; ExpectedId = 'FreshservicePSU.Error.PasswordExpired'; ExpectedCategory = 'AuthenticationError' }
        @{ Code = 'no_content_required'; StatusCode = 400; ExpectedId = 'FreshservicePSU.Error.NoContentRequired'; ExpectedCategory = 'InvalidData' }
        @{ Code = 'inaccessible_field'; StatusCode = 403; ExpectedId = 'FreshservicePSU.Error.InaccessibleField'; ExpectedCategory = 'PermissionDenied' }
        @{ Code = 'incompatible_field'; StatusCode = 400; ExpectedId = 'FreshservicePSU.Error.IncompatibleField'; ExpectedCategory = 'InvalidData' }
        @{ Code = 'unsupported_authentication_type'; StatusCode = 401; ExpectedId = 'FreshservicePSU.Error.UnsupportedAuthenticationType'; ExpectedCategory = 'AuthenticationError' }
        @{ Code = 'access_token_expired'; StatusCode = 401; ExpectedId = 'FreshservicePSU.Error.AccessTokenExpired'; ExpectedCategory = 'AuthenticationError' }
        @{ Code = 'access_token_invalid'; StatusCode = 401; ExpectedId = 'FreshservicePSU.Error.AccessTokenInvalid'; ExpectedCategory = 'AuthenticationError' }
    )

    $script:statusOnlyCases = @(
        @{ StatusCode = 400; ExpectedId = 'FreshservicePSU.Error.Validation'; ExpectedCategory = 'InvalidData' }
        @{ StatusCode = 401; ExpectedId = 'FreshservicePSU.Error.AuthenticationFailure'; ExpectedCategory = 'AuthenticationError' }
        @{ StatusCode = 403; ExpectedId = 'FreshservicePSU.Error.AccessDenied'; ExpectedCategory = 'PermissionDenied' }
        @{ StatusCode = 404; ExpectedId = 'FreshservicePSU.Error.NotFound'; ExpectedCategory = 'ObjectNotFound' }
        @{ StatusCode = 405; ExpectedId = 'FreshservicePSU.Error.RequestDefect.MethodNotAllowed'; ExpectedCategory = 'InvalidOperation' }
        @{ StatusCode = 406; ExpectedId = 'FreshservicePSU.Error.RequestDefect.NotAcceptable'; ExpectedCategory = 'InvalidOperation' }
        @{ StatusCode = 409; ExpectedId = 'FreshservicePSU.Error.Conflict'; ExpectedCategory = 'ResourceExists' }
        @{ StatusCode = 415; ExpectedId = 'FreshservicePSU.Error.RequestDefect.UnsupportedMediaType'; ExpectedCategory = 'InvalidOperation' }
        @{ StatusCode = 429; ExpectedId = 'FreshservicePSU.Error.RateLimited'; ExpectedCategory = 'LimitsExceeded' }
        @{ StatusCode = 500; ExpectedId = 'FreshservicePSU.Error.ServerError'; ExpectedCategory = 'NotSpecified' }
    )
}

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repoRoot '0.1.6/Private/Errors/New-FsuErrorRecord.ps1')
    . (Join-Path $repoRoot '0.1.6/Private/Errors/ConvertTo-FsuNormalizedError.ps1')
}

Describe 'ConvertTo-FsuNormalizedError: all 20 closed code values' {

    Context 'Code maps to its expected FullyQualifiedErrorId and category' -ForEach $codeCases {
        It "'<Code>' maps to '<ExpectedId>' / <ExpectedCategory>" {
            $record = ConvertTo-FsuNormalizedError -StatusCode $StatusCode -Code $Code -Message 'test'
            $record.FullyQualifiedErrorId | Should -Be $ExpectedId
            $record.CategoryInfo.Category | Should -Be $ExpectedCategory
        }
    }

    It 'covers exactly 20 documented code values' {
        $codeCases.Count | Should -Be 20
    }
}

Describe 'ConvertTo-FsuNormalizedError: credential/tenant-state codes stay individually distinguishable' {

    It 'invalid_credentials, access_token_expired, account_suspended, password_expired, and password_lockout all produce distinct FullyQualifiedErrorId values' {
        $ids = @('invalid_credentials', 'access_token_expired', 'account_suspended', 'password_expired', 'password_lockout') | ForEach-Object {
            (ConvertTo-FsuNormalizedError -StatusCode 401 -Code $_ -Message 'test').FullyQualifiedErrorId
        }
        ($ids | Sort-Object -Unique).Count | Should -Be 5
    }
}

Describe 'ConvertTo-FsuNormalizedError: require_feature is distinct from a generic 403' {

    It 'require_feature does not collapse into the generic access_denied id' {
        $requireFeature = ConvertTo-FsuNormalizedError -StatusCode 403 -Code 'require_feature' -Message 'test'
        $accessDenied = ConvertTo-FsuNormalizedError -StatusCode 403 -Code 'access_denied' -Message 'test'
        $requireFeature.FullyQualifiedErrorId | Should -Not -Be $accessDenied.FullyQualifiedErrorId
    }
}

Describe 'ConvertTo-FsuNormalizedError: readonly_field, inaccessible_field, incompatible_field stay distinct' {

    It 'produces three distinct FullyQualifiedErrorId values for the three field-rejection causes' {
        $ids = @('readonly_field', 'inaccessible_field', 'incompatible_field') | ForEach-Object {
            (ConvertTo-FsuNormalizedError -StatusCode 400 -Code $_ -Message 'test').FullyQualifiedErrorId
        }
        ($ids | Sort-Object -Unique).Count | Should -Be 3
    }
}

Describe 'ConvertTo-FsuNormalizedError: status-only mapping (no vendor code supplied)' {

    Context 'Status maps to its expected FullyQualifiedErrorId and category' -ForEach $statusOnlyCases {
        It "status <StatusCode> maps to '<ExpectedId>' / <ExpectedCategory>" {
            $record = ConvertTo-FsuNormalizedError -StatusCode $StatusCode -Message 'test'
            $record.FullyQualifiedErrorId | Should -Be $ExpectedId
            $record.CategoryInfo.Category | Should -Be $ExpectedCategory
        }
    }
}

Describe 'ConvertTo-FsuNormalizedError: 405/406/415 are surfaced as module request defects' {

    It 'tags 405, 406, and 415 with a RequestDefect id segment' {
        foreach ($status in @(405, 406, 415)) {
            $record = ConvertTo-FsuNormalizedError -StatusCode $status -Message 'test'
            $record.FullyQualifiedErrorId | Should -Match '^FreshservicePSU\.Error\.RequestDefect\.'
        }
    }
}

Describe 'ConvertTo-FsuNormalizedError: field preservation' {

    It 'preserves the field value on the exception Data collection' {
        $record = ConvertTo-FsuNormalizedError -StatusCode 400 -Code 'missing_field' -Field 'subject' -Message 'test'
        $record.Exception.Data['Field'] | Should -Be 'subject'
    }

    It 'omits Field when none is supplied' {
        $record = ConvertTo-FsuNormalizedError -StatusCode 400 -Code 'missing_field' -Message 'test'
        $record.Exception.Data.Contains('Field') | Should -Be $false
    }
}

Describe 'ConvertTo-FsuNormalizedError: never carries secrets' {

    It 'does not include a supplied secret value in the formatted error output' {
        $secretValue = 'sk_live_super_secret_value_12345'
        $record = ConvertTo-FsuNormalizedError -StatusCode 401 -Code 'invalid_credentials' -Message 'Credential rejected.' -CorrelationId 'corr-1'
        ($record | Out-String) | Should -Not -Match ([regex]::Escape($secretValue))
    }
}
