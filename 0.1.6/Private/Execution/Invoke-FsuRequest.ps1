function Invoke-FsuRequest {
    <#
    .SYNOPSIS
        Executes one authenticated Freshservice request through the shared pipeline.

    .DESCRIPTION
        Orchestrates URI construction, per-request Basic authentication,
        HTTP send, retry, error normalization, and a single terminal audit
        event. Tests inject -Transport, -GetTimestamp, -GetJitterFraction,
        and -Wait. The real HttpClient lives only in Send-FsuHttpRequest.
        No correlation header is sent. A timeout or 5xx on a non-idempotent
        request is an uncertain outcome, never fabricated success.

        Rate limiting is reactive, not proactive (ARCHITECTURE.md §11
        "Rate limits"). Freshservice's limit is account-wide and shared with
        consumers this module cannot observe, so its own accounting could
        never be authoritative. A request is sent; a 429 is honored by
        waiting Retry-After and retrying within the policy budget. Rate
        headers are recorded as telemetry only and gate nothing.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Context,

        [Parameter(Mandatory)]
        [ValidateSet('GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD')]
        [string]$Method,

        [string[]]$PathSegments = @(),

        [System.Collections.IDictionary]$QueryParameters,

        [uri]$Uri,

        [System.Collections.IDictionary]$Body,

        [string[]]$BoundParameterNames = @(),

        [string]$EnvelopeProperty,

        [string]$PSTypeName,

        [bool]$IsIdempotent,

        [scriptblock]$Transport,

        [scriptblock]$GetTimestamp = { [datetime]::UtcNow },

        [scriptblock]$GetJitterFraction = { Get-Random -Minimum 0.0 -Maximum 1.0 },

        [scriptblock]$Wait = { param($Seconds) Start-Sleep -Seconds $Seconds },

        [System.Threading.CancellationToken]$CancellationToken = [System.Threading.CancellationToken]::None,

        [string]$Operation = 'Invoke-FsuRequest',

        [string]$ResourceId
    )

    function Get-FsuRequestErrorRecord {
        param(
            [Parameter(Mandatory)][string]$Id,
            [Parameter(Mandatory)][string]$Message,
            [Parameter(Mandatory)][System.Management.Automation.ErrorCategory]$Category,
            [string]$CorrelationId
        )
        New-FsuErrorRecord -ErrorId $Id -Message $Message -Category $Category -CorrelationId $CorrelationId
    }

    function Test-FsuRequestCancellation {
        param(
            [System.Threading.CancellationToken]$Token,
            [string]$CorrelationId
        )
        if ($Token.IsCancellationRequested) {
            throw (Get-FsuRequestErrorRecord -Id 'FreshservicePSU.Http.Cancelled' -Message 'The request was cancelled before completion.' -Category OperationStopped -CorrelationId $CorrelationId)
        }
    }

    function Get-FsuResponseHeaderValue {
        param(
            $Header,
            [Parameter(Mandatory)][string]$Name
        )
        if ($null -eq $Header) {
            return $null
        }
        foreach ($key in @($Header.Keys)) {
            if ([string]::Equals([string]$key, $Name, [System.StringComparison]::OrdinalIgnoreCase)) {
                return [string]$Header[$key]
            }
        }
        return $null
    }

    function Get-FsuLinkHeaderValue {
        # Get-FsuResponseHeaderValue already does a case-insensitive header
        # name lookup, so a single call covers 'Link', 'link', and any
        # other casing without a redundant second lookup.
        param($Raw)
        return Get-FsuResponseHeaderValue -Header $Raw.Header -Name 'Link'
    }

    function ConvertFrom-FsuErrorPayload {
        param([string]$Content)

        $result = [PSCustomObject]@{ Code = $null; Field = $null; Message = $null }
        if ([string]::IsNullOrWhiteSpace($Content)) {
            return $result
        }

        try {
            $parsed = $Content | ConvertFrom-Json -Depth 10
        } catch {
            return $result
        }

        $errorsProperty = $parsed.PSObject.Properties['errors']
        if ($errorsProperty -and $null -ne $errorsProperty.Value) {
            $first = @($errorsProperty.Value) | Select-Object -First 1
            if ($null -ne $first) {
                if ($first.PSObject.Properties['code']) { $result.Code = [string]$first.code }
                if ($first.PSObject.Properties['field']) { $result.Field = [string]$first.field }
                if ($first.PSObject.Properties['message']) { $result.Message = [string]$first.message }
            }
        } else {
            if ($parsed.PSObject.Properties['code'] -and $parsed.code) { $result.Code = [string]$parsed.code }
            if ($parsed.PSObject.Properties['field'] -and $parsed.field) { $result.Field = [string]$parsed.field }
            if ($parsed.PSObject.Properties['message'] -and $parsed.message) { $result.Message = [string]$parsed.message }
            elseif ($parsed.PSObject.Properties['description'] -and $parsed.description) { $result.Message = [string]$parsed.description }
        }

        return $result
    }

    function Write-FsuRequestAudit {
        param(
            [Parameter(Mandatory)]$Context,
            [Parameter(Mandatory)][string]$Outcome,
            [Parameter(Mandatory)][string]$Operation,
            [string]$ResourceId,
            [Nullable[int]]$Status,
            [string]$RateLimitState
        )

        try {
            $audit = New-FsuAuditEvent `
                -CorrelationId ([string]$Context.CorrelationId) `
                -Identity ([string]$Context.Principal.PrincipalId) `
                -Stage ([string]$Context.Stage) `
                -Tenant ([string]$Context.Tenant) `
                -CredentialType ([string]$Context.Credential.CredentialType) `
                -CredentialIdentifier ([string]$Context.Credential.SecretName) `
                -Operation $Operation `
                -ResourceId $ResourceId `
                -Outcome $Outcome `
                -Status $Status `
                -FallbackUsed ([bool]$Context.Credential.UsedFallback) `
                -RateLimitState $RateLimitState
            $null = $audit | Write-FsuAuditEvent
        } catch {
            Write-Verbose 'Audit delivery failed; the operation outcome is unchanged.'
        }
    }

    function Get-FsuNormalizedFailure {
        param(
            [Parameter(Mandatory)][int]$StatusCode,
            [string]$Content,
            [string]$CorrelationId
        )

        $payload = ConvertFrom-FsuErrorPayload -Content $Content
        $knownCode = @(
            'missing_field', 'invalid_value', 'duplicate_value', 'datatype_mismatch',
            'invalid_field', 'invalid_json', 'invalid_credentials', 'access_denied',
            'require_feature', 'account_suspended', 'ssl_required', 'readonly_field',
            'password_lockout', 'password_expired', 'no_content_required',
            'inaccessible_field', 'incompatible_field', 'unsupported_authentication_type',
            'access_token_expired', 'access_token_invalid'
        )
        $recordArgs = @{
            StatusCode = $StatusCode
            CorrelationId = $CorrelationId
        }
        if ($payload.Message) { $recordArgs.Message = $payload.Message }
        if ($payload.Field) { $recordArgs.Field = $payload.Field }
        if ($payload.Code -and $payload.Code -in $knownCode) { $recordArgs.Code = $payload.Code }
        return ConvertTo-FsuNormalizedError @recordArgs
    }

    if ($null -eq $Context -or @($Context.PSObject.TypeNames) -notcontains 'Freshservice.Context') {
        throw (Get-FsuRequestErrorRecord -Id 'FreshservicePSU.Http.InvalidContext' -Message 'Invoke-FsuRequest requires a Freshservice.Context.' -Category InvalidArgument -CorrelationId '')
    }

    $correlationId = [string]$Context.CorrelationId
    $policy = $Context.RetryPolicy
    if ($null -eq $policy -or @($policy.PSObject.TypeNames) -notcontains 'Freshservice.RetryPolicy') {
        throw (Get-FsuRequestErrorRecord -Id 'FreshservicePSU.Http.InvalidRetryPolicy' -Message 'The execution context is missing a Freshservice.RetryPolicy.' -Category InvalidArgument -CorrelationId $correlationId)
    }

    if (-not $PSBoundParameters.ContainsKey('IsIdempotent')) {
        $IsIdempotent = $Method -in @('GET', 'HEAD', 'PUT', 'DELETE')
    }

    $requestUri = $Uri
    if ($null -eq $requestUri) {
        $requestUri = New-FsuUri -BaseUri ([uri]$Context.BaseUri) -PathSegments $PathSegments -QueryParameters $QueryParameters -CorrelationId $correlationId
    } else {
        $baseUri = [uri]$Context.BaseUri
        $basePath = $baseUri.AbsolutePath.TrimEnd('/') + '/'
        $sameOrigin = `
            [string]::Equals($requestUri.Scheme, $baseUri.Scheme, [System.StringComparison]::OrdinalIgnoreCase) -and `
            [string]::Equals($requestUri.Host, $baseUri.Host, [System.StringComparison]::OrdinalIgnoreCase) -and `
            $requestUri.Port -eq $baseUri.Port
        $insideBasePath = $requestUri.AbsolutePath.StartsWith($basePath, [System.StringComparison]::Ordinal)
        if (-not $sameOrigin -or -not $insideBasePath -or $requestUri.UserInfo -or $requestUri.Fragment) {
            throw (Get-FsuRequestErrorRecord -Id 'FreshservicePSU.Http.UntrustedUri' -Message 'The request URI is outside the configured tenant base URI.' -Category InvalidArgument -CorrelationId $correlationId)
        }
        $pageMatch = [regex]::Match($requestUri.Query, '[?&]page=(\d+)')
        if ($pageMatch.Success -and [int]$pageMatch.Groups[1].Value -gt 500) {
            throw (Get-FsuRequestErrorRecord -Id 'FreshservicePSU.Http.PageTooLarge' -Message "Page $($pageMatch.Groups[1].Value) exceeds the maximum supported page (500). Narrow the query instead of paging further." -Category InvalidArgument -CorrelationId $correlationId)
        }
    }

    $bodyBytes = $null
    if ($Body -and $Method -notin @('GET', 'HEAD')) {
        $bodyBytes = ConvertTo-FsuRequestBody -Fields $Body -BoundParameterNames $BoundParameterNames -CorrelationId $correlationId
    }

    Write-Verbose ("{0} {1}" -f $Method, $requestUri.GetLeftPart([System.UriPartial]::Path))

    $startedAt = & $GetTimestamp
    $attempt = 0
    $lastStatus = $null
    $rateLimitState = $null

    while ($true) {
        $attempt++
        Test-FsuRequestCancellation -Token $CancellationToken -CorrelationId $correlationId

        $raw = $null
        try {
            Test-FsuRequestCancellation -Token $CancellationToken -CorrelationId $correlationId
            $authorization = ConvertTo-FsuAuthorizationHeader -Secret $Context.Credential.Secret -CorrelationId $correlationId
            $headers = @{
                Authorization = $authorization
                Accept = 'application/json'
            }
            $raw = Send-FsuHttpRequest -Method $Method -Uri $requestUri -Header $headers -Body $bodyBytes -CancellationToken $CancellationToken -Transport $Transport -CorrelationId $correlationId
        } catch {
            $now = & $GetTimestamp

            $errorId = [string]$_.FullyQualifiedErrorId
            if ($errorId -match 'Cancelled|OperationCanceled') {
                Write-FsuRequestAudit -Context $Context -Outcome Cancellation -Operation $Operation -ResourceId $ResourceId -RateLimitState $rateLimitState
                throw
            }

            $elapsed = [math]::Max(0.0, ($now - $startedAt).TotalSeconds)
            $jitter = [double](& $GetJitterFraction)
            $decision = Get-FsuRetryDecision -Policy $policy -Attempt $attempt -ElapsedSeconds $elapsed -IsNetworkFailure -Now $now -IsIdempotent $IsIdempotent -JitterFraction $jitter
            if ($decision.ShouldRetry) {
                Test-FsuRequestCancellation -Token $CancellationToken -CorrelationId $correlationId
                & $Wait $decision.DelaySeconds
                continue
            }

            if (-not $IsIdempotent) {
                Write-FsuRequestAudit -Context $Context -Outcome Uncertain -Operation $Operation -ResourceId $ResourceId -RateLimitState $rateLimitState
                throw (Get-FsuRequestErrorRecord -Id 'FreshservicePSU.Error.UncertainOutcome' -Message 'The request may or may not have reached Freshservice. It was not retried.' -Category OperationStopped -CorrelationId $correlationId)
            }

            Write-FsuRequestAudit -Context $Context -Outcome Failure -Operation $Operation -ResourceId $ResourceId -RateLimitState $rateLimitState
            throw
        }

        $now = & $GetTimestamp

        # Rate headers are telemetry only. They report the account-wide
        # budget as of this response and cannot indicate which endpoint
        # sublimit is being approached, so nothing here gates a request:
        # a 429 does.
        $usedHeader = Get-FsuResponseHeaderValue -Header $raw.Header -Name 'X-RateLimit-Used-CurrentRequest'
        $usedCost = $null
        $parsedCost = 0
        if ($usedHeader -and [int]::TryParse($usedHeader, [ref]$parsedCost) -and $parsedCost -ge 0) {
            $usedCost = $parsedCost
        }

        $remainingHeader = Get-FsuResponseHeaderValue -Header $raw.Header -Name 'X-RateLimit-Remaining'
        $totalHeader = Get-FsuResponseHeaderValue -Header $raw.Header -Name 'X-RateLimit-Total'
        $retryAfterHeader = Get-FsuResponseHeaderValue -Header $raw.Header -Name 'Retry-After'
        $apiVersion = Get-FsuResponseHeaderValue -Header $raw.Header -Name 'X-Freshservice-Api-Version'
        $rateLimitState = 'remaining={0};used={1}' -f $remainingHeader, $usedCost
        $lastStatus = [int]$raw.StatusCode

        $parsedBody = $null
        if (-not [string]::IsNullOrWhiteSpace($raw.Content)) {
            try {
                $parsedBody = $raw.Content | ConvertFrom-Json -Depth 10
            } catch {
                # Successful responses must satisfy the documented JSON
                # contract. Error bodies are best-effort only: proxies and
                # gateways can return HTML or plain text, and the HTTP
                # status still needs to drive retry and normalization.
                if ($lastStatus -ge 200 -and $lastStatus -lt 300) {
                    Write-FsuRequestAudit -Context $Context -Outcome Failure -Operation $Operation -ResourceId $ResourceId -Status $lastStatus -RateLimitState $rateLimitState
                    throw (Get-FsuRequestErrorRecord -Id 'FreshservicePSU.Serialization.InvalidJson' -Message 'The Freshservice response was not valid JSON.' -Category InvalidData -CorrelationId $correlationId)
                }
            }
        }

        if ($lastStatus -ge 200 -and $lastStatus -lt 300) {
            $envelope = New-FsuResponse `
                -StatusCode $lastStatus `
                -CorrelationId $correlationId `
                -Body $parsedBody `
                -RateLimitTotal $(if ($totalHeader) { [int]$totalHeader } else { $null }) `
                -RateLimitRemaining $(if ($remainingHeader) { [int]$remainingHeader } else { $null }) `
                -RateLimitUsedCurrentRequest $usedCost `
                -RetryAfter $retryAfterHeader `
                -ApiVersion $apiVersion `
                -Link (Get-FsuLinkHeaderValue -Raw $raw)

            Write-FsuRequestAudit -Context $Context -Outcome Success -Operation $Operation -ResourceId $ResourceId -Status $lastStatus -RateLimitState $rateLimitState

            if ($EnvelopeProperty) {
                if (-not $PSTypeName) {
                    throw (Get-FsuRequestErrorRecord -Id 'FreshservicePSU.Http.MissingTypeName' -Message 'PSTypeName is required when EnvelopeProperty is specified.' -Category InvalidArgument -CorrelationId $correlationId)
                }
                return ConvertFrom-FsuResponse -Body $envelope.Body -EnvelopeProperty $EnvelopeProperty -PSTypeName $PSTypeName -CorrelationId $correlationId
            }

            return $envelope
        }

        $retryableStatus = $lastStatus -in @(408, 429, 500, 502, 503, 504)
        if ($retryableStatus) {
            $elapsed = [math]::Max(0.0, ($now - $startedAt).TotalSeconds)
            $jitter = [double](& $GetJitterFraction)
            # A 429 means the request was refused, not processed, so it is
            # safe to replay even a non-idempotent method.
            $retryIdempotent = $IsIdempotent -or $lastStatus -eq 429
            $retryAfterSeconds = $null
            $retryAfterDate = $null
            if ($retryAfterHeader) {
                $asInt = 0
                if ([int]::TryParse($retryAfterHeader, [ref]$asInt)) {
                    $retryAfterSeconds = [double]$asInt
                } else {
                    $retryAfterDate = $retryAfterHeader
                }
            }
            $decision = Get-FsuRetryDecision `
                -Policy $policy `
                -Attempt $attempt `
                -ElapsedSeconds $elapsed `
                -StatusCode $lastStatus `
                -IsRateLimited:($lastStatus -eq 429) `
                -RetryAfterSeconds $retryAfterSeconds `
                -RetryAfterHttpDate $retryAfterDate `
                -Now $now `
                -IsIdempotent $retryIdempotent `
                -JitterFraction $jitter
            if ($decision.ShouldRetry) {
                Test-FsuRequestCancellation -Token $CancellationToken -CorrelationId $correlationId
                & $Wait $decision.DelaySeconds
                continue
            }

            if (-not $IsIdempotent -and ($lastStatus -eq 408 -or $lastStatus -ge 500)) {
                Write-FsuRequestAudit -Context $Context -Outcome Uncertain -Operation $Operation -ResourceId $ResourceId -Status $lastStatus -RateLimitState $rateLimitState
                throw (Get-FsuRequestErrorRecord -Id 'FreshservicePSU.Error.UncertainOutcome' -Message 'The mutation may or may not have been applied. It was not retried.' -Category OperationStopped -CorrelationId $correlationId)
            }
        }

        $failure = Get-FsuNormalizedFailure -StatusCode $lastStatus -Content $raw.Content -CorrelationId $correlationId
        Write-FsuRequestAudit -Context $Context -Outcome Failure -Operation $Operation -ResourceId $ResourceId -Status $lastStatus -RateLimitState $rateLimitState
        throw $failure
    }
}
