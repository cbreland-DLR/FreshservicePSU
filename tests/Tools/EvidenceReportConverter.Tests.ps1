BeforeAll {
    $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $toolPath = Join-Path $repositoryRoot 'tools/ConvertFrom-FsuEvidenceReport.ps1'
}

Describe 'ConvertFrom-FsuEvidenceReport' {
    It 'produces review-only Markdown without fingerprints, process IDs, or response values' {
        $psuReport = [ordered]@{
            SchemaVersion = '1.0'
            CollectedUtc = '2026-08-13T12:00:00Z'
            SurfaceLabel = 'API-SAML-UserA'
            DetectedSurface = 'API endpoint'
            Runtime = @{ PowerShellVersion = '7.6.4'; OSDescription = 'Test OS'; ProcessId = 9876 }
            Variables = @(@{ Name = '$Identity'; Present = $true; Type = 'System.String'; Detail = 'fingerprint abcdef12' })
            JobIdentity = $null
            ClaimsPrincipalPresent = $true
            ClaimSummary = @{ AuthenticationType = 'SAML' }
            Claims = @(@{ Type = 'claim/type'; Issuer = 'tenant-secret'; Fingerprint = 'abcdef12' })
            SanitizationNote = 'safe'
        }
        $freshserviceReport = [ordered]@{
            SchemaVersion = '1.0'
            CollectedUtc = '2026-08-13T12:01:00Z'
            SurfaceLabel = 'Q7-ValidUser'
            Scenario = 'TicketNote'
            Request = @{ Method = 'Post'; EndpointTemplate = 'tickets/{ticket_id}/notes' }
            Result = @{
                HttpStatusCode = 201
                TransportErrorType = $null
                ResponseHeaderNames = @('Link')
                PaginationHeaderNames = @('Link')
                LinkRelations = @('next')
                BodyShape = @{ Kind = 'Object'; Properties = @(@{ Name = 'conversation'; Shape = @{ Kind = 'Object'; Properties = @() } }) }
                NoteAuthorPropertyPaths = @('$.conversation.user_id')
                NoteAuthorFingerprints = @('1234abcd')
                ExpectedAuthorMatched = $true
                CorrelationHeaderAccepted = $null
                CorrelationEchoHeaderNames = @()
                RawResponseValue = 'must-not-appear'
            }
            SanitizationNote = 'safe'
        }
        $psuPath = Join-Path $TestDrive 'psu.json'
        $freshservicePath = Join-Path $TestDrive 'freshservice.json'
        $summaryPath = Join-Path $TestDrive 'summary.md'
        $psuReport | ConvertTo-Json -Depth 10 | Set-Content $psuPath
        $freshserviceReport | ConvertTo-Json -Depth 10 | Set-Content $freshservicePath

        & $toolPath -Path $psuPath, $freshservicePath -OutputPath $summaryPath

        $summary = Get-Content -LiteralPath $summaryPath -Raw
        $summary | Should -Match 'Review-only observations'
        $summary | Should -Match 'API-SAML-UserA'
        $summary | Should -Match 'Q7-ValidUser'
        $summary | Should -Match '\$\.conversation\.user_id'
        $summary | Should -Not -Match 'abcdef12|9876|tenant-secret|1234abcd|must-not-appear'
    }

    It 'rejects an unexpected top-level field' {
        $reportPath = Join-Path $TestDrive 'unsafe.json'
        @{
            SchemaVersion = '1.0'
            SurfaceLabel = 'unsafe'
            Scenario = 'TicketNote'
            Request = @{}
            Result = @{}
            SanitizationNote = 'safe'
            RawToken = 'secret'
        } | ConvertTo-Json | Set-Content $reportPath

        { & $toolPath -Path $reportPath -OutputPath (Join-Path $TestDrive 'unsafe.md') } |
            Should -Throw '*unexpected top-level fields*'
    }

    It 'rejects unknown report schemas' {
        $reportPath = Join-Path $TestDrive 'unknown.json'
        @{ SchemaVersion = '99.0'; SurfaceLabel = 'unknown' } |
            ConvertTo-Json | Set-Content $reportPath

        { & $toolPath -Path $reportPath -OutputPath (Join-Path $TestDrive 'unknown.md') } |
            Should -Throw '*Unsupported or missing evidence schema*'
    }
}
