#Requires -Version 7.6
<#
.SYNOPSIS
    Bounded asset, asset-type, and assignment-history reads.

.DESCRIPTION
    Consumer example for PSU asset pages and reports. Uses only public
    FreshservicePSU commands. Assignment history may be unavailable (Q9).
#>
[CmdletBinding()]
param(
    [ValidateRange(1, [long]::MaxValue)]
    [long]$DisplayId = 1,

    [ValidateRange(1, 100)]
    [int]$MaxRecords = 20
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Complete-BoundedQuery.ps1')

Complete-BoundedQuery -MaxRecords $MaxRecords -Query { param($MaxRecords) Get-FreshServiceAssetType -MaxRecords $MaxRecords }
Get-FreshServiceAsset -DisplayId $DisplayId
Complete-BoundedQuery -MaxRecords $MaxRecords -Query { param($MaxRecords) Get-FreshServiceAsset -Filter "asset_state:'IN STOCK'" -MaxRecords $MaxRecords }

try {
    Complete-BoundedQuery -MaxRecords $MaxRecords -Query { param($MaxRecords) Get-FreshServiceAssetAssignmentHistory -DisplayId $DisplayId -MaxRecords $MaxRecords }
} catch {
    if ([string]$_.FullyQualifiedErrorId -match 'AssignmentHistoryUnavailable') {
        Write-Warning 'Asset assignment history is not available on this tenant (Q9).'
    } else {
        throw
    }
}
