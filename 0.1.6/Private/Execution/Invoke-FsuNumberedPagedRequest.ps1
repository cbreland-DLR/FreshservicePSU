function Invoke-FsuNumberedPagedRequest {
    <#
    .SYNOPSIS
        Streams typed records across Freshservice page-number pagination.

    .DESCRIPTION
        Used by endpoints that document `page` and an optional `total`
        count rather than a Link header (ticket filter). Page numbers
        above 500 are refused. A later-page failure becomes
        FreshservicePSU.PartialResults without continuation tokens or
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
        [int]$PerPage = 30,

        [ValidateRange(1, [int]::MaxValue)]
        [int]$MaxRecords = 1000,


        [scriptblock]$Transport,

        [scriptblock]$GetTimestamp = { [datetime]::UtcNow },

        [scriptblock]$GetJitterFraction = { Get-Random -Minimum 0.0 -Maximum 1.0 },

        [scriptblock]$Wait = { param($Seconds) Start-Sleep -Seconds $Seconds },

        [System.Threading.CancellationToken]$CancellationToken = [System.Threading.CancellationToken]::None,

        [string]$Operation = 'Invoke-FsuNumberedPagedRequest',

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
    $page = 1

    try {
        while ($true) {
            if ($CancellationToken.IsCancellationRequested) {
                throw (New-FsuErrorRecord -ErrorId 'FreshservicePSU.Http.Cancelled' -Message 'The paged request was cancelled.' -Category OperationStopped -CorrelationId ([string]$Context.CorrelationId))
            }
            if ($page -gt 500) {
                throw (New-FsuErrorRecord -ErrorId 'FreshservicePSU.Http.PageTooLarge' -Message 'Page 501 exceeds the maximum supported page (500). Narrow the query instead of paging further.' -Category InvalidArgument -CorrelationId ([string]$Context.CorrelationId))
            }

            $query = [ordered]@{}
            if ($QueryParameters) {
                foreach ($key in $QueryParameters.Keys) {
                    $query[$key] = $QueryParameters[$key]
                }
            }
            $query['per_page'] = $PerPage
            $query['page'] = $page

            $requestArgs = @{
                Context = $Context
                Method = $Method
                PathSegments = $PathSegments
                QueryParameters = $query
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
            if ($items.Count -eq 0 -or $items.Count -lt $PerPage) {
                return
            }

            $totalValue = Get-FsuBodyProperty -Body $envelope.Body -Name 'total'
            $total = 0
            if ($null -ne $totalValue -and [int]::TryParse([string]$totalValue, [ref]$total) -and $recordsEmitted -ge $total) {
                return
            }

            $page++
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
