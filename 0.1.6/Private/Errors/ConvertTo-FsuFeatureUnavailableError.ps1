function ConvertTo-FsuFeatureUnavailableError {
    <#
    .SYNOPSIS
        Remaps require_feature and HTTP 405 into a command-specific unavailable error.
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.ErrorRecord])]
    param(
        [Parameter(Mandatory)]
        $InputObject,

        [Parameter(Mandatory)]
        [ValidatePattern('^FreshservicePSU\.')]
        [string]$ErrorId,

        [Parameter(Mandatory)]
        [string]$Message,

        [string]$CorrelationId
    )

    $incomingId = [string]$InputObject.FullyQualifiedErrorId
    if ($incomingId -notmatch 'RequireFeature|MethodNotAllowed') {
        return $null
    }

    $statusCode = $null
    if ($InputObject.Exception -and $InputObject.Exception.Data -and $InputObject.Exception.Data.Contains('StatusCode')) {
        $statusCode = $InputObject.Exception.Data['StatusCode']
    }

    return New-FsuErrorRecord `
        -ErrorId $ErrorId `
        -Message $Message `
        -Category ResourceUnavailable `
        -CorrelationId $CorrelationId `
        -StatusCode $statusCode
}
