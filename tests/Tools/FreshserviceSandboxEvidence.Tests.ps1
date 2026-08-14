BeforeAll {
    $repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $toolPath = Join-Path $repositoryRoot 'tools/Get-FreshserviceSandboxEvidence.ps1'
    $sandboxKey = [securestring]::new()
    foreach ($character in 'unit-test-api-key'.ToCharArray()) {
        $sandboxKey.AppendChar($character)
    }
    $sandboxKey.MakeReadOnly()
}

Describe 'Get-FreshserviceSandboxEvidence' {
    It 'rejects a non-Freshservice API host before making a request' {
        {
            & $toolPath -Scenario CorrelationHeader -BaseUri 'https://example.test/api/v2/' `
                -SurfaceLabel 'invalid-host' -ApiKey $sandboxKey
        } | Should -Throw '*BaseUri must be*'
    }

    It 'blocks ticket-note creation without explicit acknowledgement' {
        {
            & $toolPath -Scenario TicketNote `
                -BaseUri 'https://sandbox.freshservice.com/api/v2/' `
                -SurfaceLabel 'missing-ack' -ApiKey $sandboxKey -TicketId 123
        } | Should -Throw '*AcknowledgeWrite*'
    }

    It 'summarizes nested authorship and paging without response values' {
        Mock Invoke-WebRequest {
            [pscustomobject]@{
                StatusCode = 201
                Headers = @{
                    Link = '<https://sandbox.freshservice.com/api/v2/tickets/123/notes?page=2>; rel="next"'
                    'X-Total-Count' = '99'
                }
                Content = '{"conversation":{"user_id":456,"body":"private response text","nested":{"agent_id":456}}}'
            }
        }

        $outputPath = Join-Path $TestDrive 'note.json'
        & $toolPath -Scenario TicketNote `
            -BaseUri 'https://sandbox.freshservice.com/api/v2/' `
            -SurfaceLabel 'Q7-ValidUser' -ApiKey $sandboxKey -TicketId 123 `
            -UserId 456 -ExpectedAuthorId 456 -AcknowledgeWrite -OutputPath $outputPath

        $raw = Get-Content -LiteralPath $outputPath -Raw
        $report = $raw | ConvertFrom-Json -Depth 32
        $report.Result.ExpectedAuthorMatched | Should -BeTrue
        $report.Result.NoteAuthorPropertyPaths | Should -Contain '$.conversation.user_id'
        $report.Result.NoteAuthorPropertyPaths | Should -Contain '$.conversation.nested.agent_id'
        $report.Result.PaginationHeaderNames | Should -Contain 'Link'
        $report.Result.LinkRelations | Should -Contain 'next'
        $raw | Should -Not -Match 'private response text|unit-test-api-key|tickets/123|page=2|X-Total-Count.*99'
    }

    It 'records correlation acceptance and matching response-header names only' {
        Mock Invoke-WebRequest {
            param($Uri, $Headers)
            $null = $Uri
            [pscustomobject]@{
                StatusCode = 200
                Headers = @{ 'X-Correlation-ID' = $Headers['X-Correlation-ID'] }
                Content = '{"agents":[]}'
            }
        }

        $outputPath = Join-Path $TestDrive 'correlation.json'
        & $toolPath -Scenario CorrelationHeader `
            -BaseUri 'https://sandbox.freshservice.com/api/v2/' `
            -SurfaceLabel 'Correlation' -ApiKey $sandboxKey -OutputPath $outputPath

        $raw = Get-Content -LiteralPath $outputPath -Raw
        $report = $raw | ConvertFrom-Json -Depth 32
        $report.Result.CorrelationHeaderAccepted | Should -BeTrue
        $report.Result.CorrelationEchoHeaderNames | Should -Contain 'X-Correlation-ID'
        $raw | Should -Not -Match '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
    }

    It 'records only the transport error type when a request fails' {
        Mock Invoke-WebRequest { throw [System.Net.Http.HttpRequestException]::new('URI contains sensitive-filter-value') }

        $outputPath = Join-Path $TestDrive 'transport-error.json'
        & $toolPath -Scenario ApprovalSearch `
            -BaseUri 'https://sandbox.freshservice.com/api/v2/' `
            -SurfaceLabel 'Q8-TransportError' -ApiKey $sandboxKey `
            -ApprovalQuery 'filter=sensitive-filter-value' -OutputPath $outputPath

        $raw = Get-Content -LiteralPath $outputPath -Raw
        $report = $raw | ConvertFrom-Json
        $report.Result.TransportErrorType | Should -Be 'System.Net.Http.HttpRequestException'
        $raw | Should -Not -Match 'sensitive-filter-value'
    }
}
