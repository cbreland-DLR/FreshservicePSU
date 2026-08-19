#Requires -Version 7.6
<#
.SYNOPSIS
    Converts sanitized FreshservicePSU evidence JSON into reviewable Markdown.

.DESCRIPTION
    Accepts only the known PSU identity and Freshservice sandbox evidence
    schemas. It emits safe observations, never conclusions, and never edits
    OPEN_QUESTIONS.md. Fingerprints, process IDs, tenant identifiers, endpoint
    identifiers, query values, response values, and header values are omitted.
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string[]]$Path,

    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-FsuMarkdownText {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) { return 'Not observed' }
    if ($Value -is [bool]) { return $Value.ToString().ToLowerInvariant() }
    if ($Value -is [array]) {
        if (@($Value).Count -eq 0) { return 'None' }
        return (@($Value | ForEach-Object { [string]$_ }) -join ', ') -replace '\|', '\|'
    }

    return ([string]$Value -replace '[\r\n]+', ' ' -replace '\|', '\|')
}

function Get-FsuPropertyValue {
    param(
        [AllowNull()][object]$InputObject,
        [Parameter(Mandatory)][string]$Name
    )

    if ($null -eq $InputObject -or $InputObject.PSObject.Properties.Name -notcontains $Name) {
        return $null
    }
    return $InputObject.$Name
}

function Assert-FsuEvidenceSchema {
    param(
        [Parameter(Mandatory)][object]$Report,
        [Parameter(Mandatory)][string]$ReportPath
    )

    if ((Get-FsuPropertyValue -InputObject $Report -Name 'SchemaVersion') -ne '1.0') {
        throw "Unsupported or missing evidence schema in '$ReportPath'."
    }

    $psuAllowed = @(
        'SchemaVersion', 'CollectedUtc', 'SurfaceLabel', 'DetectedSurface',
        'Runtime', 'Variables', 'JobIdentity', 'ClaimsPrincipalPresent',
        'ClaimSummary', 'Claims', 'ComparisonFingerprintsEnabled',
        'SanitizationNote'
    )
    $freshserviceAllowed = @(
        'SchemaVersion', 'CollectedUtc', 'SurfaceLabel', 'Scenario',
        'Request', 'Result', 'SanitizationNote'
    )

    $kind = if ($Report.PSObject.Properties.Name -contains 'DetectedSurface') {
        'PSU'
    } elseif ($Report.PSObject.Properties.Name -contains 'Scenario') {
        'Freshservice'
    } else {
        throw "Unrecognized evidence report in '$ReportPath'."
    }

    $allowed = if ($kind -eq 'PSU') { $psuAllowed } else { $freshserviceAllowed }
    $unknown = @($Report.PSObject.Properties.Name | Where-Object { $_ -notin $allowed })
    if ($unknown) {
        throw "Evidence report '$ReportPath' contains unexpected top-level fields: $($unknown -join ', ')."
    }

    return $kind
}

function Get-FsuShapePath {
    param(
        [AllowNull()][object]$Shape,
        [string]$Path = '$',
        [int]$Depth = 0
    )

    if ($null -eq $Shape -or $Depth -gt 6) { return }
    $kind = Get-FsuPropertyValue -InputObject $Shape -Name 'Kind'
    "$Path : $kind"

    $item = Get-FsuPropertyValue -InputObject $Shape -Name 'Item'
    if ($null -ne $item) {
        Get-FsuShapePath -Shape $item -Path "$Path[]" -Depth ($Depth + 1)
    }

    foreach ($property in @(Get-FsuPropertyValue -InputObject $Shape -Name 'Properties')) {
        if ($null -ne $property) {
            Get-FsuShapePath -Shape $property.Shape -Path "$Path.$($property.Name)" -Depth ($Depth + 1)
        }
    }
}

function ConvertTo-FsuMarkdownRow {
    param(
        [Parameter(Mandatory)][string]$Field,
        [AllowNull()][object]$Value
    )

    return "| $(ConvertTo-FsuMarkdownText $Field) | $(ConvertTo-FsuMarkdownText $Value) |"
}

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add('# FreshservicePSU evidence summary')
$lines.Add('')
$lines.Add('Review-only observations generated from sanitized reports. A maintainer must interpret these results; this file does not close any open question.')

foreach ($reportPath in $Path) {
    $resolvedPath = (Resolve-Path -LiteralPath $reportPath -ErrorAction Stop).Path
    $report = Get-Content -LiteralPath $resolvedPath -Raw | ConvertFrom-Json -Depth 32
    $kind = Assert-FsuEvidenceSchema -Report $report -ReportPath $resolvedPath

    $lines.Add('')
    $lines.Add("## $(ConvertTo-FsuMarkdownText (Get-FsuPropertyValue $report 'SurfaceLabel'))")
    $lines.Add('')
    $lines.Add('| Observation | Sanitized result |')
    $lines.Add('| --- | --- |')
    $lines.Add((ConvertTo-FsuMarkdownRow -Field 'Collected UTC' -Value (Get-FsuPropertyValue $report 'CollectedUtc')))
    $lines.Add((ConvertTo-FsuMarkdownRow -Field 'Report type' -Value $kind))

    if ($kind -eq 'PSU') {
        $lines.Add((ConvertTo-FsuMarkdownRow -Field 'Detected surface' -Value (Get-FsuPropertyValue $report 'DetectedSurface')))
        $lines.Add((ConvertTo-FsuMarkdownRow -Field 'PowerShell version' -Value (Get-FsuPropertyValue $report.Runtime 'PowerShellVersion')))
        $lines.Add((ConvertTo-FsuMarkdownRow -Field 'Operating system' -Value (Get-FsuPropertyValue $report.Runtime 'OSDescription')))
        $lines.Add((ConvertTo-FsuMarkdownRow -Field 'Claims principal present' -Value (Get-FsuPropertyValue $report 'ClaimsPrincipalPresent')))
        $lines.Add((ConvertTo-FsuMarkdownRow -Field 'Comparison fingerprints enabled' -Value (Get-FsuPropertyValue $report 'ComparisonFingerprintsEnabled')))
        $lines.Add((ConvertTo-FsuMarkdownRow -Field 'Authentication type' -Value (Get-FsuPropertyValue $report.ClaimSummary 'AuthenticationType')))
        $lines.Add((ConvertTo-FsuMarkdownRow -Field 'Claim types' -Value @($report.Claims.Type | Sort-Object -Unique)))

        $presentVariables = @($report.Variables | Where-Object Present | ForEach-Object { "$($_.Name) [$($_.Type)]" })
        $lines.Add((ConvertTo-FsuMarkdownRow -Field 'Present PSU variables' -Value $presentVariables))

    } else {
        $result = $report.Result
        $lines.Add((ConvertTo-FsuMarkdownRow -Field 'Scenario' -Value (Get-FsuPropertyValue $report 'Scenario')))
        $lines.Add((ConvertTo-FsuMarkdownRow -Field 'HTTP status' -Value (Get-FsuPropertyValue $result 'HttpStatusCode')))
        $lines.Add((ConvertTo-FsuMarkdownRow -Field 'Transport error type' -Value (Get-FsuPropertyValue $result 'TransportErrorType')))
        $lines.Add((ConvertTo-FsuMarkdownRow -Field 'Response header names' -Value @(Get-FsuPropertyValue $result 'ResponseHeaderNames')))
        $lines.Add((ConvertTo-FsuMarkdownRow -Field 'Pagination header names' -Value @(Get-FsuPropertyValue $result 'PaginationHeaderNames')))
        $lines.Add((ConvertTo-FsuMarkdownRow -Field 'Link relations' -Value @(Get-FsuPropertyValue $result 'LinkRelations')))
        $lines.Add((ConvertTo-FsuMarkdownRow -Field 'Body property paths and types' -Value @(Get-FsuShapePath -Shape $result.BodyShape)))
        $lines.Add((ConvertTo-FsuMarkdownRow -Field 'Note author property paths' -Value @(Get-FsuPropertyValue $result 'NoteAuthorPropertyPaths')))
        $lines.Add((ConvertTo-FsuMarkdownRow -Field 'Expected author matched' -Value (Get-FsuPropertyValue $result 'ExpectedAuthorMatched')))
        $lines.Add((ConvertTo-FsuMarkdownRow -Field 'Correlation header accepted' -Value (Get-FsuPropertyValue $result 'CorrelationHeaderAccepted')))
        $lines.Add((ConvertTo-FsuMarkdownRow -Field 'Correlation echo header names' -Value @(Get-FsuPropertyValue $result 'CorrelationEchoHeaderNames')))
    }

    $lines.Add('| Maintainer conclusion | Pending review |')
}

if (-not $OutputPath) {
    $stamp = [datetime]::UtcNow.ToString('yyyyMMdd-HHmmss')
    $OutputPath = Join-Path ([IO.Path]::GetTempPath()) "fsu-evidence-summary-$stamp.md"
}

if ($PSCmdlet.ShouldProcess($OutputPath, 'Write sanitized evidence Markdown')) {
    $lines | Set-Content -LiteralPath $OutputPath -Encoding utf8NoBOM
    Write-Information "Markdown summary written: $OutputPath" -InformationAction Continue
}

