function Test-FsuTicketCustomField {
    <#
    .SYNOPSIS
        Rejects custom-field keys that are not ticket form field names.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [System.Collections.IDictionary]$CustomFields,

        [string]$CorrelationId
    )

    if ($null -eq $CustomFields -or $CustomFields.Count -eq 0) {
        throw (New-FsuErrorRecord -ErrorId 'FreshservicePSU.Ticket.CustomFieldsEmpty' -Message 'CustomFields must contain at least one field name.' -Category InvalidArgument -CorrelationId $CorrelationId)
    }

    $known = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($field in @(Get-FreshServiceTicketField)) {
        if ($null -ne $field -and -not [string]::IsNullOrWhiteSpace([string]$field.Name)) {
            [void]$known.Add([string]$field.Name)
        }
    }

    foreach ($key in @($CustomFields.Keys)) {
        $name = [string]$key
        if ([string]::IsNullOrWhiteSpace($name) -or -not $known.Contains($name)) {
            throw (New-FsuErrorRecord -ErrorId 'FreshservicePSU.Ticket.UnknownCustomField' -Message "The custom field '$name' is not a ticket form field." -Category InvalidArgument -CorrelationId $CorrelationId -Field $name)
        }
    }
}
