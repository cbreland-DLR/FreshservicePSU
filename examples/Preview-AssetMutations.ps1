#Requires -Version 7.6
<#
.SYNOPSIS
    Safe preview of asset update and soft-delete commands.

.DESCRIPTION
    Consumer example for PSU asset automations. Uses only public
    FreshservicePSU commands and -WhatIf. No HTTP request is sent.
#>
[CmdletBinding()]
param(
    [ValidateRange(1, [long]::MaxValue)]
    [long]$DisplayId = 1
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Set-FreshServiceAsset -DisplayId $DisplayId -Name 'Example asset' -WhatIf
Remove-FreshServiceAsset -DisplayId $DisplayId -WhatIf
