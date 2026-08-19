function New-FsuValidConfigHashtable {
    [System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Test fixture builder; no system state is changed.')]
    param(
        [string]$Stage = 'Prod',
        [bool]$AllowSystemFallback = $true,
        [string[]]$AllowedTypes = @('SAML', 'OIDC')
    )

    $tenantId = '11111111-1111-1111-1111-111111111111'
    return @{
        SchemaVersion = '1.0'
        Stage = $Stage
        Tenant = 'acme'
        BaseUri = 'https://acme.freshservice.com/api/v2/'
        DefaultSecret = "FreshService.System.$Stage"
        AllowSystemFallback = $AllowSystemFallback
        Authentication = @{
            AllowedTypes = @($AllowedTypes)
            TrustedTenants = @($tenantId)
            TrustedIssuers = @(
                "https://sts.windows.net/$tenantId/"
                "https://login.microsoftonline.com/$tenantId/v2.0"
            )
        }
        Users = @{
            "entra:${tenantId}:aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa" = "FreshService.Alice.$Stage"
        }
    }
}

function New-FsuTestClaimsPrincipal {
    [System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Test fixture builder; no system state is changed.')]
    param(
        [hashtable]$Claim = @{},
        [string]$Issuer = 'https://sts.windows.net/11111111-1111-1111-1111-111111111111/'
    )

    $claimList = [System.Collections.Generic.List[System.Security.Claims.Claim]]::new()
    foreach ($key in $Claim.Keys) {
        foreach ($value in @($Claim[$key])) {
            $null = $claimList.Add([System.Security.Claims.Claim]::new($key, [string]$value, [string]$null, $Issuer))
        }
    }

    $identity = [System.Security.Claims.ClaimsIdentity]::new($claimList, 'AuthenticationTypes.Federation')
    return [System.Security.Claims.ClaimsPrincipal]::new($identity)
}

function New-FsuTestHostInvocation {
    [System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Test fixture builder; no system state is changed.')]
    param(
        [string]$Surface = 'Api',
        $ClaimsPrincipal,
        [string]$Identity,
        [string]$User,
        [string]$JobIdentityName,
        [string[]]$Roles = @()
    )

    return [PSCustomObject]@{
        PSTypeName = 'Freshservice.HostInvocation'
        Surface = $Surface
        Identity = $Identity
        User = $User
        ClaimsPrincipal = $ClaimsPrincipal
        JobIdentityName = $JobIdentityName
        Roles = @($Roles)
    }
}

function New-FsuSamlClaimsPrincipal {
    [System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Test fixture builder; no system state is changed.')]
    param(
        [string]$ObjectId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        [string]$TenantId = '11111111-1111-1111-1111-111111111111',
        [string]$Name = 'alice@contoso.com',
        [string]$Issuer = 'https://sts.windows.net/11111111-1111-1111-1111-111111111111/'
    )

    return New-FsuTestClaimsPrincipal -Issuer $Issuer -Claim @{
        'http://schemas.microsoft.com/identity/claims/objectidentifier' = $ObjectId
        'http://schemas.microsoft.com/identity/claims/tenantid' = $TenantId
        'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name' = $Name
    }
}

function New-FsuOidcClaimsPrincipal {
    [System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Test fixture builder; no system state is changed.')]
    param(
        [string]$ObjectId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        [string]$TenantId = '11111111-1111-1111-1111-111111111111',
        [string]$Name = 'alice@contoso.com',
        [string]$Issuer = 'https://login.microsoftonline.com/11111111-1111-1111-1111-111111111111/v2.0'
    )

    return New-FsuTestClaimsPrincipal -Issuer $Issuer -Claim @{
        oid = $ObjectId
        tid = $TenantId
        preferred_username = $Name
        iss = $Issuer
    }
}

function New-FsuMixedIssuerClaimsPrincipal {
    [System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Test fixture builder; no system state is changed.')]
    param(
        [string]$ObjectId = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        [string]$TenantId = '11111111-1111-1111-1111-111111111111',
        [string]$Name = 'mallory@evil.example.com',
        [string]$TrustedIssuer = 'https://sts.windows.net/11111111-1111-1111-1111-111111111111/',
        [string]$ObjectIdClaimSource = 'untrusted-claim-source',
        [string]$TenantClaimSource = 'legit-claim-source'
    )

    # The object-id and name claims are attributed to 'untrusted-claim-source'.
    # A separate 'iss' claim names the trusted issuer but is co-asserted
    # with the tenant claim under 'legit-claim-source' -- a different
    # Claim.Issuer than the object-id and name claims. This models a
    # claims bag that mixes one trusted assertion (iss + tid) with identity
    # claims (oid, name) that did not actually come from that issuer.
    $claims = [System.Collections.Generic.List[System.Security.Claims.Claim]]::new()
    $null = $claims.Add([System.Security.Claims.Claim]::new('http://schemas.microsoft.com/identity/claims/objectidentifier', $ObjectId, [string]$null, $ObjectIdClaimSource))
    $null = $claims.Add([System.Security.Claims.Claim]::new('http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name', $Name, [string]$null, $ObjectIdClaimSource))
    $null = $claims.Add([System.Security.Claims.Claim]::new('iss', $TrustedIssuer, [string]$null, $TenantClaimSource))
    $null = $claims.Add([System.Security.Claims.Claim]::new('http://schemas.microsoft.com/identity/claims/tenantid', $TenantId, [string]$null, $TenantClaimSource))

    $identity = [System.Security.Claims.ClaimsIdentity]::new($claims, 'AuthenticationTypes.Federation')
    return [System.Security.Claims.ClaimsPrincipal]::new($identity)
}

function New-FsuTestSecretResolver {
    [System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Test fixture builder; no system state is changed.')]
    [System.Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'Test fixture builds synthetic secrets that are never a real credential.')]
    param(
        [hashtable]$Secret = @{},
        [string]$Plaintext = 'test-api-key-DO-NOT-LEAK-9f3c'
    )

    $store = @{}
    foreach ($key in $Secret.Keys) {
        $store[$key] = $Secret[$key]
    }

    $defaultPlaintext = $Plaintext
    return {
        param($Name)
        if ($store.ContainsKey($Name)) {
            return $store[$Name]
        }
        return ConvertTo-SecureString -String $defaultPlaintext -AsPlainText -Force
    }.GetNewClosure()
}

function New-FsuTestContext {
    [System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Test fixture builder; no system state is changed.')]
    [System.Diagnostics.CodeAnalysis.SuppressMessage('PSAvoidUsingConvertToSecureStringWithPlainText', '', Justification = 'Test fixture builds a synthetic API key that is never a real credential.')]
    param(
        [string]$Stage = 'Prod',
        [string]$Tenant = 'acme',
        [string]$BaseUri = 'https://acme.freshservice.com/api/v2/',
        [string]$ApiKey = 'test-api-key-DO-NOT-LEAK-pipe',
        [string]$AccountType = 'User',
        [string]$SecretName = 'FreshService.Alice.Prod',
        [string]$PrincipalId = 'entra:11111111-1111-1111-1111-111111111111:aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        [string]$ExecutionType = 'Interactive',
        [string]$CorrelationId = 'corr-pipe-1',
        $RetryPolicy
    )

    if ($null -eq $RetryPolicy) {
        $RetryPolicy = New-FsuRetryPolicy -Mode Interactive
    }

    return [PSCustomObject]@{
        PSTypeName = 'Freshservice.Context'
        Stage = $Stage
        Tenant = $Tenant
        BaseUri = $BaseUri
        Principal = [PSCustomObject]@{
            PSTypeName = 'Freshservice.ExecutionPrincipal'
            PrincipalId = $PrincipalId
            UserPrincipalName = 'alice@contoso.com'
            ExecutionType = $ExecutionType
            AuthenticationType = 'SAML'
        }
        Credential = [PSCustomObject]@{
            PSTypeName = 'Freshservice.ResolvedCredential'
            CredentialType = $AccountType
            SecretName = $SecretName
            Secret = (ConvertTo-SecureString -String $ApiKey -AsPlainText -Force)
            UsedFallback = $false
        }
        RetryPolicy = $RetryPolicy
        CorrelationId = $CorrelationId
    }
}

function New-FsuCannedHttpResponse {
    [System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Test fixture builder; no system state is changed.')]
    param(
        [int]$StatusCode = 200,
        [string]$Content = '',
        [hashtable]$Header = @{}
    )

    return [PSCustomObject]@{
        PSTypeName = 'Freshservice.Http.RawResponse'
        StatusCode = $StatusCode
        ReasonPhrase = 'canned'
        Header = $Header
        Content = $Content
    }
}

function New-FsuScriptedTransport {
    [System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Test fixture builder; no system state is changed.')]
    param(
        [Parameter(Mandatory)]
        [object[]]$Response
    )

    $state = [pscustomobject]@{
        Index = 0
        Request = [System.Collections.Generic.List[object]]::new()
    }
    $queue = @($Response)
    $transport = {
        param($Request)
        $null = $state.Request.Add($Request)
        if ($state.Index -ge $queue.Count) {
            throw "Transport queue exhausted after $($queue.Count) response(s)."
        }
        $item = $queue[$state.Index]
        $state.Index++
        if ($item -is [System.Management.Automation.ErrorRecord]) {
            throw $item
        }
        return $item
    }.GetNewClosure()

    return [pscustomobject]@{
        Transport = $transport
        State = $state
    }
}
