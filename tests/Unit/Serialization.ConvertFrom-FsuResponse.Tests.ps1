<#
.SYNOPSIS
    Unit tests for ConvertFrom-FsuResponse (ARCHITECTURE.md §10, §11).
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repoRoot 'FreshservicePSU/Private/Errors/New-FsuErrorRecord.ps1')
    . (Join-Path $repoRoot 'FreshservicePSU/Private/Serialization/ConvertFrom-FsuResponse.ps1')
}

Describe 'ConvertFrom-FsuResponse explicit envelope extraction' {

    It 'extracts the named envelope property' {
        $body = [pscustomobject]@{ ticket = [pscustomobject]@{ id = 7; subject = 'hi' } }
        $result = ConvertFrom-FsuResponse -Body $body -EnvelopeProperty 'ticket' -PSTypeName 'FreshservicePSU.Ticket'
        $result.id | Should -Be 7
    }

    It 'applies the given PSTypeName to the emitted record' {
        $body = [pscustomobject]@{ ticket = [pscustomobject]@{ id = 7 } }
        $result = ConvertFrom-FsuResponse -Body $body -EnvelopeProperty 'ticket' -PSTypeName 'FreshservicePSU.Ticket'
        $result.PSObject.TypeNames | Should -Contain 'FreshservicePSU.Ticket'
    }

    It 'applies the PSTypeName to every item of a collection envelope' {
        $body = [pscustomobject]@{ tickets = @([pscustomobject]@{ id = 1 }, [pscustomobject]@{ id = 2 }) }
        $result = @(ConvertFrom-FsuResponse -Body $body -EnvelopeProperty 'tickets' -PSTypeName 'FreshservicePSU.Ticket')
        $result.Count | Should -Be 2
        foreach ($item in $result) {
            $item.PSObject.TypeNames | Should -Contain 'FreshservicePSU.Ticket'
        }
    }

    It 'does not infer the envelope from the first property when a different one is requested' {
        # 'meta' is first in property order but 'ticket' is requested; a
        # first-property-inference bug would silently return the wrong data.
        $body = [ordered]@{ meta = [pscustomobject]@{ count = 1 }; ticket = [pscustomobject]@{ id = 99 } }
        $result = ConvertFrom-FsuResponse -Body ([pscustomobject]$body) -EnvelopeProperty 'ticket' -PSTypeName 'FreshservicePSU.Ticket'
        $result.id | Should -Be 99
    }

    It 'throws a terminating error, not an empty result, when the envelope property is missing' {
        $body = [pscustomobject]@{ unrelated = 'x' }
        { ConvertFrom-FsuResponse -Body $body -EnvelopeProperty 'ticket' -PSTypeName 'FreshservicePSU.Ticket' } | Should -Throw
    }

    It 'the missing-envelope error carries the FreshservicePSU.Serialization.MissingEnvelopeProperty id' {
        $body = [pscustomobject]@{ unrelated = 'x' }
        $errorId = $null
        try {
            ConvertFrom-FsuResponse -Body $body -EnvelopeProperty 'ticket' -PSTypeName 'FreshservicePSU.Ticket' | Out-Null
        } catch {
            $errorId = $_.FullyQualifiedErrorId
        }
        $errorId | Should -Match 'FreshservicePSU\.Serialization\.MissingEnvelopeProperty'
    }
}

Describe 'ConvertFrom-FsuResponse null passthrough' {
    It 'passes a null Body through unchanged, never coerced to empty string or $false' {
        $result = ConvertFrom-FsuResponse -Body $null -EnvelopeProperty 'ticket' -PSTypeName 'FreshservicePSU.Ticket'
        $null -eq $result | Should -Be $true
    }
}

Describe 'ConvertFrom-FsuResponse embedded (include) properties' {
    It 'keeps the same PSTypeName with an embedded property present' {
        $body = [pscustomobject]@{
            ticket = [pscustomobject]@{ id = 7; requester = [pscustomobject]@{ id = 3; name = 'Jo' } }
        }
        $result = ConvertFrom-FsuResponse -Body $body -EnvelopeProperty 'ticket' -PSTypeName 'FreshservicePSU.Ticket'
        $result.PSObject.TypeNames | Should -Contain 'FreshservicePSU.Ticket'
        $result.requester.id | Should -Be 3
    }

    It 'extracts the embedded property by name like any other property' {
        $body = [pscustomobject]@{
            ticket = [pscustomobject]@{ id = 7; requester = [pscustomobject]@{ id = 3; name = 'Jo' } }
        }
        $result = ConvertFrom-FsuResponse -Body $body -EnvelopeProperty 'ticket' -PSTypeName 'FreshservicePSU.Ticket'
        $result.requester.name | Should -Be 'Jo'
    }
}
