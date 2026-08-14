#Requires -Version 7.6
<#
.SYNOPSIS
    Collects a sanitized Freshservice sandbox evidence report for Q7, Q8, Q9,
    or the correlation-header spike.

.DESCRIPTION
    This operator tool never writes API keys, Authorization headers, response
    bodies, identifiers, or header values to its report. It records only HTTP
    status, response property names and types, and the names of returned
    headers. Ticket-note creation requires the explicit -AcknowledgeWrite
    switch and a disposable ticket supplied by the operator.

    Run each authorization case separately, give it a distinct -SurfaceLabel,
    review the JSON report, summarize the result in OPEN_QUESTIONS.md, and
    delete the raw report. Never run this against production.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('TicketNote', 'ApprovalSearch', 'AssetAssignmentHistory', 'CorrelationHeader')]
    [string]$Scenario,

    [Parameter(Mandatory)]
    [uri]$BaseUri,

    [Parameter(Mandatory)]
    [string]$SurfaceLabel,

    [securestring]$ApiKey,

    [long]$TicketId,

    [long]$UserId,

    [long]$ExpectedAuthorId,

    [string]$ApprovalQuery,

    [long]$AssetDisplayId,

    [switch]$AcknowledgeWrite,

    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-FsuEvidenceShape {
    param(
        [AllowNull()][object]$Value,
        [int]$Depth = 0,
        [int]$MaximumDepth = 4
    )

    if ($null -eq $Value) {
        return [ordered]@{ Kind = 'Null'; Properties = @() }
    }

    if ($Value -is [array]) {
        $first = @($Value | Select-Object -First 1)
        return [ordered]@{
            Kind = 'Array'
            Count = @($Value).Count
            Item = if ($first -and $Depth -lt $MaximumDepth) {
                Get-FsuEvidenceShape -Value $first[0] -Depth ($Depth + 1) -MaximumDepth $MaximumDepth
            } else {
                $null
            }
        }
    }

    if ($Value -is [psobject] -and $Value -isnot [string]) {
        return [ordered]@{
            Kind = $Value.GetType().FullName
            Properties = @(foreach ($property in $Value.PSObject.Properties | Sort-Object Name) {
                    [ordered]@{
                        Name = $property.Name
                        Shape = if ($Depth -lt $MaximumDepth) {
                            Get-FsuEvidenceShape -Value $property.Value -Depth ($Depth + 1) -MaximumDepth $MaximumDepth
                        } else {
                            [ordered]@{ Kind = if ($null -eq $property.Value) { 'Null' } else { $property.Value.GetType().FullName }; Properties = @() }
                        }
                    }
                })
        }
    }

    return [ordered]@{ Kind = $Value.GetType().FullName; Properties = @() }
}

function Find-FsuEvidenceProperty {
    param(
        [AllowNull()][object]$Value,
        [Parameter(Mandatory)][string[]]$Name,
        [string]$Path = '$',
        [int]$Depth = 0
    )

    if ($null -eq $Value -or $Depth -gt 6) {
        return
    }

    if ($Value -is [array]) {
        for ($index = 0; $index -lt @($Value).Count; $index++) {
            Find-FsuEvidenceProperty -Value $Value[$index] -Name $Name -Path "$Path[]" -Depth ($Depth + 1)
        }
        return
    }

    if ($Value -is [psobject] -and $Value -isnot [string]) {
        foreach ($property in $Value.PSObject.Properties) {
            $propertyPath = "$Path.$($property.Name)"
            if ($property.Name -in $Name) {
                [pscustomobject]@{ Path = $propertyPath; Value = $property.Value }
            }
            Find-FsuEvidenceProperty -Value $property.Value -Name $Name -Path $propertyPath -Depth ($Depth + 1)
        }
    }
}

function Get-FsuEvidenceHeaderText {
    param(
        [Parameter(Mandatory)][object]$Headers,
        [Parameter(Mandatory)][string]$Name
    )

    $values = @($Headers[$Name])
    return ($values | ForEach-Object { [string]$_ }) -join ','
}

function Get-FsuEvidenceFingerprint {
    param([AllowNull()][object]$Value, [Parameter(Mandatory)][string]$Salt)

    if ($null -eq $Value) {
        return $null
    }

    $bytes = [System.Text.Encoding]::UTF8.GetBytes("$Salt$Value")
    $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
    return -join ($hash[0..3] | ForEach-Object { $_.ToString('x2') })
}

if ($BaseUri.Scheme -ne 'https' -or $BaseUri.Host -notmatch '^[a-z0-9-]+\.freshservice\.com$' -or
    $BaseUri.AbsolutePath -ne '/api/v2/') {
    throw 'BaseUri must be an HTTPS standard Freshservice API v2 URI, such as https://tenant.freshservice.com/api/v2/.'
}

if (-not $ApiKey) {
    $ApiKey = Read-Host -Prompt 'Freshservice sandbox API key' -AsSecureString
}

if ($Scenario -eq 'TicketNote' -and ($TicketId -le 0 -or -not $AcknowledgeWrite)) {
    throw 'TicketNote requires a disposable -TicketId and the explicit -AcknowledgeWrite switch.'
}

if ($Scenario -eq 'ApprovalSearch' -and [string]::IsNullOrWhiteSpace($ApprovalQuery)) {
    throw 'ApprovalSearch requires the documented sandbox filter string in -ApprovalQuery, without a leading question mark.'
}

if ($Scenario -eq 'AssetAssignmentHistory' -and $AssetDisplayId -le 0) {
    throw 'AssetAssignmentHistory requires -AssetDisplayId.'
}

$plainApiKey = $null
$bstr = [IntPtr]::Zero
$credentialBytes = $null
try {
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($ApiKey)
    $plainApiKey = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    $credentialBytes = [Text.Encoding]::UTF8.GetBytes("${plainApiKey}:X")
    $basicCredential = [Convert]::ToBase64String($credentialBytes)
} finally {
    if ($bstr -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

$relativePath = switch ($Scenario) {
    'TicketNote' { "tickets/$TicketId/notes" }
    'ApprovalSearch' { "approvals?$ApprovalQuery" }
    'AssetAssignmentHistory' { "assets/$AssetDisplayId/assignment-history" }
    'CorrelationHeader' { 'agents?per_page=1' }
}

$headers = @{ Authorization = "Basic $basicCredential"; Accept = 'application/json' }
$correlationId = $null
if ($Scenario -eq 'CorrelationHeader') {
    $correlationId = [guid]::NewGuid().ToString()
    $headers['X-Correlation-ID'] = $correlationId
}

$request = @{ Uri = ([uri]::new($BaseUri, $relativePath)); Headers = $headers; Method = if ($Scenario -eq 'TicketNote') { 'Post' } else { 'Get' }; SkipHttpErrorCheck = $true }
if ($Scenario -eq 'TicketNote') {
    $note = @{ body = "FreshservicePSU sandbox evidence note $([guid]::NewGuid())"; private = $true }
    if ($UserId -gt 0) {
        $note['user_id'] = $UserId
    }
    $request['ContentType'] = 'application/json'
    $request['Body'] = $note | ConvertTo-Json -Compress
}

$salt = [guid]::NewGuid().ToString()
$response = $null
$transportError = $null
try {
    $response = Invoke-WebRequest @request
} catch {
    $transportError = $_.Exception.GetType().FullName
} finally {
    if ($credentialBytes) {
        [array]::Clear($credentialBytes, 0, $credentialBytes.Length)
    }
    $plainApiKey = $null
    $basicCredential = $null
    $headers.Authorization = $null
}

$body = $null
if ($response -and -not [string]::IsNullOrWhiteSpace($response.Content)) {
    try { $body = $response.Content | ConvertFrom-Json -Depth 32 } catch { $body = $null }
}

$authorProperties = if ($Scenario -eq 'TicketNote' -and $body) {
    @(Find-FsuEvidenceProperty -Value $body -Name @('user_id', 'created_by', 'agent_id'))
} else {
    @()
}

$responseHeaderNames = if ($response) { @($response.Headers.Keys | Sort-Object) } else { @() }
$paginationHeaderNames = @($responseHeaderNames | Where-Object { $_ -match '^(?i:link|x-total-count|x-page|x-per-page)$' })
$linkRelations = @()
if ($response -and $responseHeaderNames -contains 'Link') {
    $linkText = Get-FsuEvidenceHeaderText -Headers $response.Headers -Name 'Link'
    $linkRelations = @([regex]::Matches($linkText, 'rel\s*=\s*"?(?<Relation>[^";,\s]+)') |
            ForEach-Object { $_.Groups['Relation'].Value } | Sort-Object -Unique)
}

$correlationEchoHeaderNames = @()
if ($response -and $correlationId) {
    $correlationEchoHeaderNames = @($responseHeaderNames | Where-Object {
            (Get-FsuEvidenceHeaderText -Headers $response.Headers -Name $_) -eq $correlationId
        })
}

$report = [ordered]@{
    SchemaVersion = '1.0'
    CollectedUtc = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
    SurfaceLabel = $SurfaceLabel
    Scenario = $Scenario
    Request = [ordered]@{
        Method = $request.Method
        EndpointTemplate = switch ($Scenario) {
            'TicketNote' { 'tickets/{ticket_id}/notes' }
            'ApprovalSearch' { 'approvals?{documented-filter}' }
            'AssetAssignmentHistory' { 'assets/{display_id}/assignment-history' }
            'CorrelationHeader' { 'agents?per_page=1 with X-Correlation-ID' }
        }
        SentUserId = $UserId -gt 0
        SentCorrelationHeader = $Scenario -eq 'CorrelationHeader'
    }
    Result = [ordered]@{
        TransportErrorType = $transportError
        HttpStatusCode = if ($response) { [int]$response.StatusCode } else { $null }
        ResponseHeaderNames = $responseHeaderNames
        PaginationHeaderNames = $paginationHeaderNames
        LinkRelations = $linkRelations
        BodyShape = Get-FsuEvidenceShape -Value $body
        NoteAuthorPropertyPaths = @($authorProperties | ForEach-Object { $_.Path })
        NoteAuthorFingerprints = @($authorProperties | ForEach-Object {
                Get-FsuEvidenceFingerprint -Value $_.Value -Salt $salt
            })
        ExpectedAuthorMatched = if ($ExpectedAuthorId -gt 0 -and $authorProperties) {
            [bool](@($authorProperties.Value | ForEach-Object { [string]$_ }) -contains [string]$ExpectedAuthorId)
        } else {
            $null
        }
        CorrelationHeaderAccepted = if ($Scenario -eq 'CorrelationHeader' -and $response) {
            [int]$response.StatusCode -ge 200 -and [int]$response.StatusCode -lt 300
        } else {
            $null
        }
        CorrelationEchoHeaderNames = $correlationEchoHeaderNames
    }
    SanitizationNote = 'No API key, authorization header, response body, identifiers, header values, query values, or correlation value is written. The note-author fingerprint is salted per report.'
}

if (-not $OutputPath) {
    $stamp = [datetime]::UtcNow.ToString('yyyyMMdd-HHmmss')
    $safeLabel = $SurfaceLabel -replace '[^A-Za-z0-9\-]', '_'
    $OutputPath = Join-Path ([IO.Path]::GetTempPath()) "freshservice-evidence-$safeLabel-$stamp.json"
}

$report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $OutputPath -Encoding utf8NoBOM
Write-Information "HTTP status     : $($report.Result.HttpStatusCode)" -InformationAction Continue
Write-Information "Report written  : $OutputPath" -InformationAction Continue
Write-Information 'Review the report, summarize only sanitized conclusions, then delete it.' -InformationAction Continue
