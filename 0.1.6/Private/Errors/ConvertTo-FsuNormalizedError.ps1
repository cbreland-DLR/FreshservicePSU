function ConvertTo-FsuNormalizedError {
    <#
    .SYNOPSIS
        Normalizes a Freshservice API failure into a stable PowerShell error
        record (ARCHITECTURE.md §11 "Errors").

    .DESCRIPTION
        Maps Freshservice v2's closed `code` set and documented HTTP statuses
        into stable ErrorCategory and FullyQualifiedErrorId values. `field` is
        preserved. Four groupings carry design weight and are honored here:
        the credential/tenant-state codes stay individually distinguishable,
        `require_feature` gets its own self-explaining error, `readonly_field`
        / `inaccessible_field` / `incompatible_field` stay distinct, and
        405/406/415 are surfaced as defects in this module's own request
        construction. Never accepts or returns secrets, authorization values,
        or sensitive request bodies.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.ErrorRecord])]
    param(
        [Parameter(Mandatory)]
        [ValidateRange(100, 599)]
        [int]$StatusCode,

        [ValidateSet(
            'missing_field', 'invalid_value', 'duplicate_value', 'datatype_mismatch',
            'invalid_field', 'invalid_json', 'invalid_credentials', 'access_denied',
            'require_feature', 'account_suspended', 'ssl_required', 'readonly_field',
            'password_lockout', 'password_expired', 'no_content_required',
            'inaccessible_field', 'incompatible_field', 'unsupported_authentication_type',
            'access_token_expired', 'access_token_invalid'
        )]
        [string]$Code,

        [string]$Field,

        [string]$Message,

        [string]$CorrelationId
    )

    # Closed code -> (Id suffix, ErrorCategory) map. Every entry gets its own
    # FullyQualifiedErrorId suffix so the four design-weight groupings stay
    # individually distinguishable even where categories are shared.
    $codeMap = @{
        missing_field = @{ Id = 'MissingField'; Category = 'InvalidData' }
        invalid_value = @{ Id = 'InvalidValue'; Category = 'InvalidData' }
        duplicate_value = @{ Id = 'DuplicateValue'; Category = 'ResourceExists' }
        datatype_mismatch = @{ Id = 'DatatypeMismatch'; Category = 'InvalidData' }
        invalid_field = @{ Id = 'InvalidField'; Category = 'InvalidData' }
        invalid_json = @{ Id = 'InvalidJson'; Category = 'InvalidData' }
        invalid_credentials = @{ Id = 'InvalidCredentials'; Category = 'AuthenticationError' }
        access_denied = @{ Id = 'AccessDenied'; Category = 'PermissionDenied' }
        require_feature = @{ Id = 'RequireFeature'; Category = 'PermissionDenied' }
        account_suspended = @{ Id = 'AccountSuspended'; Category = 'PermissionDenied' }
        ssl_required = @{ Id = 'SslRequired'; Category = 'SecurityError' }
        readonly_field = @{ Id = 'ReadonlyField'; Category = 'InvalidOperation' }
        password_lockout = @{ Id = 'PasswordLockout'; Category = 'AuthenticationError' }
        password_expired = @{ Id = 'PasswordExpired'; Category = 'AuthenticationError' }
        no_content_required = @{ Id = 'NoContentRequired'; Category = 'InvalidData' }
        inaccessible_field = @{ Id = 'InaccessibleField'; Category = 'PermissionDenied' }
        incompatible_field = @{ Id = 'IncompatibleField'; Category = 'InvalidData' }
        unsupported_authentication_type = @{ Id = 'UnsupportedAuthenticationType'; Category = 'AuthenticationError' }
        access_token_expired = @{ Id = 'AccessTokenExpired'; Category = 'AuthenticationError' }
        access_token_invalid = @{ Id = 'AccessTokenInvalid'; Category = 'AuthenticationError' }
    }

    # Status fallback map, used when no `code` is supplied (e.g. 404, 409) or
    # when the code is not present in the closed set above.
    $statusMap = @{
        400 = @{ Id = 'Validation'; Category = 'InvalidData' }
        401 = @{ Id = 'AuthenticationFailure'; Category = 'AuthenticationError' }
        403 = @{ Id = 'AccessDenied'; Category = 'PermissionDenied' }
        404 = @{ Id = 'NotFound'; Category = 'ObjectNotFound' }
        405 = @{ Id = 'MethodNotAllowed'; Category = 'InvalidOperation' }
        406 = @{ Id = 'NotAcceptable'; Category = 'InvalidOperation' }
        409 = @{ Id = 'Conflict'; Category = 'ResourceExists' }
        415 = @{ Id = 'UnsupportedMediaType'; Category = 'InvalidOperation' }
        429 = @{ Id = 'RateLimited'; Category = 'LimitsExceeded' }
        500 = @{ Id = 'ServerError'; Category = 'NotSpecified' }
    }

    $requestDefectStatuses = @(405, 406, 415)

    if ($Code -and $codeMap.ContainsKey($Code)) {
        $mapping = $codeMap[$Code]
    } elseif ($statusMap.ContainsKey($StatusCode)) {
        $mapping = $statusMap[$StatusCode]
    } else {
        $mapping = @{ Id = 'Unmapped'; Category = 'NotSpecified' }
    }

    $errorId = "FreshservicePSU.Error.$($mapping.Id)"
    if ($StatusCode -in $requestDefectStatuses) {
        # 405/406/415 indicate a defect in this module's own request
        # construction rather than caller input; the Id makes that explicit
        # regardless of whether a `code` was also supplied.
        $errorId = "FreshservicePSU.Error.RequestDefect.$($mapping.Id)"
    }

    $resolvedMessage = if ($Message) {
        $Message
    } elseif ($Code) {
        "Freshservice API request failed with status $StatusCode and code '$Code'."
    } else {
        "Freshservice API request failed with status $StatusCode."
    }

    return New-FsuErrorRecord -ErrorId $errorId -Message $resolvedMessage -Category ([System.Management.Automation.ErrorCategory]$mapping.Category) -CorrelationId $CorrelationId -Field $Field -Code $Code -StatusCode $StatusCode
}
