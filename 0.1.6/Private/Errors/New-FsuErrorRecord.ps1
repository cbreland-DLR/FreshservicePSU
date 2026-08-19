function New-FsuErrorRecord {
    <#
    .SYNOPSIS
        Builds a normalized, safe, machine-parseable terminating error record.

    .DESCRIPTION
        Shared error-record constructor used by every contract in this module
        that must fail closed. Never accepts or emits secrets, authorization
        values, or complete request headers. A caller-supplied CorrelationId
        and Field are carried on the exception's Data collection so tests and
        callers can recover them without widening the ErrorRecord's public
        surface. An optional InnerException preserves the original cause
        (e.g. the underlying HTTP failure behind a wrapping error such as
        FreshservicePSU.PartialResults) without exposing its message as the
        outer, stable message text.
    #>
    [System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Pure in-memory object constructor; no system state is changed.')]
    [CmdletBinding()]
    [OutputType([System.Management.Automation.ErrorRecord])]
    param(
        [Parameter(Mandatory)]
        [ValidatePattern('^FreshservicePSU\.')]
        [string]$ErrorId,

        [Parameter(Mandatory)]
        [string]$Message,

        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorCategory]$Category,

        [string]$CorrelationId,

        [string]$Field,

        [string]$Code,

        [Nullable[int]]$StatusCode,

        [string]$TargetObject,

        [System.Exception]$InnerException
    )

    $exception = if ($InnerException) {
        [System.Exception]::new($Message, $InnerException)
    } else {
        [System.Exception]::new($Message)
    }
    if ($CorrelationId) {
        $exception.Data['CorrelationId'] = $CorrelationId
    }
    if ($Field) {
        $exception.Data['Field'] = $Field
    }
    if ($Code) {
        $exception.Data['Code'] = $Code
    }
    if ($null -ne $StatusCode) {
        $exception.Data['StatusCode'] = $StatusCode
    }

    $errorRecord = [System.Management.Automation.ErrorRecord]::new(
        $exception,
        $ErrorId,
        $Category,
        $TargetObject
    )

    return $errorRecord
}
