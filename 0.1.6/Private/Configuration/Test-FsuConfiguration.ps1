function Test-FsuConfiguration {
    <#
    .SYNOPSIS
        Validates an in-memory FreshservicePSUConfig hashtable (ARCHITECTURE.md §7).

    .DESCRIPTION
        Pure validation of a hashtable already supplied by the caller, or of
        an object that already carries the 'Freshservice.Configuration'
        (or nested 'Freshservice.Configuration.Authentication') type name.
        A type name is not evidence of provenance -- PSTypeNames is
        attacker-settable on any PSCustomObject, and $Config can arrive from
        caller scope -- so an already-typed object is re-shaped into a plain
        dictionary and run through every check below rather than being
        trusted and returned unchecked. This function does not read the
        trusted PSU variable, does not resolve secrets, and does not touch
        identity. Every failure mode throws a normalized terminating error
        (fail closed); a partially-valid object is never returned. On
        success, returns an immutable-in-practice 'Freshservice.Configuration'
        object.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        $Config,

        [string]$CorrelationId
    )

    function Get-FsuConfigurationErrorRecord {
        param(
            [Parameter(Mandatory)]
            [string]$Id,

            [Parameter(Mandatory)]
            [string]$Message,

            [string]$CorrelationId
        )

        New-FsuErrorRecord -ErrorId "FreshservicePSU.Settings.$Id" -Message $Message -Category InvalidData -CorrelationId $CorrelationId
    }

    function Get-FsuTypedConfigPropertyValue {
        param($Object, [Parameter(Mandatory)][string]$Name)

        if ($null -eq $Object) {
            return $null
        }
        $property = $Object.PSObject.Properties[$Name]
        if ($null -eq $property) {
            return $null
        }
        return $property.Value
    }

    # Re-shape an already-typed 'Freshservice.Configuration' object into a
    # plain hashtable so it runs through the exact same checks as a raw
    # hashtable, instead of being accepted on the strength of its type name.
    if ($null -ne $Config -and $Config -isnot [System.Collections.IDictionary]) {
        $configTypeNames = @($Config.PSObject.TypeNames)
        if ($configTypeNames -contains 'Freshservice.Configuration') {
            $authSource = Get-FsuTypedConfigPropertyValue -Object $Config -Name 'Authentication'
            $authHash = @{
                AllowedTypes = @(Get-FsuTypedConfigPropertyValue -Object $authSource -Name 'AllowedTypes')
                TrustedTenants = @(Get-FsuTypedConfigPropertyValue -Object $authSource -Name 'TrustedTenants')
                TrustedIssuers = @(Get-FsuTypedConfigPropertyValue -Object $authSource -Name 'TrustedIssuers')
            }

            $usersSource = Get-FsuTypedConfigPropertyValue -Object $Config -Name 'Users'
            $usersHash = @{}
            if ($usersSource -is [System.Collections.IDictionary] -or $usersSource -is [System.Collections.Generic.IDictionary[string, string]]) {
                foreach ($key in @($usersSource.Keys)) {
                    $usersHash[[string]$key] = [string]$usersSource[$key]
                }
            }

            $Config = @{
                SchemaVersion = Get-FsuTypedConfigPropertyValue -Object $Config -Name 'SchemaVersion'
                Stage = Get-FsuTypedConfigPropertyValue -Object $Config -Name 'Stage'
                Tenant = Get-FsuTypedConfigPropertyValue -Object $Config -Name 'Tenant'
                BaseUri = Get-FsuTypedConfigPropertyValue -Object $Config -Name 'BaseUri'
                DefaultSecret = Get-FsuTypedConfigPropertyValue -Object $Config -Name 'DefaultSecret'
                AllowSystemFallback = Get-FsuTypedConfigPropertyValue -Object $Config -Name 'AllowSystemFallback'
                Authentication = $authHash
                Users = $usersHash
            }
        }
    }

    if ($null -eq $Config -or $Config -isnot [System.Collections.IDictionary]) {
        throw (Get-FsuConfigurationErrorRecord -Id 'NotADictionary' -Message 'FreshservicePSUConfig must be a dictionary/hashtable.' -CorrelationId $CorrelationId)
    }

    # Allowed = every property the schema recognizes; Required = the subset that
    # must be present. BaseUri, Authentication, and Users are OPTIONAL: BaseUri is
    # always https://<Tenant>.freshservice.com/api/v2/ and is derived from Tenant,
    # and the Authentication/Users identity model is only used by the interactive
    # per-user path -- unattended (job) callers and the app-forwarded acting-secret
    # path never need it. A present-but-invalid optional property still fails closed.
    $topLevelSchema = @('SchemaVersion', 'Stage', 'Tenant', 'BaseUri', 'DefaultSecret', 'AllowSystemFallback', 'Authentication', 'Users')
    $requiredTopLevel = @('SchemaVersion', 'Stage', 'Tenant', 'DefaultSecret', 'AllowSystemFallback')
    $allowedAuthentication = @('AllowedTypes', 'TrustedTenants', 'TrustedIssuers')

    # Case-insensitive key collection so an ordered/case-sensitive dictionary
    # is checked the same way a normal PowerShell hashtable would be.
    $topLevelKeys = @($Config.Keys | ForEach-Object { [string]$_ })

    # A case-sensitive dictionary can hold both 'Stage' and 'stage'. Both pass
    # the case-insensitive allowlist and required-key checks below, and then
    # only the canonically-cased one is ever read — so the other silently does
    # nothing. Security-sensitive configuration that is ambiguous must fail
    # rather than pick a winner. Users keys get the same treatment further down.
    function Get-FsuCollidingKey {
        param([Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Key)

        # Callers must wrap this in @(): PowerShell unrolls a returned empty
        # array to $null, and .Count on $null is a strict-mode error.
        $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
        return @($Key | Where-Object { -not $seen.Add($_) })
    }

    $collidingTopLevel = @(Get-FsuCollidingKey -Key $topLevelKeys)
    if ($collidingTopLevel.Count -gt 0) {
        throw (Get-FsuConfigurationErrorRecord -Id 'AmbiguousProperty' -Message "FreshservicePSUConfig property names must be unique, including case-insensitively: $($collidingTopLevel -join ', ')." -CorrelationId $CorrelationId)
    }

    $unknownTopLevel = @($topLevelKeys | Where-Object { $_ -notin $topLevelSchema })
    if ($unknownTopLevel.Count -gt 0) {
        throw (Get-FsuConfigurationErrorRecord -Id 'UnknownProperty' -Message "Unknown FreshservicePSUConfig properties: $($unknownTopLevel -join ', ')." -CorrelationId $CorrelationId)
    }

    $missingTopLevel = @($requiredTopLevel | Where-Object { $_ -notin $topLevelKeys })
    if ($missingTopLevel.Count -gt 0) {
        throw (Get-FsuConfigurationErrorRecord -Id 'MissingProperty' -Message "FreshservicePSUConfig is missing required properties: $($missingTopLevel -join ', ')." -CorrelationId $CorrelationId)
    }

    if ($Config['SchemaVersion'] -isnot [string] -or $Config['SchemaVersion'] -ne '1.0') {
        throw (Get-FsuConfigurationErrorRecord -Id 'UnsupportedSchemaVersion' -Message "FreshservicePSUConfig.SchemaVersion must be '1.0'." -CorrelationId $CorrelationId)
    }

    if ($Config['Stage'] -isnot [string] -or $Config['Stage'] -notin @('Prod', 'Dev')) {
        throw (Get-FsuConfigurationErrorRecord -Id 'InvalidStage' -Message "FreshservicePSUConfig.Stage must be 'Prod' or 'Dev'." -CorrelationId $CorrelationId)
    }

    if ($Config['Tenant'] -isnot [string] -or [string]::IsNullOrWhiteSpace($Config['Tenant'])) {
        throw (Get-FsuConfigurationErrorRecord -Id 'InvalidTenant' -Message 'FreshservicePSUConfig.Tenant must be a non-empty string.' -CorrelationId $CorrelationId)
    }

    # Tenant is the Freshservice subdomain label (e.g. 'acme'). It must be a single
    # DNS label so the derived host below cannot be hijacked by a dotted or
    # scheme-bearing value like 'acme.attacker.com' or 'https://evil'.
    if ($Config['Tenant'] -notmatch '^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?$') {
        throw (Get-FsuConfigurationErrorRecord -Id 'InvalidTenant' -Message "FreshservicePSUConfig.Tenant must be a single Freshservice subdomain label (letters, digits, hyphens), e.g. 'acme'." -CorrelationId $CorrelationId)
    }

    # BaseUri is always https://<tenant>.freshservice.com/api/v2/ and is derived
    # from Tenant, so it is not something operators set. It remains OPTIONAL in the
    # schema for a deliberate override (e.g. a vanity domain); when supplied it is
    # validated below with the same fail-closed checks and used as-is, otherwise it
    # is computed. Configuration integrity is security-sensitive because it selects
    # the tenant (ARCHITECTURE.md §7).
    $expectedHost = '{0}.freshservice.com' -f $Config['Tenant']
    $resolvedBaseUri = 'https://{0}/api/v2/' -f $expectedHost

    if ($topLevelKeys -contains 'BaseUri') {
        if ($Config['BaseUri'] -isnot [string] -or [string]::IsNullOrWhiteSpace($Config['BaseUri'])) {
            throw (Get-FsuConfigurationErrorRecord -Id 'InvalidBaseUri' -Message 'FreshservicePSUConfig.BaseUri must be a non-empty string.' -CorrelationId $CorrelationId)
        }

        $parsedBaseUri = $null
        if (-not [System.Uri]::TryCreate($Config['BaseUri'], [System.UriKind]::Absolute, [ref]$parsedBaseUri)) {
            throw (Get-FsuConfigurationErrorRecord -Id 'InvalidBaseUri' -Message "FreshservicePSUConfig.BaseUri '$($Config['BaseUri'])' is not a valid absolute URI." -CorrelationId $CorrelationId)
        }

        if ($parsedBaseUri.Scheme -ne 'https') {
            throw (Get-FsuConfigurationErrorRecord -Id 'BaseUriNotHttps' -Message "FreshservicePSUConfig.BaseUri '$($Config['BaseUri'])' must use HTTPS." -CorrelationId $CorrelationId)
        }

        # The path must be exactly '/api/v2/' — not merely contain it. A substring
        # check accepts 'https://attacker.example.com/decoy/api/v2/'.
        if ($parsedBaseUri.AbsolutePath -ne '/api/v2/') {
            throw (Get-FsuConfigurationErrorRecord -Id 'BaseUriNotV2' -Message "FreshservicePSUConfig.BaseUri '$($Config['BaseUri'])' must have the exact path '/api/v2/'." -CorrelationId $CorrelationId)
        }

        # An exact path is not enough: 'https://attacker.example.com/api/v2/'
        # satisfies it while pointing every request at another host, so the host
        # must be the configured tenant's.
        if ($parsedBaseUri.Host -ne $expectedHost) {
            throw (Get-FsuConfigurationErrorRecord -Id 'BaseUriHostMismatch' -Message "FreshservicePSUConfig.BaseUri host '$($parsedBaseUri.Host)' does not match the configured tenant; expected '$expectedHost'." -CorrelationId $CorrelationId)
        }

        # Userinfo can smuggle credentials into a URI, and a query or fragment on a
        # base URI silently alters every request built from it.
        if ($parsedBaseUri.UserInfo -or $parsedBaseUri.Query -or $parsedBaseUri.Fragment) {
            throw (Get-FsuConfigurationErrorRecord -Id 'BaseUriHasExtraComponents' -Message 'FreshservicePSUConfig.BaseUri must not carry userinfo, a query string, or a fragment.' -CorrelationId $CorrelationId)
        }

        $resolvedBaseUri = [string]$Config['BaseUri']
    }

    if ($Config['DefaultSecret'] -isnot [string] -or [string]::IsNullOrWhiteSpace($Config['DefaultSecret'])) {
        throw (Get-FsuConfigurationErrorRecord -Id 'InvalidDefaultSecret' -Message 'FreshservicePSUConfig.DefaultSecret must be a non-empty secret name.' -CorrelationId $CorrelationId)
    }

    if ($Config['AllowSystemFallback'] -isnot [bool]) {
        throw (Get-FsuConfigurationErrorRecord -Id 'InvalidAllowSystemFallback' -Message 'FreshservicePSUConfig.AllowSystemFallback must be a boolean.' -CorrelationId $CorrelationId)
    }

    # Authentication and Users are OPTIONAL: they configure the interactive
    # per-user identity model, which unattended (job) callers and the
    # app-forwarded acting-secret path never use. When present they are validated
    # in full and fail closed; when absent, per-user interactive mapping is simply
    # unavailable (callers resolve to the system credential or a forwarded acting
    # secret), and Authentication on the resulting object is $null.
    $authenticationResult = $null
    if ($topLevelKeys -contains 'Authentication') {
        $authentication = $Config['Authentication']
        if ($null -eq $authentication -or $authentication -isnot [System.Collections.IDictionary]) {
            throw (Get-FsuConfigurationErrorRecord -Id 'InvalidAuthentication' -Message 'FreshservicePSUConfig.Authentication must be a dictionary.' -CorrelationId $CorrelationId)
        }

        $authenticationKeys = @($authentication.Keys | ForEach-Object { [string]$_ })

        $collidingAuthentication = @(Get-FsuCollidingKey -Key $authenticationKeys)
        if ($collidingAuthentication.Count -gt 0) {
            throw (Get-FsuConfigurationErrorRecord -Id 'AmbiguousAuthenticationProperty' -Message "FreshservicePSUConfig.Authentication property names must be unique, including case-insensitively: $($collidingAuthentication -join ', ')." -CorrelationId $CorrelationId)
        }

        $unknownAuthentication = @($authenticationKeys | Where-Object { $_ -notin $allowedAuthentication })
        if ($unknownAuthentication.Count -gt 0) {
            throw (Get-FsuConfigurationErrorRecord -Id 'UnknownAuthenticationProperty' -Message "Unknown FreshservicePSUConfig.Authentication properties: $($unknownAuthentication -join ', ')." -CorrelationId $CorrelationId)
        }

        # When Authentication is supplied it must be complete: a partial identity
        # policy that trusts nothing (or an unstated dimension) is a configuration
        # error, not a silently-narrowed trust set.
        $missingAuthentication = @($allowedAuthentication | Where-Object { $_ -notin $authenticationKeys })
        if ($missingAuthentication.Count -gt 0) {
            throw (Get-FsuConfigurationErrorRecord -Id 'MissingAuthenticationProperty' -Message "FreshservicePSUConfig.Authentication is missing required properties: $($missingAuthentication -join ', ')." -CorrelationId $CorrelationId)
        }

        foreach ($listName in @('AllowedTypes', 'TrustedTenants', 'TrustedIssuers')) {
            # These three lists decide which identities the module will ever trust,
            # so a null-only check is not enough — a bare string 'SAML' would pass
            # it and then behave as an unintended collection, and an empty list
            # would trust nothing while still reporting valid configuration.
            $value = $authentication[$listName]
            if ($null -eq $value -or $value -is [string] -or $value -isnot [System.Collections.IEnumerable]) {
                throw (Get-FsuConfigurationErrorRecord -Id "InvalidAuthentication$listName" -Message "FreshservicePSUConfig.Authentication.$listName must be an array." -CorrelationId $CorrelationId)
            }

            $items = @($value)
            if ($items.Count -eq 0) {
                throw (Get-FsuConfigurationErrorRecord -Id "EmptyAuthentication$listName" -Message "FreshservicePSUConfig.Authentication.$listName must contain at least one entry." -CorrelationId $CorrelationId)
            }

            foreach ($item in $items) {
                if ($item -isnot [string] -or [string]::IsNullOrWhiteSpace($item)) {
                    throw (Get-FsuConfigurationErrorRecord -Id "InvalidAuthentication$listName" -Message "FreshservicePSUConfig.Authentication.$listName entries must be non-empty strings." -CorrelationId $CorrelationId)
                }
            }
        }

        # AllowedTypes names authentication mechanisms the module implements;
        # anything else is a configuration error, not a mechanism to attempt.
        $unsupportedTypes = @($authentication['AllowedTypes'] | Where-Object { $_ -notin @('SAML', 'OIDC') })
        if ($unsupportedTypes.Count -gt 0) {
            throw (Get-FsuConfigurationErrorRecord -Id 'UnsupportedAuthenticationType' -Message "FreshservicePSUConfig.Authentication.AllowedTypes supports only 'SAML' and 'OIDC'; found: $($unsupportedTypes -join ', ')." -CorrelationId $CorrelationId)
        }

        # A token's issuer is compared against these values, so a non-absolute or
        # non-HTTPS entry can never match a real issuer.
        foreach ($issuer in @($authentication['TrustedIssuers'])) {
            $parsedIssuer = $null
            if (-not [System.Uri]::TryCreate($issuer, [System.UriKind]::Absolute, [ref]$parsedIssuer) -or $parsedIssuer.Scheme -ne 'https') {
                throw (Get-FsuConfigurationErrorRecord -Id 'InvalidTrustedIssuer' -Message "FreshservicePSUConfig.Authentication.TrustedIssuers entry '$issuer' must be an absolute HTTPS URI." -CorrelationId $CorrelationId)
            }
        }

        $authenticationResult = [PSCustomObject]@{
            PSTypeName = 'Freshservice.Configuration.Authentication'
            AllowedTypes = @($authentication['AllowedTypes'])
            TrustedTenants = @($authentication['TrustedTenants'])
            TrustedIssuers = @($authentication['TrustedIssuers'])
        }
    }

    $usersResult = [System.Collections.Generic.Dictionary[string, string]]::new()
    if ($topLevelKeys -contains 'Users') {
        $users = $Config['Users']
        if ($null -eq $users -or $users -isnot [System.Collections.IDictionary]) {
            throw (Get-FsuConfigurationErrorRecord -Id 'InvalidUsers' -Message 'FreshservicePSUConfig.Users must be a dictionary.' -CorrelationId $CorrelationId)
        }

        $userKeys = @($users.Keys | ForEach-Object { [string]$_ })

        $collidingKeys = @(Get-FsuCollidingKey -Key $userKeys)
        if ($collidingKeys.Count -gt 0) {
            throw (Get-FsuConfigurationErrorRecord -Id 'DuplicateUserKey' -Message "FreshservicePSUConfig.Users keys must be unique, including case-insensitively: $($collidingKeys -join ', ')." -CorrelationId $CorrelationId)
        }

        foreach ($userKey in $userKeys) {
            $secretName = $users[$userKey]
            if ($secretName -isnot [string] -or [string]::IsNullOrWhiteSpace($secretName)) {
                throw (Get-FsuConfigurationErrorRecord -Id 'InvalidUserSecret' -Message "FreshservicePSUConfig.Users['$userKey'] must map to a non-empty secret name." -CorrelationId $CorrelationId)
            }
            $usersResult[[string]$userKey] = [string]$users[$userKey]
        }
    }

    $result = [PSCustomObject]@{
        PSTypeName = 'Freshservice.Configuration'
        SchemaVersion = [string]$Config['SchemaVersion']
        Stage = [string]$Config['Stage']
        Tenant = [string]$Config['Tenant']
        BaseUri = $resolvedBaseUri
        DefaultSecret = [string]$Config['DefaultSecret']
        AllowSystemFallback = [bool]$Config['AllowSystemFallback']
        Authentication = $authenticationResult
        Users = [System.Collections.ObjectModel.ReadOnlyDictionary[string, string]]::new($usersResult)
    }

    return $result
}
