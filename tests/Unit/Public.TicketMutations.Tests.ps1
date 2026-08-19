<#
.SYNOPSIS
    Unit tests for ticket create, update, and note commands.
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $private = Join-Path $repoRoot '0.1.6/Private'
    . (Join-Path $private 'Errors/New-FsuErrorRecord.ps1')
    . (Join-Path $private 'Execution/New-FsuRetryPolicy.ps1')
    . (Join-Path $private 'Serialization/ConvertTo-FsuTicket.ps1')
    . (Join-Path $private 'Serialization/ConvertTo-FsuTicketNote.ps1')
    . (Join-Path $private 'Serialization/ConvertTo-FsuTicketWriteBody.ps1')
    . (Join-Path $PSScriptRoot 'FsuIdentityFixtures.ps1')

    $script:moduleName = 'FreshservicePSU'
    Import-Module (Join-Path $repoRoot '0.1.6/FreshservicePSU.psd1') -Force
    $script:context = New-FsuTestContext
}

AfterAll {
    Remove-Module -Name $moduleName -Force -ErrorAction SilentlyContinue
}

Describe 'Ticket mutations are exported without secret parameters' {
    It '<Name> is exported and supports ShouldProcess' -ForEach @(
        @{ Name = 'New-FreshServiceTicket' }
        @{ Name = 'Set-FreshServiceTicket' }
        @{ Name = 'Add-FreshServiceTicketNote' }
    ) {
        (Get-Command -Name $Name -Module $moduleName).Name | Should -Be $Name
        $keys = (Get-Command $Name).Parameters.Keys
        @('Tenant', 'Stage', 'BaseUri', 'ApiKey', 'Secret', 'WorkspaceId') |
            ForEach-Object { $keys | Should -Not -Contain $_ }
        $keys | Should -Contain 'WhatIf'
    }
}

Describe 'ConvertTo-FsuTicketNote: Q13 contract' {
    It 'maps body_text and ticket id' {
        $note = ConvertTo-FsuTicketNote -TicketId 51 -InputObject ([PSCustomObject]@{
                id = 4289856; private = $true; user_id = 1232463344; incoming = $false
                body = '<div>Hi</div>'; body_text = 'Hi'; ticket_id = 51
                created_at = '2021-04-12T06:44:09Z'; updated_at = '2021-04-12T06:44:09Z'
            })
        $note.PSObject.TypeNames | Should -Contain 'FreshservicePSU.TicketNote'
        $note.Body | Should -Be 'Hi'
        $note.TicketId | Should -Be 51
        $note.Private | Should -BeTrue
        $note.CreatedAt | Should -BeOfType [datetime]
    }
}

Describe 'Ticket mutation pipeline mapping' {
    BeforeEach {
        Mock -ModuleName $moduleName Get-FsuExecutionContext { $script:context }
    }

    It 'creates a ticket with email and only bound fields' {
        Mock -ModuleName $moduleName Invoke-FsuRequest {
            [PSCustomObject]@{
                id = 265; subject = 'VPN'; status = 2; priority = 1; type = 'Incident'
                requester_id = 1; created_at = '2017-09-08T10:34:28Z'; updated_at = '2017-09-08T10:34:28Z'
            }
        }

        $result = New-FreshServiceTicket -Email 'ada@contoso.com' -Subject 'VPN' -Description 'Cannot connect' -Priority 3
        $result.Subject | Should -Be 'VPN'
        $result.PSObject.TypeNames | Should -Contain 'FreshservicePSU.Ticket'

        Should -Invoke -ModuleName $moduleName -CommandName Invoke-FsuRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'POST' -and
            $PathSegments[0] -eq 'tickets' -and
            $Body['email'] -eq 'ada@contoso.com' -and
            $Body['subject'] -eq 'VPN' -and
            $Body['description'] -eq 'Cannot connect' -and
            $Body['priority'] -eq 3 -and
            $BoundParameterNames -contains 'email' -and
            $BoundParameterNames -notcontains 'status' -and
            -not $Body.ContainsKey('workspace_id')
        }
    }

    It 'does not send HTTP on New -WhatIf' {
        Mock -ModuleName $moduleName Invoke-FsuRequest { throw 'transport should not run' }
        Mock -ModuleName $moduleName Get-FsuExecutionContext { throw 'context should not run' }
        $null = New-FreshServiceTicket -Email 'ada@contoso.com' -Subject 'VPN' -Description 'Cannot connect' -WhatIf
        Should -Invoke -ModuleName $moduleName -CommandName Invoke-FsuRequest -Times 0
    }

    It 'updates only bound ticket fields and maps AgentId to responder_id' {
        Mock -ModuleName $moduleName Invoke-FsuRequest {
            [PSCustomObject]@{
                id = 265; subject = 'VPN'; status = 5; priority = 3; type = 'Incident'
                requester_id = 1; responder_id = $null
                created_at = '2017-09-08T10:34:28Z'; updated_at = '2017-09-08T10:34:28Z'
            }
        }

        $null = Set-FreshServiceTicket -TicketId 265 -Status 5 -AgentId $null
        Should -Invoke -ModuleName $moduleName -CommandName Invoke-FsuRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'PUT' -and
            $PathSegments[0] -eq 'tickets' -and
            $PathSegments[1] -eq '265' -and
            $Body['status'] -eq 5 -and
            $null -eq $Body['responder_id'] -and
            $BoundParameterNames -contains 'status' -and
            $BoundParameterNames -contains 'responder_id' -and
            $BoundParameterNames -notcontains 'subject'
        }
    }

    It 'rejects a ticket update with no property fields' {
        Mock -ModuleName $moduleName Invoke-FsuRequest { throw 'transport should not run' }
        { Set-FreshServiceTicket -TicketId 265 } | Should -Throw '*updatable ticket property*'
        Should -Invoke -ModuleName $moduleName -CommandName Invoke-FsuRequest -Times 0
    }

    It 'rejects unknown custom fields before transport' {
        Mock -ModuleName $moduleName Get-FreshServiceTicketField {
            [PSCustomObject]@{ Name = 'custom_text' }
        }
        Mock -ModuleName $moduleName Invoke-FsuRequest { throw 'transport should not run' }
        { New-FreshServiceTicket -Email 'ada@contoso.com' -Subject 'VPN' -Description 'x' -CustomFields @{ nope = 1 } } |
            Should -Throw '*custom field*'
        Should -Invoke -ModuleName $moduleName -CommandName Invoke-FsuRequest -Times 0
    }

    It 'rejects unknown custom fields on New -WhatIf without resolving an execution context' {
        # CustomFields validation is a read-only call (Get-FreshServiceTicketField)
        # and is documented to run before the request is sent, including
        # under -WhatIf. Get-FsuExecutionContext must not run for this: the
        # command should still return before ShouldProcess.
        Mock -ModuleName $moduleName Get-FreshServiceTicketField {
            [PSCustomObject]@{ Name = 'custom_text' }
        }
        Mock -ModuleName $moduleName Invoke-FsuRequest { throw 'transport should not run' }
        Mock -ModuleName $moduleName Get-FsuExecutionContext { throw 'context should not run' }
        { New-FreshServiceTicket -Email 'ada@contoso.com' -Subject 'VPN' -Description 'x' -CustomFields @{ nope = 1 } -WhatIf } |
            Should -Throw '*custom field*'
        Should -Invoke -ModuleName $moduleName -CommandName Invoke-FsuRequest -Times 0
    }

    It 'rejects unknown custom fields on Set -WhatIf without resolving an execution context' {
        Mock -ModuleName $moduleName Get-FreshServiceTicketField {
            [PSCustomObject]@{ Name = 'custom_text' }
        }
        Mock -ModuleName $moduleName Invoke-FsuRequest { throw 'transport should not run' }
        Mock -ModuleName $moduleName Get-FsuExecutionContext { throw 'context should not run' }
        { Set-FreshServiceTicket -TicketId 265 -CustomFields @{ nope = 1 } -WhatIf } |
            Should -Throw '*custom field*'
        Should -Invoke -ModuleName $moduleName -CommandName Invoke-FsuRequest -Times 0
    }

    It 'adds a note without user_id' {
        Mock -ModuleName $moduleName Invoke-FsuRequest {
            [PSCustomObject]@{
                id = 4289856; private = $true; user_id = 9; incoming = $false
                body_text = 'Checked'; ticket_id = 51
                created_at = '2021-04-12T06:44:09Z'; updated_at = '2021-04-12T06:44:09Z'
            }
        }

        $result = Add-FreshServiceTicketNote -TicketId 51 -Body 'Checked' -Private $true
        $result.Body | Should -Be 'Checked'
        $result.PSObject.TypeNames | Should -Contain 'FreshservicePSU.TicketNote'

        Should -Invoke -ModuleName $moduleName -CommandName Invoke-FsuRequest -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'POST' -and
            $PathSegments[0] -eq 'tickets' -and
            $PathSegments[1] -eq '51' -and
            $PathSegments[2] -eq 'notes' -and
            $Body['body'] -eq 'Checked' -and
            $Body['private'] -eq $true -and
            -not $Body.ContainsKey('user_id')
        }
    }

    It 'does not send HTTP on note -WhatIf' {
        Mock -ModuleName $moduleName Invoke-FsuRequest { throw 'transport should not run' }
        $null = Add-FreshServiceTicketNote -TicketId 51 -Body 'Checked' -WhatIf
        Should -Invoke -ModuleName $moduleName -CommandName Invoke-FsuRequest -Times 0
    }
}

Describe 'Set-FreshServiceTicket: Description JSON-null contract' {

    BeforeEach {
        Mock -ModuleName $moduleName Get-FsuExecutionContext { $script:context }
    }

    It 'omits description when not bound' {
        Mock -ModuleName $moduleName Invoke-FsuRequest {
            [PSCustomObject]@{ id = 265; status = 5 }
        }
        $null = Set-FreshServiceTicket -TicketId 265 -Status 5
        Should -Invoke -ModuleName $moduleName -CommandName Invoke-FsuRequest -Times 1 -Exactly -ParameterFilter {
            $BoundParameterNames -notcontains 'description' -and
            -not $Body.ContainsKey('description')
        }
    }

    It 'sends an explicit JSON null when bound as $null' {
        Mock -ModuleName $moduleName Invoke-FsuRequest {
            [PSCustomObject]@{ id = 265; description = $null }
        }
        $null = Set-FreshServiceTicket -TicketId 265 -Description $null
        Should -Invoke -ModuleName $moduleName -CommandName Invoke-FsuRequest -Times 1 -Exactly -ParameterFilter {
            $BoundParameterNames -contains 'description' -and
            $Body.ContainsKey('description') -and
            $null -eq $Body['description']
        }
    }

    It 'sends a bound string description' {
        Mock -ModuleName $moduleName Invoke-FsuRequest {
            [PSCustomObject]@{ id = 265; description = 'x' }
        }
        $null = Set-FreshServiceTicket -TicketId 265 -Description 'x'
        Should -Invoke -ModuleName $moduleName -CommandName Invoke-FsuRequest -Times 1 -Exactly -ParameterFilter {
            $Body['description'] -eq 'x'
        }
    }

    It 'rejects a non-string, non-null description with a normalized error' {
        Mock -ModuleName $moduleName Invoke-FsuRequest { throw 'transport should not run' }
        $caught = $null
        try {
            $null = Set-FreshServiceTicket -TicketId 265 -Description 123
        } catch {
            $caught = $_
        }
        $caught | Should -Not -BeNullOrEmpty
        $caught.FullyQualifiedErrorId | Should -Match 'FreshservicePSU\.Ticket\.InvalidDescription'
        $caught.CategoryInfo.Category | Should -Be 'InvalidArgument'
        Should -Invoke -ModuleName $moduleName -CommandName Invoke-FsuRequest -Times 0
    }
}
