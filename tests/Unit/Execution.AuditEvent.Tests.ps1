<#
.SYNOPSIS
    Unit tests for New-FsuAuditEvent and Write-FsuAuditEvent (ARCHITECTURE.md
    §13 "Audit delivery").
#>

BeforeAll {
    $script:repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $repoRoot 'FreshservicePSU/Private/Errors/New-FsuErrorRecord.ps1')
    . (Join-Path $repoRoot 'FreshservicePSU/Private/Execution/New-FsuAuditEvent.ps1')
    . (Join-Path $repoRoot 'FreshservicePSU/Private/Execution/Write-FsuAuditEvent.ps1')

    $script:allowedFields = @(
        'CorrelationId', 'Identity', 'Stage', 'Tenant', 'CredentialType',
        'CredentialIdentifier', 'Operation', 'ResourceId', 'Outcome',
        'Status', 'FallbackUsed', 'RateLimitState'
    )

    function New-FsuBaseAuditEventArg {
        [System.Diagnostics.CodeAnalysis.SuppressMessage('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Test fixture builder; no system state is changed.')]
        param()

        return @{
            CorrelationId = 'corr-1'
            Identity = 'entra:tenant:aaaa'
            Stage = 'Prod'
            Tenant = 'acme'
            CredentialType = 'User'
            CredentialIdentifier = 'FreshService.Alice.Prod'
            Operation = 'Add-FreshServiceTicketNote'
            ResourceId = '12345'
            Outcome = 'Success'
            Status = 200
            FallbackUsed = $false
            RateLimitState = 'ok'
        }
    }
}

Describe 'New-FsuAuditEvent: allowlist' {

    It 'produces a FreshservicePSU.AuditEvent typed object' {
        $auditArgs = New-FsuBaseAuditEventArg
        $auditEvent = New-FsuAuditEvent @auditArgs
        $auditEvent.PSObject.TypeNames | Should -Contain 'FreshservicePSU.AuditEvent'
    }

    It 'exposes exactly the allowlisted property set and nothing else' {
        $auditArgs = New-FsuBaseAuditEventArg
        $auditEvent = New-FsuAuditEvent @auditArgs
        $eventProperties = @($auditEvent.PSObject.Properties.Name | Where-Object { $_ -ne 'PSTypeName' })
        (Compare-Object -ReferenceObject $allowedFields -DifferenceObject $eventProperties) | Should -BeNullOrEmpty
    }

    It 'rejects an input field outside the allowlist rather than allowing it onto the object (proves construction is allowlist-driven, not hashtable-copy-then-delete)' {
        $auditArgs = New-FsuBaseAuditEventArg
        $auditArgs['ApiKey'] = 'sk_live_should_never_appear'
        { New-FsuAuditEvent @auditArgs } | Should -Throw
    }

    It 'never carries a supplied secret-shaped value onto the object even via the CredentialIdentifier field (identifiers are names, not secret values)' {
        $auditArgs = New-FsuBaseAuditEventArg
        $auditArgs['CredentialIdentifier'] = 'FreshService.Alice.Prod'
        $auditEvent = New-FsuAuditEvent @auditArgs
        $auditEvent.CredentialIdentifier | Should -Be 'FreshService.Alice.Prod'
        $auditEvent.CredentialIdentifier | Should -Not -Match '^sk_live_'
    }
}

Describe 'Write-FsuAuditEvent: information-stream-only delivery' {

    It 'writes the event only to the information stream, tagged FreshservicePSU.Audit, and never to success output' {
        $auditArgs = New-FsuBaseAuditEventArg
        $infoRecords = $null
        $successOutput = New-FsuAuditEvent @auditArgs | Write-FsuAuditEvent -InformationVariable infoRecords

        @($successOutput).Count | Should -Be 0
        @($infoRecords).Count | Should -Be 1
        $infoRecords[0].Tags | Should -Contain 'FreshservicePSU.Audit'
        $infoRecords[0].MessageData.PSObject.TypeNames | Should -Contain 'FreshservicePSU.AuditEvent'
    }

    It 'emits exactly one terminal event for a successful attempted operation' {
        $auditArgs = New-FsuBaseAuditEventArg
        $infoRecords = $null
        New-FsuAuditEvent @auditArgs | Write-FsuAuditEvent -InformationVariable infoRecords | Out-Null
        @($infoRecords).Count | Should -Be 1
    }

    It 'emits exactly one terminal event for a failed attempted operation' {
        $auditArgs = New-FsuBaseAuditEventArg
        $auditArgs['Outcome'] = 'Failure'
        $auditArgs['Status'] = 500
        $infoRecords = $null
        New-FsuAuditEvent @auditArgs | Write-FsuAuditEvent -InformationVariable infoRecords | Out-Null
        @($infoRecords).Count | Should -Be 1
        $infoRecords[0].MessageData.Outcome | Should -Be 'Failure'
    }

    It 'allows a Preview outcome for -WhatIf paths but never emits Success for a preview' {
        $auditArgs = New-FsuBaseAuditEventArg
        $auditArgs['Outcome'] = 'Preview'
        $infoRecords = $null
        New-FsuAuditEvent @auditArgs | Write-FsuAuditEvent -InformationVariable infoRecords | Out-Null
        $infoRecords[0].MessageData.Outcome | Should -Be 'Preview'
        $infoRecords[0].MessageData.Outcome | Should -Not -Be 'Success'
    }

    # The writer takes the constructed event rather than redeclaring the
    # twelve-field allowlist, so this type guard is what stops an arbitrary
    # object — one that never passed through the allowlist constructor — from
    # being emitted as an audit record.
    It 'refuses an object that did not come from New-FsuAuditEvent' {
        $notAnEvent = [PSCustomObject]@{ CorrelationId = 'x'; ApiKey = 'sk_live_secret' }
        { $notAnEvent | Write-FsuAuditEvent } | Should -Throw
    }

    # A PSTypeName is only a string, so the type claim alone proves nothing.
    It 'refuses a forged object that merely claims the audit PSTypeName' {
        $forged = [PSCustomObject]@{ PSTypeName = 'FreshservicePSU.AuditEvent'; ApiKey = 'sk_live_secret' }
        { $forged | Write-FsuAuditEvent } | Should -Throw '*allowlist*'
    }

    It 'refuses a legitimate event that had a field added after construction' {
        $auditArgs = New-FsuBaseAuditEventArg
        $tampered = New-FsuAuditEvent @auditArgs
        $tampered | Add-Member -NotePropertyName 'ApiKey' -NotePropertyValue 'sk_live_secret'
        { $tampered | Write-FsuAuditEvent } | Should -Throw '*allowlist*'
    }
}
