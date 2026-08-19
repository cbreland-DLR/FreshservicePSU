function Invoke-FsuTokenPagedRequest {
    <#
    .SYNOPSIS
        Streams typed records across Freshservice next_page_url token pages.

    .DESCRIPTION
        Used by ticket activity. Follows next_page_url from the JSON body
        only when the URI stays under the configured tenant base URI.
        Continuation tokens are never copied into errors or audit events.
        A later-page failure becomes FreshservicePSU.PartialResults.
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


        [ValidateRange(1, [int]::MaxValue)]
        [int]$MaxRecords = 1000,


        [scriptblock]$Transport,

        [scriptblock]$GetTimestamp = { [datetime]::UtcNow },

        [scriptblock]$GetJitterFraction = { Get-Random -Minimum 0.0 -Maximum 1.0 },

        [scriptblock]$Wait = { param($Seconds) Start-Sleep -Seconds $Seconds },

        [System.Threading.CancellationToken]$CancellationToken = [System.Threading.CancellationToken]::None,

        [string]$Operation = 'Invoke-FsuTokenPagedRequest',

        [string]$ResourceId
    )

    function Get-FsuBodyProperty {
        param($Body, [string]$Name)

        if ($null -eq $Body) {
            return $null
        }
        if ($Body -is [System.Collections.IDictionary]) {
            if ($Body.Contains($Name)) {
                return $Body[$Name]
            }
            return $null
        }
        $property = $Body.PSObject.Properties[$Name]
        if ($null -eq $property) {
            return $null
        }
        return $property.Value
    }

    $pagesCompleted = 0
    $recordsEmitted = 0
    $nextUri = $null

    try {
        while ($true) {
            if ($CancellationToken.IsCancellationRequested) {
                throw (New-FsuErrorRecord -ErrorId 'FreshservicePSU.Http.Cancelled' -Message 'The paged request was cancelled.' -Category OperationStopped -CorrelationId ([string]$Context.CorrelationId))
            }
            if ($pagesCompleted -ge 500) {
                throw (New-FsuErrorRecord -ErrorId 'FreshservicePSU.Http.PageTooLarge' -Message 'Token pagination exceeded the maximum supported page (500). Narrow the query instead of paging further.' -Category InvalidArgument -CorrelationId ([string]$Context.CorrelationId))
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
            if ($nextUri) {
                $requestArgs.Uri = $nextUri
            } else {
                $requestArgs.PathSegments = $PathSegments
                $requestArgs.QueryParameters = $QueryParameters
            }

            $envelope = Invoke-FsuRequest @requestArgs
            $pagesCompleted++

            $pageRecords = ConvertFrom-FsuResponse -Body $envelope.Body -EnvelopeProperty $EnvelopeProperty -PSTypeName $PSTypeName -CorrelationId ([string]$Context.CorrelationId)
            $items = @()
            if ($null -ne $pageRecords) {
                $items = @($pageRecords)
            }

            foreach ($item in $items) {
                if ($recordsEmitted -ge $MaxRecords) {
                    return
                }
                $item
                $recordsEmitted++
            }

            if ($recordsEmitted -ge $MaxRecords) {
                return
            }
            if ($items.Count -eq 0) {
                return
            }

            $nextValue = Get-FsuBodyProperty -Body $envelope.Body -Name 'next_page_url'
            if ([string]::IsNullOrWhiteSpace([string]$nextValue)) {
                return
            }

            $candidate = $null
            if (-not [uri]::TryCreate([string]$nextValue, [UriKind]::Absolute, [ref]$candidate)) {
                throw (New-FsuErrorRecord -ErrorId 'FreshservicePSU.Http.UntrustedUri' -Message 'The continuation URI is not an absolute URI.' -Category InvalidData -CorrelationId ([string]$Context.CorrelationId))
            }
            $nextUri = $candidate
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
                -CorrelationId ([string]$Context.CorrelationId)
            $partial.Exception.Data['PagesCompleted'] = $pagesCompleted
            $partial.Exception.Data['RecordsEmitted'] = $recordsEmitted
            throw $partial
        }
        throw
    }
}
