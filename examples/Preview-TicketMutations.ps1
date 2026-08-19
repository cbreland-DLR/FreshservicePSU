#Requires -Version 7.6
<#
.SYNOPSIS
    Safe preview of ticket create, update, and note commands.

.DESCRIPTION
    Consumer example for PSU ticket forms. Uses only public
    FreshservicePSU commands and -WhatIf. No HTTP request is sent.
#>
[CmdletBinding()]
param(
    [ValidateRange(1, [long]::MaxValue)]
    [long]$TicketId = 1,

    [ValidateNotNullOrEmpty()]
    [string]$Email = 'ada@contoso.com'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

New-FreshServiceTicket -Email $Email -Subject 'Example ticket' -Description 'Created from the Phase 7 preview example.' -WhatIf
Set-FreshServiceTicket -TicketId $TicketId -Status 5 -WhatIf
Add-FreshServiceTicketNote -TicketId $TicketId -Body 'Example private note.' -Private $true -WhatIf
