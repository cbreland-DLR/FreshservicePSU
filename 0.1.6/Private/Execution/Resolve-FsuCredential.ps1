function Resolve-FsuCredential {
    <#
    .SYNOPSIS
        Selects the personal or system Freshservice credential (ARCHITECTURE.md §8).

    .DESCRIPTION
        Runs only after the trusted PSU identity has been normalized.
        Interactive callers with a working personal mapping use that secret.
        Interactive callers without a mapping use the system secret only when
        fallback is allowed. A mapped personal secret that cannot be loaded
        fails and never falls back. Noninteractive (system) execution always
        uses the stage default secret. Secret names that embed a stage label
        must match the configured stage so prod cannot resolve a dev secret.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        $Principal,

        [Parameter(Mandatory)]
        $Configuration,

        [scriptblock]$SecretResolver,

        # Delegated per-user secret NAME forwarded by a trusted first-party job.
        # The calling app resolves the signed-in user in its own interactive
        # context (where $ClaimsPrincipal is verified) and passes only the secret
        # name; the value stays in the vault. Honored ONLY on the non-interactive
        # (System) path so a live interactive caller can never be overridden.
        [string]$ActingSecretName,

        [string]$CorrelationId
    )

    function Get-FsuCredentialErrorRecord {
        param(
            [Parameter(Mandatory)]
            [string]$Id,

            [Parameter(Mandatory)]
            [string]$Message,

            [string]$CorrelationId
        )

        New-FsuErrorRecord -ErrorId "FreshservicePSU.Credential.$Id" -Message $Message -Category AuthenticationError -CorrelationId $CorrelationId
    }

    function Get-FsuMappedSecretName {
        param(
            $Users,

            [Parameter(Mandatory)]
            [string]$PrincipalId
        )

        foreach ($key in @($Users.Keys)) {
            if ([string]::Equals([string]$key, $PrincipalId, [System.StringComparison]::OrdinalIgnoreCase)) {
                return [string]$Users[$key]
            }
        }

        return $null
    }

    function Get-FsuSecretStageLabel {
        param([Parameter(Mandatory)][string]$Name)

        # Case-insensitive and covers both explicit separators ('.', '-', '_')
        # and camelCase word boundaries: 'freshservice-prod-key',
        # 'Freshservice.PROD.Key', and 'fsProdKey' must all be recognized as
        # Prod-labeled so the stage-affinity guard below cannot be silently
        # bypassed by casing, separator, or naming-convention choice. An
        # unlabeled name (no part matches either label) still returns $null
        # and remains allowed -- unlabeled names are not an error.
        # -creplace (case-sensitive) is required here: the default
        # case-insensitive -replace would treat [A-Z] as matching lowercase
        # too, inserting a boundary between every character instead of only
        # at genuine camelCase transitions.
        $wordBoundaried = $Name -creplace '(?<=[a-z0-9])(?=[A-Z])', '_'
        $label = $null
        foreach ($part in @($wordBoundaried -split '[.\-_]')) {
            if ($part -eq 'Prod') {
                $label = 'Prod'
            } elseif ($part -eq 'Dev') {
                $label = 'Dev'
            }
        }

        return $label
    }

    function Test-FsuSecretStageAffinity {
        param(
            [Parameter(Mandatory)]
            [string]$Name,

            [Parameter(Mandatory)]
            [string]$Stage,

            [string]$CorrelationId
        )

        $label = Get-FsuSecretStageLabel -Name $Name
        if ($null -ne $label -and $label -ne $Stage) {
            throw (Get-FsuCredentialErrorRecord -Id 'StageMismatch' -Message 'The resolved secret reference is not valid for the configured stage.' -CorrelationId $CorrelationId)
        }
    }

    $executionType = [string]$Principal.ExecutionType
    $credentialType = 'System'
    $secretName = [string]$Configuration.DefaultSecret
    $usedFallback = $false

    if ($executionType -eq 'Interactive') {
        $mappedName = Get-FsuMappedSecretName -Users $Configuration.Users -PrincipalId ([string]$Principal.PrincipalId)
        if (-not [string]::IsNullOrWhiteSpace($mappedName)) {
            $credentialType = 'User'
            $secretName = $mappedName
        } elseif ($Configuration.AllowSystemFallback) {
            $usedFallback = $true
        } else {
            throw (Get-FsuCredentialErrorRecord -Id 'FallbackDenied' -Message 'No personal credential is mapped for the authenticated caller and system fallback is not allowed.' -CorrelationId $CorrelationId)
        }
    } elseif (-not [string]::IsNullOrWhiteSpace($ActingSecretName)) {
        # Non-interactive delegated credential: a trusted first-party app resolved
        # the signed-in user in its own interactive context and forwarded the secret
        # name to this job. The name still goes through stage-affinity and the vault
        # resolver below; the raw key never crosses the app/job boundary. This is a
        # trust-the-caller boundary (a job that sets FreshServiceActingSecret asserts
        # which key to use), so gate WHO may start the job at the app/API layer.
        $credentialType = 'DelegatedUser'
        $secretName = $ActingSecretName
    }

    Test-FsuSecretStageAffinity -Name $secretName -Stage ([string]$Configuration.Stage) -CorrelationId $CorrelationId

    $secret = Get-FsuSecret -Name $secretName -Resolver $SecretResolver -CorrelationId $CorrelationId

    return [PSCustomObject]@{
        PSTypeName = 'Freshservice.ResolvedCredential'
        CredentialType = $credentialType
        SecretName = $secretName
        Secret = $secret
        UsedFallback = [bool]$usedFallback
    }
}
