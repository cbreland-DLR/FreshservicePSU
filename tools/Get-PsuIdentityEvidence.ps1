#Requires -Version 7.0
<#
.SYNOPSIS
    Collects sanitized evidence for FreshservicePSU open questions Q1, Q2, Q3,
    and Q15 from a running PowerShell Universal instance.

.DESCRIPTION
    Read-only with one deliberate exception, described under -RunSharedStateTest
    below. The script reads the identity variables PSU exposes on whichever
    surface it is running on, inventories the current user's claims, records
    runtime versions, and optionally probes cross-process coordination.

    NOTHING SENSITIVE IS WRITTEN TO THE OUTPUT. Claim values are never
    recorded. For each claim the script records its type URI, issuer, value
    kind (Guid / Email / Uri / Other), value length, and an 8-character
    fingerprint derived from a salted SHA-256 of the value. The fingerprint is
    stable within one run, so two users can be compared to confirm they
    normalize differently, and it is useless outside that run because the salt
    is random per invocation. Assertions, ID tokens, access tokens, secrets,
    and raw claim values never enter the output.

    Run it once per surface. Deploy the same file as an API endpoint, an App
    page, and a scheduled script; each run reports which surface it detected.
    See tools/README.md for deployment steps.

.PARAMETER OutputPath
    Where to write the JSON report. Defaults to a timestamped file in the
    system temp directory. Review the file before sharing it.

.PARAMETER SurfaceLabel
    Free-text label recorded in the report, e.g. 'API-SAML-UserA' or
    'Schedule-System'. Use it to tell runs apart when comparing surfaces or
    two different users.

.PARAMETER RunSharedStateTest
    Opt-in. Probes Q15 by taking an OS-named mutex and writing one entry to
    PSU's server-level cache under a key prefixed 'FsuEvidence.'. This is the
    only write the script performs; it removes the entry afterwards. Omit this
    switch to keep the run strictly read-only.

.EXAMPLE
    ./Get-PsuIdentityEvidence.ps1 -SurfaceLabel 'API-SAML-UserA'

.EXAMPLE
    ./Get-PsuIdentityEvidence.ps1 -SurfaceLabel 'Schedule-System' -RunSharedStateTest
#>
[CmdletBinding()]
param(
    [string]$OutputPath,

    [Parameter(Mandatory)]
    [string]$SurfaceLabel,

    [switch]$RunSharedStateTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Random per run: fingerprints can be compared within one report, and carry no
# meaning outside it. This is what makes recording claim shape safe.
$script:Salt = [guid]::NewGuid().ToString()

function Get-Fingerprint {
    param([string]$Value)

    if ([string]::IsNullOrEmpty($Value)) { return $null }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($script:Salt + $Value)
    $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
    return -join ($hash[0..3] | ForEach-Object { $_.ToString('x2') })
}

function Get-ValueKind {
    param([string]$Value)

    if ([string]::IsNullOrEmpty($Value)) { return 'Empty' }
    $parsedGuid = [guid]::Empty
    if ([guid]::TryParse($Value, [ref]$parsedGuid)) { return 'Guid' }
    if ($Value -match '^[^@\s]+@[^@\s]+\.[^@\s]+$') { return 'Email' }
    if ($Value -match '^https?://') { return 'Uri' }
    if ($Value -match '^\d+$') { return 'Numeric' }
    return 'Other'
}

# Describes a variable without ever emitting its contents.
function Get-VariableEvidence {
    param([string]$Name)

    $variable = Get-Variable -Name $Name -ErrorAction SilentlyContinue
    if ($null -eq $variable) {
        return [ordered]@{ Name = "`$$Name"; Present = $false; Type = $null; Detail = 'not defined on this surface' }
    }

    $value = $variable.Value
    if ($null -eq $value) {
        return [ordered]@{ Name = "`$$Name"; Present = $true; Type = $null; Detail = 'defined but $null' }
    }

    $detail = switch ($true) {
        ($value -is [string]) { "string, length $($value.Length), kind $(Get-ValueKind -Value $value), fingerprint $(Get-Fingerprint -Value $value)"; break }
        ($value -is [array]) { "array of $($value.Count)"; break }
        default { 'present' }
    }

    return [ordered]@{
        Name = "`$$Name"
        Present = $true
        Type = $value.GetType().FullName
        Detail = $detail
    }
}

Write-Host "Collecting PSU identity evidence for surface '$SurfaceLabel'..." -ForegroundColor Cyan

# --- Q3: runtime facts ----------------------------------------------------
$runtime = [ordered]@{
    PowerShellVersion = $PSVersionTable.PSVersion.ToString()
    PSEdition = $PSVersionTable.PSEdition
    OSDescription = [System.Runtime.InteropServices.RuntimeInformation]::OSDescription
    ProcessArchitecture = [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString()
    ProcessId = $PID
    ProcessName = (Get-Process -Id $PID).ProcessName
    RunspaceInstanceId = [runspace]::DefaultRunspace.InstanceId.ToString()
    PsuModuleVersion = (Get-Module -Name 'Universal' -ListAvailable |
            Sort-Object Version -Descending |
            Select-Object -First 1 -ExpandProperty Version) -as [string]
}

# --- Q1: identity variables per surface -----------------------------------
# Names taken from the current Devolutions PSU variable reference. There is no
# $PSUIdentity or $UAIdentity despite both appearing in older forum material;
# both are probed anyway so their absence is recorded as evidence.
$variableNames = @(
    'Identity', 'ClaimsPrincipal', 'User', 'Roles',
    'UAJob', 'UAJobId', 'UAScript', 'UASchedule', 'UAScheduleId',
    'PSUEnvironment', 'Repository',
    'Url', 'Method', 'RemoteIpAddress',
    'PSUAppToken', 'PSUComputerName',
    'PSUIdentity', 'UAIdentity'
)
$variables = @(foreach ($name in $variableNames) { Get-VariableEvidence -Name $name })

$detectedSurface = switch ($true) {
    ($null -ne (Get-Variable -Name 'UAJob' -ErrorAction SilentlyContinue)) { 'Script or Schedule'; break }
    ($null -ne (Get-Variable -Name 'Url' -ErrorAction SilentlyContinue)) { 'API endpoint'; break }
    ($null -ne (Get-Variable -Name 'DashboardName' -ErrorAction SilentlyContinue)) { 'App'; break }
    default { 'Unknown or interactive console' }
}

# $UAJob.Identity.Name is the only identity a scheduled run is documented to
# have, so capture its shape specifically.
$jobIdentity = $null
$uaJob = Get-Variable -Name 'UAJob' -ErrorAction SilentlyContinue
if ($null -ne $uaJob -and $null -ne $uaJob.Value) {
    $identityName = $null
    try { $identityName = [string]$uaJob.Value.Identity.Name } catch { $identityName = $null }
    $jobIdentity = [ordered]@{
        HasIdentity = -not [string]::IsNullOrEmpty($identityName)
        Kind = Get-ValueKind -Value $identityName
        Length = if ($identityName) { $identityName.Length } else { 0 }
        Fingerprint = Get-Fingerprint -Value $identityName
    }
}

# --- Q2: claim inventory, types only --------------------------------------
$claims = @()
$claimsPrincipalPresent = $false
$claimsVariable = Get-Variable -Name 'ClaimsPrincipal' -ErrorAction SilentlyContinue
if ($null -ne $claimsVariable -and $null -ne $claimsVariable.Value) {
    $claimsPrincipalPresent = $true
    $principal = $claimsVariable.Value
    $identityNameValue = $null
    try { $identityNameValue = [string]$principal.Identity.Name } catch { $identityNameValue = $null }

    $claims = @(foreach ($claim in $principal.Claims) {
            [ordered]@{
                Type = $claim.Type
                Issuer = $claim.Issuer
                ValueType = $claim.ValueType
                ValueKind = Get-ValueKind -Value $claim.Value
                ValueLength = $claim.Value.Length
                Fingerprint = Get-Fingerprint -Value $claim.Value
            }
        })

    $claimSummary = [ordered]@{
        IsAuthenticated = [bool]$principal.Identity.IsAuthenticated
        AuthenticationType = [string]$principal.Identity.AuthenticationType
        IdentityNameKind = Get-ValueKind -Value $identityNameValue
        IdentityNameFingerprint = Get-Fingerprint -Value $identityNameValue
        ClaimCount = $claims.Count
        # The three Q2 cares about. Presence, not value.
        HasObjectIdentifier = [bool]($claims | Where-Object { $_.Type -eq 'http://schemas.microsoft.com/identity/claims/objectidentifier' })
        HasTenantId = [bool]($claims | Where-Object { $_.Type -eq 'http://schemas.microsoft.com/identity/claims/tenantid' })
        HasRequiredNameClaim = [bool]($claims | Where-Object { $_.Type -eq 'http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name' })
    }
} else {
    $claimSummary = [ordered]@{
        IsAuthenticated = $false
        AuthenticationType = $null
        ClaimCount = 0
        Note = 'No $ClaimsPrincipal on this surface. Claim-based normalization is impossible here.'
    }
}

# --- Q15: cross-process coordination (opt-in; the only write) -------------
$sharedState = [ordered]@{ Ran = $false; Note = 'Skipped. Pass -RunSharedStateTest to probe Q15.' }
if ($RunSharedStateTest) {
    $mutexName = 'Global\FsuEvidence.LimiterProbe'
    $cacheKey = "FsuEvidence.Probe.$([guid]::NewGuid().ToString('N').Substring(0, 8))"
    $mutex = $null
    $acquired = $false
    try {
        $mutex = [System.Threading.Mutex]::new($false, $mutexName)
        $acquired = $mutex.WaitOne([TimeSpan]::FromSeconds(10))

        $cacheAvailable = $null -ne (Get-Command -Name 'Set-PSUCache' -ErrorAction SilentlyContinue)
        $roundTripped = $null
        if ($cacheAvailable) {
            $token = [guid]::NewGuid().ToString()
            Set-PSUCache -Key $cacheKey -Value $token -Integrated
            $roundTripped = ((Get-PSUCache -Key $cacheKey -Integrated) -eq $token)
        }

        $workerProcesses = @(Get-Process -Name 'Universal*', 'PowerShellUniversal*' -ErrorAction SilentlyContinue |
                Select-Object -ExpandProperty Id)

        $sharedState = [ordered]@{
            Ran = $true
            MutexName = $mutexName
            MutexAcquired = $acquired
            CacheCmdletsAvailable = $cacheAvailable
            CacheRoundTripSucceeded = $roundTripped
            ObservedProcessId = $PID
            CandidateWorkerProcessIds = $workerProcesses
            CandidateWorkerProcessCount = $workerProcesses.Count
            Note = 'Run this concurrently from two worker processes and compare MutexAcquired timing and the shared cache value to satisfy Q15.'
        }
    } catch {
        $sharedState = [ordered]@{ Ran = $true; Error = $_.Exception.Message }
    } finally {
        if ($acquired -and $null -ne $mutex) { $mutex.ReleaseMutex() }
        if ($null -ne $mutex) { $mutex.Dispose() }
        if (Get-Command -Name 'Remove-PSUCache' -ErrorAction SilentlyContinue) {
            Remove-PSUCache -Key $cacheKey -Integrated -ErrorAction SilentlyContinue
        }
    }
}

# --- Report ---------------------------------------------------------------
$report = [ordered]@{
    SchemaVersion = '1.0'
    CollectedUtc = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
    SurfaceLabel = $SurfaceLabel
    DetectedSurface = $detectedSurface
    Runtime = $runtime
    Variables = $variables
    JobIdentity = $jobIdentity
    ClaimsPrincipalPresent = $claimsPrincipalPresent
    ClaimSummary = $claimSummary
    Claims = $claims
    SharedState = $sharedState
    SanitizationNote = 'Claim and identity values are never recorded. Fingerprints are salted per run and comparable only within this report.'
}

if (-not $OutputPath) {
    $stamp = [datetime]::UtcNow.ToString('yyyyMMdd-HHmmss')
    $safeLabel = ($SurfaceLabel -replace '[^A-Za-z0-9\-]', '_')
    $OutputPath = Join-Path ([System.IO.Path]::GetTempPath()) "psu-evidence-$safeLabel-$stamp.json"
}

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding utf8NoBOM

Write-Host ''
Write-Host "Surface detected : $detectedSurface" -ForegroundColor Green
Write-Host "ClaimsPrincipal  : $claimsPrincipalPresent"
Write-Host "Claims found     : $($claims.Count)"
Write-Host "PowerShell       : $($runtime.PowerShellVersion) on $($runtime.OSDescription)"
Write-Host "Report written   : $OutputPath" -ForegroundColor Green
Write-Host ''
Write-Host 'Review the file before sharing it. It should contain no claim values.' -ForegroundColor Yellow

$report
