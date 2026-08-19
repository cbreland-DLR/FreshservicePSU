<#
.SYNOPSIS
    Unit tests for New-FsuUri (ARCHITECTURE.md §11 "Pagination and
    embedding").
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repoRoot '0.1.6/Private/Errors/New-FsuErrorRecord.ps1')
    . (Join-Path $repoRoot '0.1.6/Private/Http/New-FsuUri.ps1')
    $script:baseUri = [System.Uri]'https://acme.freshservice.com/api/v2/'
}

Describe 'New-FsuUri path segment escaping' {

    It 'escapes a segment containing a slash so it cannot alter path structure' {
        $uri = New-FsuUri -BaseUri $baseUri -PathSegments @('tickets', '1/../../admin')
        $uri.AbsolutePath | Should -Not -Match '/admin'
        $uri.AbsolutePath | Should -Match ([regex]::Escape('1%2F..%2F..%2Fadmin'))
    }

    It 'escapes a segment containing spaces' {
        $uri = New-FsuUri -BaseUri $baseUri -PathSegments @('tickets', 'a b')
        $uri.AbsolutePath | Should -Match 'a%20b'
    }

    It 'escapes a segment containing Unicode characters' {
        $uri = New-FsuUri -BaseUri $baseUri -PathSegments @('tickets', 'café')
        $uri.AbsolutePath | Should -Not -Match 'café'
        $uri.AbsolutePath | Should -Match ([regex]::Escape([System.Uri]::EscapeDataString('café')))
    }

    It 'escapes a segment containing reserved characters (? and #)' {
        $uri = New-FsuUri -BaseUri $baseUri -PathSegments @('tickets', 'a?b#c')
        $uri.AbsolutePath | Should -Not -Match '\?'
        $uri.AbsolutePath | Should -Not -Match '#'
    }

    It 'refuses a segment that would resolve outside /api/v2/, rather than silently collapsing it' {
        # '..' still resolves (via UriBuilder path normalization) to a
        # location outside the base path even though it was escaped as an
        # opaque unit; New-FsuUri's post-build containment check catches
        # this and fails closed rather than silently returning an escaped
        # URI.
        $errorId = $null
        try {
            New-FsuUri -BaseUri $baseUri -PathSegments @('..', '..', 'admin') | Out-Null
        } catch {
            $errorId = $_.FullyQualifiedErrorId
        }
        $errorId | Should -Match 'FreshservicePSU\.Http\.PathEscape'
    }

}

Describe 'New-FsuUri query parameters' {

    It 'encodes a scalar query value' {
        $uri = New-FsuUri -BaseUri $baseUri -PathSegments @('tickets') -QueryParameters @{ email = 'a b@example.com' }
        $uri.Query | Should -Match 'a%20b%40example\.com'
    }

    It 'supports array query values as repeated keys' {
        $uri = New-FsuUri -BaseUri $baseUri -PathSegments @('tickets') -QueryParameters @{ status = @(2, 3) }
        $uri.Query | Should -Match 'status=2'
        $uri.Query | Should -Match 'status=3'
    }

    Context 'per_page bounds' {
        It 'rejects per_page 0' {
            { New-FsuUri -BaseUri $baseUri -PathSegments @('tickets') -QueryParameters @{ per_page = 0 } } | Should -Throw
        }
        It 'accepts per_page 1' {
            { New-FsuUri -BaseUri $baseUri -PathSegments @('tickets') -QueryParameters @{ per_page = 1 } } | Should -Not -Throw
        }
        It 'accepts per_page 100' {
            { New-FsuUri -BaseUri $baseUri -PathSegments @('tickets') -QueryParameters @{ per_page = 100 } } | Should -Not -Throw
        }
        It 'rejects per_page 101' {
            { New-FsuUri -BaseUri $baseUri -PathSegments @('tickets') -QueryParameters @{ per_page = 101 } } | Should -Throw
        }
    }

    Context 'page ceiling' {
        It 'accepts page 500' {
            { New-FsuUri -BaseUri $baseUri -PathSegments @('tickets') -QueryParameters @{ page = 500 } } | Should -Not -Throw
        }
        It 'refuses page 501 with a normalized error' {
            $errorId = $null
            try {
                New-FsuUri -BaseUri $baseUri -PathSegments @('tickets') -QueryParameters @{ page = 501 } | Out-Null
            } catch {
                $errorId = $_.FullyQualifiedErrorId
            }
            $errorId | Should -Match 'FreshservicePSU\.Http\.PageTooLarge'
        }
    }
}

Describe 'New-FsuUri stays within the base URI' {
    It 'result path always begins with /api/v2/' {
        $uri = New-FsuUri -BaseUri $baseUri -PathSegments @('tickets', '42')
        $uri.AbsolutePath | Should -Match '^/api/v2/tickets/42$'
    }
}
