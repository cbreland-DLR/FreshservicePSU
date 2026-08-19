function Send-FsuHttpRequest {
    <#
    .SYNOPSIS
        Sends one HTTP request. The only function that may use HttpClient.

    .DESCRIPTION
        Private/Http transport boundary (ARCHITECTURE.md §11). When
        -Transport is supplied the injected scriptblock receives a request
        description and must return a Freshservice.Http.RawResponse-shaped
        object; no network is used. The real path attaches caller-supplied
        headers to the request, never to the shared client.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'HEAD')]
        [string]$Method,

        [Parameter(Mandatory)]
        [uri]$Uri,

        [System.Collections.IDictionary]$Header = @{},

        [byte[]]$Body,

        [string]$ContentType = 'application/json; charset=utf-8',

        [System.Threading.CancellationToken]$CancellationToken = [System.Threading.CancellationToken]::None,

        [scriptblock]$Transport,

        [string]$CorrelationId
    )

    function ConvertTo-FsuRawHttpResponse {
        param(
            [Parameter(Mandatory)]
            [System.Net.Http.HttpResponseMessage]$HttpResponse
        )

        $headers = [hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($entry in $HttpResponse.Headers) {
            $headers[$entry.Key] = ($entry.Value -join ',')
        }
        if ($null -ne $HttpResponse.Content) {
            foreach ($entry in $HttpResponse.Content.Headers) {
                $headers[$entry.Key] = ($entry.Value -join ',')
            }
        }

        $content = ''
        if ($null -ne $HttpResponse.Content) {
            $content = $HttpResponse.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        }

        return [PSCustomObject]@{
            PSTypeName = 'Freshservice.Http.RawResponse'
            StatusCode = [int]$HttpResponse.StatusCode
            ReasonPhrase = [string]$HttpResponse.ReasonPhrase
            Header = $headers
            Content = $content
        }
    }

    $requestDescription = [PSCustomObject]@{
        PSTypeName = 'Freshservice.Http.Request'
        Method = $Method
        Uri = $Uri
        Header = $Header
        Body = $Body
        ContentType = $ContentType
    }

    if ($Transport) {
        return (& $Transport $requestDescription)
    }

    $client = Get-FsuHttpClient
    $message = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::new($Method), $Uri)
    $response = $null
    try {
        foreach ($key in @($Header.Keys)) {
            if ([string]::Equals([string]$key, 'Content-Type', [System.StringComparison]::OrdinalIgnoreCase)) {
                continue
            }
            $null = $message.Headers.TryAddWithoutValidation([string]$key, [string]$Header[$key])
        }

        if ($null -ne $Body -and @($Body).Count -gt 0 -and $Method -notin @('GET', 'HEAD')) {
            $message.Content = [System.Net.Http.ByteArrayContent]::new($Body)
            $message.Content.Headers.ContentType = [System.Net.Http.Headers.MediaTypeHeaderValue]::Parse($ContentType)
        }

        $response = $client.Send($message, $CancellationToken)
        return ConvertTo-FsuRawHttpResponse -HttpResponse $response
    } catch [System.OperationCanceledException] {
        if ($CancellationToken.IsCancellationRequested) {
            throw (New-FsuErrorRecord -ErrorId 'FreshservicePSU.Http.Cancelled' -Message 'The request was cancelled before completion.' -Category OperationStopped -CorrelationId $CorrelationId)
        }
        throw (New-FsuErrorRecord -ErrorId 'FreshservicePSU.Http.Timeout' -Message 'The HTTP request timed out before a Freshservice response was received.' -Category OperationTimeout -CorrelationId $CorrelationId)
    } catch [System.Net.Http.HttpRequestException] {
        throw (New-FsuErrorRecord -ErrorId 'FreshservicePSU.Http.NetworkFailure' -Message 'The HTTP request failed before a Freshservice response was received.' -Category ConnectionError -CorrelationId $CorrelationId)
    } finally {
        if ($null -ne $response) {
            $response.Dispose()
        }
        $message.Dispose()
    }
}
