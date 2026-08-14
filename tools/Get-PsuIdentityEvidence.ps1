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
    fingerprint derived from a salted SHA-256 of the value. The default salt is
    random per invocation. Pass the same temporary ComparisonSecret to a
    controlled set of runs only when cross-report comparison is required.
    Assertions, ID tokens, access tokens, secrets, and raw claim values never
    enter the output.

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

.PARAMETER ComparisonSecret
    Optional temporary secret used as the fingerprint salt. Supply the same
    value to User A/User B or SAML/OIDC runs that must be compared, then delete
    it. The value is never written to the report. Without this parameter,
    fingerprints are comparable only within one report.

.PARAMETER RunSharedStateTest
    Opt-in. Probes Q15 by taking an OS-named mutex and writing one entry to
    PSU's server-level cache under a key prefixed 'FsuEvidence.'. This is the
    only mode that writes. It requires SharedStateProbeId and SharedStateRole.

.PARAMETER SharedStateProbeId
    A non-secret label shared by every process in one Q15 probe. It is hashed
    before being used in the cache key or mutex name and is not written to the
    report.

.PARAMETER SharedStateRole
    Initializer writes count one while holding the mutex. Contender must start
    while Initializer holds it and advances the same cache state to count two.
    RestartSeed leaves a marker before a PSU restart; RestartCheck confirms
    whether it survived. Cleanup removes a failed or completed probe entry.

.EXAMPLE
    ./Get-PsuIdentityEvidence.ps1 -SurfaceLabel 'API-SAML-UserA'

.EXAMPLE
    ./Get-PsuIdentityEvidence.ps1 -SurfaceLabel 'Limiter-ProcessA' `
        -RunSharedStateTest -SharedStateProbeId 'q15-20260813' `
        -SharedStateRole Initializer
#>
[CmdletBinding()]
param(
    [string]$OutputPath,

    [Parameter(Mandatory)]
    [string]$SurfaceLabel,

    [securestring]$ComparisonSecret,

    [switch]$RunSharedStateTest,

    [ValidateSet('Initializer', 'Contender', 'RestartSeed', 'RestartCheck', 'Cleanup')]
    [string]$SharedStateRole,

    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]{2,63}$')]
    [string]$SharedStateProbeId,

    [ValidateRange(2, 15)]
    [int]$MutexHoldSeconds = 5
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Random per run by default. An operator can deliberately reuse a temporary,
# unreported secret across the small set of reports that must be compared.
$script:Salt = [guid]::NewGuid().ToString()
$comparisonFingerprintsEnabled = $false
if ($ComparisonSecret) {
    $comparisonBstr = [IntPtr]::Zero
    try {
        $comparisonBstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($ComparisonSecret)
        $script:Salt = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($comparisonBstr)
        if ($script:Salt.Length -lt 16) {
            throw 'ComparisonSecret must contain at least 16 characters.'
        }
        $comparisonFingerprintsEnabled = $true
    } finally {
        if ($comparisonBstr -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($comparisonBstr)
        }
    }
}

function Get-Fingerprint {
    param([string]$Value)

    if ([string]::IsNullOrEmpty($Value)) { return $null }
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($script:Salt + $Value)
    $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
    return -join ($hash[0..3] | ForEach-Object { $_.ToString('x2') })
}

function Get-StableHash {
    param([Parameter(Mandatory)][string]$Value)

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
    $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
    return -join ($hash[0..7] | ForEach-Object { $_.ToString('x2') })
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

Write-Information "Collecting PSU identity evidence for surface '$SurfaceLabel'..." -InformationAction Continue

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
    if ([string]::IsNullOrWhiteSpace($SharedStateProbeId) -or [string]::IsNullOrWhiteSpace($SharedStateRole)) {
        throw 'RunSharedStateTest requires SharedStateProbeId and SharedStateRole.'
    }

    $probeHash = Get-StableHash -Value $SharedStateProbeId
    $mutexLeaf = "FsuEvidence.LimiterProbe.$probeHash"
    $mutexName = if ($IsWindows) { "Global\$mutexLeaf" } else { $mutexLeaf }
    $cacheKey = "FsuEvidence.Probe.$probeHash"
    $mutex = $null
    $acquired = $false
    $waitTimer = [System.Diagnostics.Stopwatch]::new()
    $cacheAvailable = $null -ne (Get-Command -Name 'Set-PSUCache' -ErrorAction SilentlyContinue) -and
    $null -ne (Get-Command -Name 'Get-PSUCache' -ErrorAction SilentlyContinue) -and
    $null -ne (Get-Command -Name 'Remove-PSUCache' -ErrorAction SilentlyContinue)
    $workerProcesses = @(Get-Process -Name 'Universal*', 'PowerShellUniversal*' -ErrorAction SilentlyContinue |
            Select-Object -ExpandProperty Id)

    $sharedState = [ordered]@{
        Ran = $true
        Role = $SharedStateRole
        ProbeHash = $probeHash
        CacheCmdletsAvailable = $cacheAvailable
        MutexName = $mutexName
        MutexAcquired = $false
        MutexWaitMilliseconds = $null
        CacheVisibleBeforeMutex = $null
        CounterBefore = $null
        CounterAfter = $null
        ObservedInitializerState = $null
        CacheRoundTripSucceeded = $null
        CachePersistedAfterRestart = $null
        CleanupSucceeded = $null
        ObservedProcessId = $PID
        CandidateWorkerProcessIds = $workerProcesses
        CandidateWorkerProcessCount = $workerProcesses.Count
        ErrorType = $null
    }

    try {
        if (-not $cacheAvailable) {
            throw 'The integrated PSU cache commands are unavailable on this execution surface.'
        }

        if ($SharedStateRole -eq 'Cleanup') {
            Remove-PSUCache -Key $cacheKey -Integrated -ErrorAction SilentlyContinue
            $sharedState.CleanupSucceeded = $null -eq (Get-PSUCache -Key $cacheKey -Integrated)
        } elseif ($SharedStateRole -eq 'RestartCheck') {
            $restartState = Get-PSUCache -Key $cacheKey -Integrated
            $sharedState.CachePersistedAfterRestart = $null -ne $restartState
            Remove-PSUCache -Key $cacheKey -Integrated -ErrorAction SilentlyContinue
            $sharedState.CleanupSucceeded = $null -eq (Get-PSUCache -Key $cacheKey -Integrated)
        } else {
            $beforeMutex = Get-PSUCache -Key $cacheKey -Integrated
            $sharedState.CacheVisibleBeforeMutex = $null -ne $beforeMutex

            $mutex = [System.Threading.Mutex]::new($false, $mutexName)
            $waitTimer.Start()
            $acquired = $mutex.WaitOne([TimeSpan]::FromSeconds($MutexHoldSeconds + 10))
            $waitTimer.Stop()
            $sharedState.MutexAcquired = $acquired
            $sharedState.MutexWaitMilliseconds = $waitTimer.ElapsedMilliseconds
            if (-not $acquired) {
                throw 'Timed out acquiring the shared-state evidence mutex.'
            }

            if ($SharedStateRole -in @('Initializer', 'RestartSeed')) {
                $token = [guid]::NewGuid().ToString()
                $state = [ordered]@{
                    SchemaVersion = '1.0'
                    Role = $SharedStateRole
                    Token = $token
                    Counter = 1
                    ProcessId = $PID
                    WrittenUtc = [datetime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
                }
                Set-PSUCache -Key $cacheKey -Value $state -Integrated
                $readBack = Get-PSUCache -Key $cacheKey -Integrated
                $sharedState.CounterAfter = if ($readBack) { [int]$readBack.Counter } else { $null }
                $sharedState.CacheRoundTripSucceeded = $null -ne $readBack -and $readBack.Token -eq $token
                if ($SharedStateRole -eq 'Initializer') {
                    Start-Sleep -Seconds $MutexHoldSeconds
                }
            } else {
                $current = Get-PSUCache -Key $cacheKey -Integrated
                $sharedState.ObservedInitializerState = $null -ne $beforeMutex -and $null -ne $current -and
                $beforeMutex.Token -eq $current.Token -and $current.Role -eq 'Initializer'
                if (-not $sharedState.ObservedInitializerState) {
                    throw 'Contender did not observe state written by Initializer.'
                }

                $sharedState.CounterBefore = [int]$current.Counter
                $current.Counter = $sharedState.CounterBefore + 1
                $current.Role = 'Contender'
                $current.ProcessId = $PID
                Set-PSUCache -Key $cacheKey -Value $current -Integrated
                $readBack = Get-PSUCache -Key $cacheKey -Integrated
                $sharedState.CounterAfter = if ($readBack) { [int]$readBack.Counter } else { $null }
                $sharedState.CacheRoundTripSucceeded = $null -ne $readBack -and
                $readBack.Token -eq $current.Token -and $readBack.Counter -eq 2
            }
        }
    } catch {
        $sharedState.ErrorType = $_.Exception.GetType().FullName
    } finally {
        if ($acquired -and $null -ne $mutex) { $mutex.ReleaseMutex() }
        if ($null -ne $mutex) { $mutex.Dispose() }
    }
} elseif ($SharedStateRole -or $SharedStateProbeId) {
    throw 'SharedStateRole and SharedStateProbeId are valid only with RunSharedStateTest.'
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
    ComparisonFingerprintsEnabled = $comparisonFingerprintsEnabled
    SanitizationNote = 'Claim and identity values and the comparison secret are never recorded. Fingerprints are cross-report comparable only when the same temporary ComparisonSecret was supplied.'
}
$script:Salt = $null

if (-not $OutputPath) {
    $stamp = [datetime]::UtcNow.ToString('yyyyMMdd-HHmmss')
    $safeLabel = ($SurfaceLabel -replace '[^A-Za-z0-9\-]', '_')
    $OutputPath = Join-Path ([System.IO.Path]::GetTempPath()) "psu-evidence-$safeLabel-$stamp.json"
}

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding utf8NoBOM

Write-Information '' -InformationAction Continue
Write-Information "Surface detected : $detectedSurface" -InformationAction Continue
Write-Information "ClaimsPrincipal  : $claimsPrincipalPresent" -InformationAction Continue
Write-Information "Claims found     : $($claims.Count)" -InformationAction Continue
Write-Information "PowerShell       : $($runtime.PowerShellVersion) on $($runtime.OSDescription)" -InformationAction Continue
Write-Information "Report written   : $OutputPath" -InformationAction Continue
Write-Information '' -InformationAction Continue
Write-Information 'Review the file before sharing it. It should contain no claim values.' -InformationAction Continue

$report
