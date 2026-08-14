[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Justification = 'Global scope is required so an invoked external script can see PSU command test doubles and host variables.')]
param()

BeforeAll {
    $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $toolPath = Join-Path $repositoryRoot 'tools/Get-PsuIdentityEvidence.ps1'
    $global:FsuEvidenceTestCache = @{}

    function global:Set-PSUCache {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Test double for a PSU command.')]
        param([string]$Key, [object]$Value, [switch]$Integrated)
        $null = $Integrated
        $global:FsuEvidenceTestCache[$Key] = $Value
    }

    function global:Get-PSUCache {
        param([string]$Key, [switch]$Integrated)
        $null = $Integrated
        return $global:FsuEvidenceTestCache[$Key]
    }

    function global:Remove-PSUCache {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Test double for a PSU command.')]
        param([string]$Key, [switch]$Integrated)
        $null = $Integrated
        $global:FsuEvidenceTestCache.Remove($Key)
    }
}

AfterAll {
    Remove-Item Function:/Set-PSUCache, Function:/Get-PSUCache, Function:/Remove-PSUCache -ErrorAction SilentlyContinue
    Remove-Variable -Name FsuEvidenceTestCache -Scope Global -ErrorAction SilentlyContinue
    Remove-Variable -Name ClaimsPrincipal -Scope Global -ErrorAction SilentlyContinue
}

Describe 'Get-PsuIdentityEvidence' {
    BeforeEach {
        $global:FsuEvidenceTestCache = @{}
    }

    AfterEach {
        Remove-Variable -Name ClaimsPrincipal -Scope Global -ErrorAction SilentlyContinue
    }

    It 'records claim shape without claim values' {
        $objectId = '11111111-2222-3333-4444-555555555555'
        $userName = 'evidence-user@example.test'
        $claims = [Collections.Generic.List[Security.Claims.Claim]]::new()
        $claims.Add([Security.Claims.Claim]::new('http://schemas.microsoft.com/identity/claims/objectidentifier', $objectId))
        $claims.Add([Security.Claims.Claim]::new('http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name', $userName))
        $identity = [Security.Claims.ClaimsIdentity]::new('SAML')
        $identity.AddClaims($claims)
        $global:ClaimsPrincipal = [Security.Claims.ClaimsPrincipal]::new($identity)

        $comparisonSecret = [securestring]::new()
        foreach ($character in 'temporary-comparison-secret'.ToCharArray()) {
            $comparisonSecret.AppendChar($character)
        }
        $comparisonSecret.MakeReadOnly()

        $outputPath = Join-Path $TestDrive 'identity.json'
        $secondOutputPath = Join-Path $TestDrive 'identity-second.json'
        $null = & $toolPath -SurfaceLabel 'API-SAML-UserA' -OutputPath $outputPath `
            -ComparisonSecret $comparisonSecret
        $null = & $toolPath -SurfaceLabel 'API-SAML-UserA-Repeat' -OutputPath $secondOutputPath `
            -ComparisonSecret $comparisonSecret

        $raw = Get-Content -LiteralPath $outputPath -Raw
        $report = $raw | ConvertFrom-Json
        $secondReport = Get-Content -LiteralPath $secondOutputPath -Raw | ConvertFrom-Json
        $report.ClaimSummary.HasObjectIdentifier | Should -BeTrue
        $report.ClaimSummary.HasRequiredNameClaim | Should -BeTrue
        $report.ComparisonFingerprintsEnabled | Should -BeTrue
        $report.Claims[0].Fingerprint | Should -Be $secondReport.Claims[0].Fingerprint
        $raw | Should -Not -Match ([regex]::Escape($objectId))
        $raw | Should -Not -Match ([regex]::Escape($userName))
        $raw | Should -Not -Match 'temporary-comparison-secret'
    }

    It 'uses one shared cache key for initializer and contender roles' {
        $probeId = 'unit-shared-probe'
        $initializerPath = Join-Path $TestDrive 'initializer.json'
        $contenderPath = Join-Path $TestDrive 'contender.json'

        $null = & $toolPath -SurfaceLabel 'Limiter-ProcessA' -OutputPath $initializerPath `
            -RunSharedStateTest -SharedStateProbeId $probeId `
            -SharedStateRole Initializer -MutexHoldSeconds 2
        $null = & $toolPath -SurfaceLabel 'Limiter-ProcessB' -OutputPath $contenderPath `
            -RunSharedStateTest -SharedStateProbeId $probeId `
            -SharedStateRole Contender -MutexHoldSeconds 2

        $initializer = Get-Content $initializerPath -Raw | ConvertFrom-Json
        $contender = Get-Content $contenderPath -Raw | ConvertFrom-Json
        $initializer.SharedState.CounterAfter | Should -Be 1
        $contender.SharedState.CacheVisibleBeforeMutex | Should -BeTrue
        $contender.SharedState.ObservedInitializerState | Should -BeTrue
        $contender.SharedState.CounterBefore | Should -Be 1
        $contender.SharedState.CounterAfter | Should -Be 2
        $contender.SharedState.CacheRoundTripSucceeded | Should -BeTrue
        $initializer.SharedState.ProbeHash | Should -Be $contender.SharedState.ProbeHash
    }

    It 'detects cleared restart state and cleans stale probe state' {
        $probeId = 'unit-restart-probe'
        $seedPath = Join-Path $TestDrive 'restart-seed.json'
        $checkPath = Join-Path $TestDrive 'restart-check.json'

        $null = & $toolPath -SurfaceLabel 'Limiter-RestartSeed' -OutputPath $seedPath `
            -RunSharedStateTest -SharedStateProbeId $probeId `
            -SharedStateRole RestartSeed
        $global:FsuEvidenceTestCache = @{}
        $null = & $toolPath -SurfaceLabel 'Limiter-RestartCheck' -OutputPath $checkPath `
            -RunSharedStateTest -SharedStateProbeId $probeId `
            -SharedStateRole RestartCheck

        $check = Get-Content $checkPath -Raw | ConvertFrom-Json
        $check.SharedState.CachePersistedAfterRestart | Should -BeFalse
        $check.SharedState.CleanupSucceeded | Should -BeTrue
    }

    It 'does not write the raw shared probe label to its report' {
        $outputPath = Join-Path $TestDrive 'cleanup.json'
        $null = & $toolPath -SurfaceLabel 'Limiter-Cleanup' -OutputPath $outputPath `
            -RunSharedStateTest -SharedStateProbeId 'private-operator-label' `
            -SharedStateRole Cleanup

        Get-Content -LiteralPath $outputPath -Raw | Should -Not -Match 'private-operator-label'
    }
}
