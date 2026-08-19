#Requires -Version 7.6
<#
.SYNOPSIS
    Bounded SLA-policy and business-hours configuration reads.

.DESCRIPTION
    Consumer example for PSU policy reports. Uses only public
    FreshservicePSU commands. Does not write configuration.
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 100)]
    [int]$MaxRecords = 20
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Complete-BoundedQuery.ps1')

try {
    Complete-BoundedQuery -MaxRecords $MaxRecords -Query { param($MaxRecords) Get-FreshServiceSLAPolicy -MaxRecords $MaxRecords }
} catch {
    if ([string]$_.FullyQualifiedErrorId -match 'SLAPolicy.Unavailable') {
        Write-Warning 'SLA policy reads are not available on this tenant.'
    } else {
        throw
    }
}

try {
    Complete-BoundedQuery -MaxRecords $MaxRecords -Query { param($MaxRecords) Get-FreshServiceBusinessHour -MaxRecords $MaxRecords }
} catch {
    if ([string]$_.FullyQualifiedErrorId -match 'BusinessHour.Unavailable') {
        Write-Warning 'Business-hours reads are not available on this tenant.'
    } else {
        throw
    }
}
