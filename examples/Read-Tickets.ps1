#Requires -Version 7.6
<#
.SYNOPSIS
    Bounded ticket, fulfillment, approval, and activity reads.

.DESCRIPTION
    Consumer example for PSU ticket reports. Uses only public
    FreshservicePSU commands. A later-page failure discards the
    incomplete buffer and does not treat the run as complete.
#>
[CmdletBinding()]
param(
    [ValidateRange(1, [long]::MaxValue)]
    [long]$TicketId = 1,

    [ValidateRange(1, 100)]
    [int]$MaxRecords = 20
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Complete-BoundedQuery.ps1')

Complete-BoundedQuery -MaxRecords $MaxRecords -Query { param($MaxRecords) Get-FreshServiceTicket -MaxRecords $MaxRecords }
Complete-BoundedQuery -MaxRecords $MaxRecords -Query { param($MaxRecords) Search-FreshServiceTicket -Query 'status:2' -MaxRecords $MaxRecords }
Get-FreshServiceTicket -TicketId $TicketId
Complete-BoundedQuery -MaxRecords $MaxRecords -Query { param($MaxRecords) Get-FreshServiceTicketActivity -TicketId $TicketId -MaxRecords $MaxRecords }
Complete-BoundedQuery -MaxRecords $MaxRecords -Query { param($MaxRecords) Get-FreshServiceRequestedItem -TicketId $TicketId -MaxRecords $MaxRecords }
Complete-BoundedQuery -MaxRecords $MaxRecords -Query { param($MaxRecords) Get-FreshServiceTask -TicketId $TicketId -MaxRecords $MaxRecords }
Complete-BoundedQuery -MaxRecords $MaxRecords -Query { param($MaxRecords) Get-FreshServiceRequestApproval -TicketId $TicketId -MaxRecords $MaxRecords }

try {
    Complete-BoundedQuery -MaxRecords $MaxRecords -Query { param($MaxRecords) Search-FreshServiceApproval -Status requested -MaxRecords $MaxRecords }
} catch {
    if ([string]$_.FullyQualifiedErrorId -match 'SearchUnavailable') {
        Write-Warning 'Cross-ticket approval search is not available on this tenant (Q8).'
    } else {
        throw
    }
}
