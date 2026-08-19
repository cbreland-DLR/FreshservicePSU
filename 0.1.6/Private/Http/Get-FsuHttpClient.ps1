function Get-FsuHttpClient {
    <#
    .SYNOPSIS
        Returns the module-scoped HttpClient used for connection reuse.

    .DESCRIPTION
        ARCHITECTURE.md §11 requires a module-scoped HttpClient over a
        SocketsHttpHandler with a bounded PooledConnectionLifetime. The
        client never carries Authorization default headers: authentication
        is attached per request. This function is the only place the shared
        client is created. Tests inject a Transport on Send-FsuHttpRequest
        and never reach this path.
    #>
    [CmdletBinding()]
    [OutputType([System.Net.Http.HttpClient])]
    param()

    if ($null -eq $script:FsuSharedHttpClient) {
        $handler = [System.Net.Http.SocketsHttpHandler]::new()
        $handler.PooledConnectionLifetime = [timespan]::FromMinutes(2)
        $handler.PooledConnectionIdleTimeout = [timespan]::FromMinutes(1)
        $handler.UseCookies = $false
        $handler.AllowAutoRedirect = $false

        $client = [System.Net.Http.HttpClient]::new($handler, $true)
        $client.Timeout = [timespan]::FromMinutes(5)
        $script:FsuSharedHttpClient = $client
    }

    return $script:FsuSharedHttpClient
}
