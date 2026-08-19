function Invoke-FsuPagedRequest {
    <#
    .SYNOPSIS
        Streams typed records across Freshservice link-header pages.

    .DESCRIPTION
        Follows the Link rel=next header only; its absence ends paging
        (ARCHITECTURE.md §11). per_page is 1-100. Page numbers above 500
        are refused. Already-emitted records are not recalled when a later
        page fails: a FreshservicePSU.PartialResults error reports pages
        completed and records emitted without continuation tokens or
        response bodies. The failed page's original error (status code,
        vendor code, and message) is preserved as the PartialResults
        error's InnerException and, where available, copied onto its own
        Code/StatusCode so the cause is not discarded.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        $Context,

        [ValidateSet('GET')]
        [string]$Method = 'GET',

        [string[]]$PathSegments = @(),

        [System.Collections.IDictionary]$QueryParameters = @{},

        [Parameter(Mandatory)]
        [string]$EnvelopeProperty,

        [Parameter(Mandatory)]
        [string]$PSTypeName,


        [ValidateRange(1, 100)]
        [int]$PerPage = 100,

        [ValidateRange(1, [int]::MaxValue)]
        [int]$MaxRecords = 1000,


        [scriptblock]$Transport,

        [scriptblock]$GetTimestamp = { [datetime]::UtcNow },

        [scriptblock]$GetJitterFraction = { Get-Random -Minimum 0.0 -Maximum 1.0 },

        [scriptblock]$Wait = { param($Seconds) Start-Sleep -Seconds $Seconds },

        [System.Threading.CancellationToken]$CancellationToken = [System.Threading.CancellationToken]::None,

        [string]$Operation = 'Invoke-FsuPagedRequest',

        [string]$ResourceId
    )

    function Get-FsuNextPageUri {
        param([string]$Link)

        if ([string]::IsNullOrWhiteSpace($Link)) {
            return $null
        }

        foreach ($part in @($Link -split ',')) {
            if ($part -match '(?i)<([^>]+)>\s*;\s*rel="?next"?') {
                $candidate = $null
                if ([uri]::TryCreate($Matches[1], [UriKind]::Absolute, [ref]$candidate)) {
                    return $candidate
                }
            }
        }

        return $null
    }

    $query = [ordered]@{}
    if ($QueryParameters) {
        foreach ($key in $QueryParameters.Keys) {
            $query[$key] = $QueryParameters[$key]
        }
    }
    $query['per_page'] = $PerPage
    if (-not $query.Contains('page')) {
        $query['page'] = 1
    }

    $pagesCompleted = 0
    $recordsEmitted = 0
    $nextUri = $null
    $isFirst = $true

    try {
        while ($true) {
            if ($CancellationToken.IsCancellationRequested) {
                throw (New-FsuErrorRecord -ErrorId 'FreshservicePSU.Http.Cancelled' -Message 'The paged request was cancelled.' -Category OperationStopped -CorrelationId ([string]$Context.CorrelationId))
            }

            $requestArgs = @{
                Context = $Context
                Method = $Method
                IsIdempotent = $true
                GetTimestamp = $GetTimestamp
                GetJitterFraction = $GetJitterFraction
                Wait = $Wait
                CancellationToken = $CancellationToken
                Operation = $Operation
                ResourceId = $ResourceId
            }
            if ($Transport) {
                $requestArgs.Transport = $Transport
            }

            if ($isFirst) {
                $requestArgs.PathSegments = $PathSegments
                $requestArgs.QueryParameters = $query
            } else {
                $requestArgs.Uri = $nextUri
            }

            $envelope = Invoke-FsuRequest @requestArgs
            $pagesCompleted++
            $isFirst = $false

            $pageRecords = ConvertFrom-FsuResponse -Body $envelope.Body -EnvelopeProperty $EnvelopeProperty -PSTypeName $PSTypeName -CorrelationId ([string]$Context.CorrelationId)
            $items = @()
            if ($null -ne $pageRecords) {
                $items = @($pageRecords)
            }

            $nextUri = Get-FsuNextPageUri -Link ([string]$envelope.Link)

            for ($itemIndex = 0; $itemIndex -lt $items.Count; $itemIndex++) {
                if ($recordsEmitted -ge $MaxRecords) {
                    $leftoverOnPage = $items.Count - $itemIndex
                    if ($leftoverOnPage -gt 0 -or $null -ne $nextUri) {
                        Write-Warning "Invoke-FsuPagedRequest truncated results at MaxRecords ($MaxRecords); more records were available. Raise -MaxRecords to retrieve them."
                    }
                    return
                }
                $items[$itemIndex]
                $recordsEmitted++
            }

            if ($recordsEmitted -ge $MaxRecords) {
                if ($null -ne $nextUri) {
                    Write-Warning "Invoke-FsuPagedRequest truncated results at MaxRecords ($MaxRecords); more records were available. Raise -MaxRecords to retrieve them."
                }
                return
            }

            if ($null -eq $nextUri) {
                return
            }
        }
    } catch {
        $errorId = [string]$_.FullyQualifiedErrorId
        if ($errorId -match 'Cancelled|PartialResults') {
            throw
        }
        if ($pagesCompleted -gt 0) {
            $partial = New-FsuErrorRecord `
                -ErrorId 'FreshservicePSU.PartialResults' `
                -Message "A later page failed after $pagesCompleted page(s) and $recordsEmitted record(s). Discard or reconcile already-emitted records; the run is incomplete." `
                -Category OperationStopped `
                -CorrelationId ([string]$Context.CorrelationId) `
                -Code ([string]$_.Exception.Data['Code']) `
                -StatusCode ($_.Exception.Data['StatusCode']) `
                -InnerException $_.Exception
            $partial.Exception.Data['PagesCompleted'] = $pagesCompleted
            $partial.Exception.Data['RecordsEmitted'] = $recordsEmitted
            throw $partial
        }
        throw
    }
}
