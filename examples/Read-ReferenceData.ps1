#Requires -Version 7.6
<#
.SYNOPSIS
    Bounded reads of form and report reference data.

.DESCRIPTION
    Consumer example for PSU pages and reports. Uses only public
    FreshservicePSU commands. Tenant, stage, and credentials come from
    the trusted PSU execution context. Does not persist results.
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 100)]
    [int]$MaxRecords = 20
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'Complete-BoundedQuery.ps1')

Complete-BoundedQuery -MaxRecords $MaxRecords -Query { param($MaxRecords) Get-FreshServiceLocation -MaxRecords $MaxRecords }
Complete-BoundedQuery -MaxRecords $MaxRecords -Query { param($MaxRecords) Get-FreshServiceDepartment -MaxRecords $MaxRecords }
Complete-BoundedQuery -MaxRecords $MaxRecords -Query { param($MaxRecords) Get-FreshServiceAgentGroup -MaxRecords $MaxRecords }
Complete-BoundedQuery -MaxRecords $MaxRecords -Query { param($MaxRecords) Get-FreshServiceAgent -MaxRecords $MaxRecords }
Complete-BoundedQuery -MaxRecords $MaxRecords -Query { param($MaxRecords) Get-FreshServiceRequester -MaxRecords $MaxRecords }
Complete-BoundedQuery -MaxRecords $MaxRecords -Query { param($MaxRecords) Get-FreshServiceTicketField -MaxRecords $MaxRecords }
