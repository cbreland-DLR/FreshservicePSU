function ConvertTo-FsuExecutionPrincipal {
    <#
    .SYNOPSIS
        Normalizes a trusted PSU invocation into Freshservice.ExecutionPrincipal.

    .DESCRIPTION
        Implements ARCHITECTURE.md §6 against the documented Entra SAML and
        OIDC claim maps. Interactive callers require exactly one immutable
        object ID, one tenant, one readable username, a trusted issuer, and
        an allowed authentication type. Email is never a credential-map key.
        Extra properties on the invocation object (PrincipalId, Stage,
        Tenant, AuthenticationType) are ignored so user-controlled values
        cannot spoof identity.

        Schedules and other UAJob-backed executions without a claims
        principal use the system identity. An API invocation that has an
        Identity string but no claims principal is treated as noninteractive
        (app token / automation) pending live Q1 evidence. An App
        invocation without claims is anonymous interactive execution and is
        denied.

        Issuer trust is bound to the individual claim it vouches for, not to
        the claims bag as a whole: the object-id claim used for PrincipalId,
        and the tenant/name claims read alongside it, must each resolve to
        the same trusted issuer (via the claim's own Claim.Issuer, or an
        'iss' claim co-asserted with it). A principal that mixes one
        trusted-issuer claim with identity claims carried by another source
        is rejected rather than accepted on the strength of the one trusted
        claim.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $HostInvocation,

        [Parameter(Mandatory)]
        $Configuration,

        [string]$CorrelationId
    )

    function Get-FsuIdentityErrorRecord {
        param(
            [Parameter(Mandatory)]
            [string]$Id,

            [Parameter(Mandatory)]
            [string]$Message,

            [string]$CorrelationId
        )

        New-FsuErrorRecord -ErrorId "FreshservicePSU.Identity.$Id" -Message $Message -Category AuthenticationError -CorrelationId $CorrelationId
    }

    function Get-FsuInvocationProperty {
        param(
            $InputObject,

            [Parameter(Mandatory)]
            [string]$Name
        )

        if ($null -eq $InputObject) {
            return $null
        }

        $property = $InputObject.PSObject.Properties[$Name]
        if ($null -eq $property) {
            return $null
        }

        return $property.Value
    }

    function Get-FsuClaim {
        param(
            [Parameter(Mandatory)]
            [System.Security.Claims.ClaimsPrincipal]$ClaimsPrincipal,

            [Parameter(Mandatory)]
            [AllowEmptyCollection()]
            [string[]]$Type
        )

        $claimMatches = [System.Collections.Generic.List[System.Security.Claims.Claim]]::new()
        foreach ($claim in @($ClaimsPrincipal.Claims)) {
            foreach ($candidate in @($Type)) {
                if ([string]::Equals($claim.Type, $candidate, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $null = $claimMatches.Add($claim)
                }
            }
        }

        return @($claimMatches)
    }

    function Get-FsuDistinctClaimValue {
        param(
            [AllowEmptyCollection()]
            [AllowNull()]
            [System.Security.Claims.Claim[]]$Claim
        )

        $values = [System.Collections.Generic.List[string]]::new()
        foreach ($item in @($Claim)) {
            if ($null -eq $item -or [string]::IsNullOrWhiteSpace($item.Value)) {
                continue
            }

            $normalized = $item.Value.Trim()
            $alreadyPresent = $false
            foreach ($existing in $values) {
                if ([string]::Equals($existing, $normalized, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $alreadyPresent = $true
                    break
                }
            }

            if (-not $alreadyPresent) {
                $null = $values.Add($normalized)
            }
        }

        return @($values)
    }

    function Test-FsuIssuerTrusted {
        param(
            [string]$Issuer,

            [Parameter(Mandatory)]
            [AllowEmptyCollection()]
            [string[]]$TrustedIssuer
        )

        if ([string]::IsNullOrWhiteSpace($Issuer)) {
            return $false
        }

        $candidate = $Issuer.Trim().TrimEnd('/')
        foreach ($trusted in @($TrustedIssuer)) {
            if ([string]::Equals($candidate, $trusted.Trim().TrimEnd('/'), [System.StringComparison]::OrdinalIgnoreCase)) {
                return $true
            }
        }

        return $false
    }

    function Resolve-FsuTrustedClaimIssuer {
        <#
            Resolves the issuer that actually vouches for a single claim,
            rather than for the claims bag as a whole. A claim is trusted
            either because its own Claim.Issuer is on the allowlist, or
            because an 'iss'-type claim co-asserted with it (sharing the
            same Claim.Issuer metadata -- i.e. the same underlying
            token/source) names a trusted issuer as its value. An 'iss'
            claim carried by a *different* source does not vouch for this
            claim: that is exactly the claims-bag mixing this function
            exists to prevent.
        #>
        param(
            [Parameter(Mandatory)]
            [System.Security.Claims.Claim]$Claim,

            [Parameter(Mandatory)]
            [AllowEmptyCollection()]
            [string[]]$TrustedIssuer,

            [Parameter(Mandatory)]
            [AllowEmptyCollection()]
            [System.Security.Claims.Claim[]]$IssuerClaim
        )

        if (Test-FsuIssuerTrusted -Issuer $Claim.Issuer -TrustedIssuer $TrustedIssuer) {
            return $Claim.Issuer
        }

        foreach ($issClaim in @($IssuerClaim)) {
            if ([string]::Equals([string]$issClaim.Issuer, [string]$Claim.Issuer, [System.StringComparison]::OrdinalIgnoreCase) -and
                (Test-FsuIssuerTrusted -Issuer $issClaim.Value -TrustedIssuer $TrustedIssuer)) {
                return $issClaim.Value
            }
        }

        return $null
    }

    function Get-FsuTenantFromIssuer {
        param([string]$Issuer)

        if ([string]::IsNullOrWhiteSpace($Issuer)) {
            return $null
        }

        $uri = $null
        if (-not [System.Uri]::TryCreate($Issuer, [System.UriKind]::Absolute, [ref]$uri)) {
            return $null
        }

        foreach ($segment in @($uri.AbsolutePath.Trim('/').Split('/'))) {
            $guid = [guid]::Empty
            if ([guid]::TryParse($segment, [ref]$guid)) {
                return $guid.ToString('D').ToLowerInvariant()
            }
        }

        return $null
    }

    function ConvertTo-FsuNormalizedGuid {
        param(
            [Parameter(Mandatory)]
            [string]$Value,

            [Parameter(Mandatory)]
            [string]$ErrorId,

            [string]$CorrelationId
        )

        $guid = [guid]::Empty
        if (-not [guid]::TryParse($Value, [ref]$guid)) {
            throw (Get-FsuIdentityErrorRecord -Id $ErrorId -Message 'The trusted identity did not contain a valid immutable identifier.' -CorrelationId $CorrelationId)
        }

        return $guid.ToString('D').ToLowerInvariant()
    }

    if ($null -eq $HostInvocation) {
        throw (Get-FsuIdentityErrorRecord -Id 'MissingInvocation' -Message 'Trusted PSU invocation data is required.' -CorrelationId $CorrelationId)
    }

    $surface = [string](Get-FsuInvocationProperty -InputObject $HostInvocation -Name 'Surface')
    $claimsPrincipal = Get-FsuInvocationProperty -InputObject $HostInvocation -Name 'ClaimsPrincipal'
    $hasClaimsPrincipal = $claimsPrincipal -is [System.Security.Claims.ClaimsPrincipal]
    $isNoninteractiveSurface = $surface -in @('Schedule', 'Script')

    # Per-user interactive identity mapping requires an Authentication policy. When
    # FreshservicePSUConfig omits Authentication (it is optional), that path is
    # disabled: every caller resolves as System -- and uses the system credential or
    # an app-forwarded acting-secret -- even one that carries a ClaimsPrincipal.
    if ($null -eq $Configuration.Authentication) {
        $systemName = [string](Get-FsuInvocationProperty -InputObject $HostInvocation -Name 'JobIdentityName')
        if ([string]::IsNullOrWhiteSpace($systemName)) {
            $systemName = [string](Get-FsuInvocationProperty -InputObject $HostInvocation -Name 'Identity')
        }
        if ([string]::IsNullOrWhiteSpace($systemName)) {
            $systemName = 'system'
        }
        return [PSCustomObject]@{
            PSTypeName = 'Freshservice.ExecutionPrincipal'
            PrincipalId = 'system'
            UserPrincipalName = $systemName
            ExecutionType = 'System'
            AuthenticationType = 'System'
        }
    }

    if ($isNoninteractiveSurface -and -not $hasClaimsPrincipal) {
        $jobName = [string](Get-FsuInvocationProperty -InputObject $HostInvocation -Name 'JobIdentityName')
        if ([string]::IsNullOrWhiteSpace($jobName)) {
            $jobName = 'system'
        }

        return [PSCustomObject]@{
            PSTypeName = 'Freshservice.ExecutionPrincipal'
            PrincipalId = 'system'
            UserPrincipalName = $jobName
            ExecutionType = 'System'
            AuthenticationType = 'System'
        }
    }

    if (-not $hasClaimsPrincipal) {
        $identityName = Get-FsuInvocationProperty -InputObject $HostInvocation -Name 'Identity'
        if ($surface -eq 'Api' -and -not [string]::IsNullOrWhiteSpace([string]$identityName)) {
            return [PSCustomObject]@{
                PSTypeName = 'Freshservice.ExecutionPrincipal'
                PrincipalId = 'system'
                UserPrincipalName = [string]$identityName
                ExecutionType = 'System'
                AuthenticationType = 'System'
            }
        }

        throw (Get-FsuIdentityErrorRecord -Id 'Unauthenticated' -Message 'Interactive execution requires a trusted PSU identity and is denied.' -CorrelationId $CorrelationId)
    }

    # Documented Entra maps from ARCHITECTURE.md §6. Claim candidates live
    # only in this adapter so commands cannot hard-code provider types.
    $samlObjectIdType = @('http://schemas.microsoft.com/identity/claims/objectidentifier')
    $oidcObjectIdType = @('oid')
    $samlTenantType = @('http://schemas.microsoft.com/identity/claims/tenantid')
    $oidcTenantType = @('tid')
    $samlNameType = @('http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name')
    $oidcNameType = @('preferred_username', 'upn')
    $issuerClaimType = @('iss', 'http://schemas.microsoft.com/identity/claims/identityprovider')

    $samlObjectClaims = @(Get-FsuClaim -ClaimsPrincipal $claimsPrincipal -Type $samlObjectIdType)
    $oidcObjectClaims = @(Get-FsuClaim -ClaimsPrincipal $claimsPrincipal -Type $oidcObjectIdType)
    $objectIdClaims = @($samlObjectClaims) + @($oidcObjectClaims)
    if ($objectIdClaims.Count -eq 0) {
        throw (Get-FsuIdentityErrorRecord -Id 'MissingObjectId' -Message 'The trusted identity did not include an immutable object identifier.' -CorrelationId $CorrelationId)
    }

    # Trust is bound to the object-id claim actually used for PrincipalId,
    # not to "any trusted issuer anywhere in the claims bag": a claim is
    # only a candidate if its own issuer (Claim.Issuer, or a co-asserted
    # 'iss' claim -- see Resolve-FsuTrustedClaimIssuer) is on the allowlist.
    # An object-id claim carried by an untrusted source is never used, even
    # if some other claim in the same principal happens to be trusted.
    $issuerClaims = @(Get-FsuClaim -ClaimsPrincipal $claimsPrincipal -Type $issuerClaimType)
    $trustedIssuers = @($Configuration.Authentication.TrustedIssuers)

    $trustedObjectClaims = [System.Collections.Generic.List[System.Security.Claims.Claim]]::new()
    $trustedIssuer = $null
    foreach ($claim in $objectIdClaims) {
        $resolvedIssuer = Resolve-FsuTrustedClaimIssuer -Claim $claim -TrustedIssuer $trustedIssuers -IssuerClaim $issuerClaims
        if ($null -ne $resolvedIssuer) {
            $null = $trustedObjectClaims.Add($claim)
            if ($null -eq $trustedIssuer) {
                $trustedIssuer = $resolvedIssuer
            }
        }
    }

    if ($trustedObjectClaims.Count -eq 0) {
        throw (Get-FsuIdentityErrorRecord -Id 'UntrustedIssuer' -Message 'The trusted identity issuer is not in the configured issuer allowlist.' -CorrelationId $CorrelationId)
    }

    $objectValues = @(Get-FsuDistinctClaimValue -Claim @($trustedObjectClaims))
    if ($objectValues.Count -gt 1) {
        throw (Get-FsuIdentityErrorRecord -Id 'ConflictingIdentity' -Message 'The trusted identity contained conflicting immutable object identifiers.' -CorrelationId $CorrelationId)
    }

    # Tenant and name claims are read only from the same trusted issuer that
    # vouched for the object-id claim above -- a tenant or name claim
    # carried by a different (even if separately trusted) issuer must not
    # be mixed into this principal.
    $samlTenantClaims = @(Get-FsuClaim -ClaimsPrincipal $claimsPrincipal -Type $samlTenantType)
    $oidcTenantClaims = @(Get-FsuClaim -ClaimsPrincipal $claimsPrincipal -Type $oidcTenantType)
    $tenantClaims = @($samlTenantClaims) + @($oidcTenantClaims)
    $trustedTenantClaims = @($tenantClaims | Where-Object {
            $resolvedIssuer = Resolve-FsuTrustedClaimIssuer -Claim $_ -TrustedIssuer $trustedIssuers -IssuerClaim $issuerClaims
            $null -ne $resolvedIssuer -and [string]::Equals($resolvedIssuer.Trim().TrimEnd('/'), $trustedIssuer.Trim().TrimEnd('/'), [System.StringComparison]::OrdinalIgnoreCase)
        })
    $tenantValues = @(Get-FsuDistinctClaimValue -Claim $trustedTenantClaims)

    if ($tenantValues.Count -gt 1) {
        throw (Get-FsuIdentityErrorRecord -Id 'ConflictingTenant' -Message 'The trusted identity contained conflicting tenant identifiers.' -CorrelationId $CorrelationId)
    }

    $tenantValue = $null
    if ($tenantValues.Count -eq 1) {
        $tenantValue = $tenantValues[0]
    } else {
        $tenantValue = Get-FsuTenantFromIssuer -Issuer $trustedIssuer
    }

    if ([string]::IsNullOrWhiteSpace($tenantValue)) {
        throw (Get-FsuIdentityErrorRecord -Id 'MissingTenant' -Message 'The trusted identity did not include a tenant identifier.' -CorrelationId $CorrelationId)
    }

    $normalizedTenant = ConvertTo-FsuNormalizedGuid -Value $tenantValue -ErrorId 'MissingTenant' -CorrelationId $CorrelationId
    $trustedTenants = @($Configuration.Authentication.TrustedTenants | ForEach-Object {
            $parsed = [guid]::Empty
            if ([guid]::TryParse($_, [ref]$parsed)) {
                $parsed.ToString('D').ToLowerInvariant()
            } else {
                [string]$_
            }
        })
    if ($normalizedTenant -notin $trustedTenants) {
        throw (Get-FsuIdentityErrorRecord -Id 'UntrustedTenant' -Message 'The trusted identity tenant is not in the configured tenant allowlist.' -CorrelationId $CorrelationId)
    }

    $authenticationType = if ($trustedObjectClaims[0].Type -in $samlObjectIdType) { 'SAML' } else { 'OIDC' }
    $allowedTypes = @($Configuration.Authentication.AllowedTypes)
    $typeAllowed = $false
    foreach ($allowed in $allowedTypes) {
        if ([string]::Equals([string]$allowed, $authenticationType, [System.StringComparison]::OrdinalIgnoreCase)) {
            $typeAllowed = $true
            break
        }
    }
    if (-not $typeAllowed) {
        throw (Get-FsuIdentityErrorRecord -Id 'AuthenticationTypeNotAllowed' -Message 'The trusted identity used an authentication type that is not allowed.' -CorrelationId $CorrelationId)
    }

    $nameTypes = if ($authenticationType -eq 'SAML') { $samlNameType } else { $oidcNameType }
    $nameCandidates = @(Get-FsuClaim -ClaimsPrincipal $claimsPrincipal -Type $nameTypes)
    $trustedNameClaims = @($nameCandidates | Where-Object {
            $resolvedIssuer = Resolve-FsuTrustedClaimIssuer -Claim $_ -TrustedIssuer $trustedIssuers -IssuerClaim $issuerClaims
            $null -ne $resolvedIssuer -and [string]::Equals($resolvedIssuer.Trim().TrimEnd('/'), $trustedIssuer.Trim().TrimEnd('/'), [System.StringComparison]::OrdinalIgnoreCase)
        })
    $nameValues = @(Get-FsuDistinctClaimValue -Claim $trustedNameClaims)
    if ($nameValues.Count -eq 0) {
        throw (Get-FsuIdentityErrorRecord -Id 'MissingUsername' -Message 'The trusted identity did not include a readable username.' -CorrelationId $CorrelationId)
    }
    if ($nameValues.Count -gt 1) {
        throw (Get-FsuIdentityErrorRecord -Id 'ConflictingUsername' -Message 'The trusted identity contained conflicting usernames.' -CorrelationId $CorrelationId)
    }

    $normalizedObjectId = ConvertTo-FsuNormalizedGuid -Value $objectValues[0] -ErrorId 'InvalidObjectId' -CorrelationId $CorrelationId

    return [PSCustomObject]@{
        PSTypeName = 'Freshservice.ExecutionPrincipal'
        PrincipalId = 'entra:{0}:{1}' -f $normalizedTenant, $normalizedObjectId
        UserPrincipalName = $nameValues[0]
        ExecutionType = 'Interactive'
        AuthenticationType = $authenticationType
    }
}
