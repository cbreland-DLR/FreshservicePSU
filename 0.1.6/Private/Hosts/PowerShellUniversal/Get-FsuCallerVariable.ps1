function Get-FsuCallerVariable {
    <#
    .SYNOPSIS
        Reads a caller-scope variable without creating it.

    .DESCRIPTION
        PowerShell Universal injects identity and configuration values into
        the invoking script, API, or app scope. Module functions cannot see
        those names locally, so this helper walks parent scopes. It never
        creates a variable and never treats a missing name as an empty
        string: Found is false when the name is absent and true when it
        exists even if the value is $null (for example $User with
        authentication disabled).
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    for ($scope = 1; $scope -le 16; $scope++) {
        try {
            $variable = Get-Variable -Name $Name -Scope $scope -ErrorAction Stop
            return [PSCustomObject]@{
                PSTypeName = 'Freshservice.CallerVariable'
                Found = $true
                Value = $variable.Value
            }
        } catch [System.Management.Automation.ItemNotFoundException] {
            continue
        } catch [System.ArgumentOutOfRangeException] {
            break
        } catch {
            $id = [string]$_.FullyQualifiedErrorId
            if ($id -match 'ScopeIsNotDefined|ArgumentOutOfRange|PSArgumentOutOfRange') {
                break
            }
            # Never log $_ or the variable value here -- it may be
            # configuration or a secret. Record only the error id so an
            # unexpected failure (which silently reports Found=$false) is
            # discoverable.
            Write-Verbose "Get-FsuCallerVariable: unexpected error at scope $scope for '$Name' (FullyQualifiedErrorId: $id)."
        }
    }

    return [PSCustomObject]@{
        PSTypeName = 'Freshservice.CallerVariable'
        Found = $false
        Value = $null
    }
}
