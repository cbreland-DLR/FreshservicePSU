[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', '', Justification = 'Global scope is required so an invoked external script can see host identity variables.')]
param()

BeforeAll {
    $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $toolPath = Join-Path $repositoryRoot 'tools/Get-PsuIdentityEvidence.ps1'
}

AfterAll {
    Remove-Variable -Name ClaimsPrincipal -Scope Global -ErrorAction SilentlyContinue
}

Describe 'Get-PsuIdentityEvidence' {
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
}
