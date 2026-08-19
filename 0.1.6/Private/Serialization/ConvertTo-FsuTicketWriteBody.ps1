function ConvertTo-FsuTicketWriteBody {
    <#
    .SYNOPSIS
        Builds a ticket create/update body from bound public parameters.
    #>
    [CmdletBinding()]
    [OutputType([hashtable])]
    param(
        [Parameter(Mandatory)]
        [System.Collections.IDictionary]$BoundParameters,

        [string[]]$Exclude = @()
    )

    $vendorByParameter = [ordered]@{
        Subject = 'subject'
        Description = 'description'
        RequesterId = 'requester_id'
        Email = 'email'
        Status = 'status'
        Priority = 'priority'
        Type = 'type'
        Source = 'source'
        Urgency = 'urgency'
        Impact = 'impact'
        GroupId = 'group_id'
        AgentId = 'responder_id'
        Category = 'category'
        SubCategory = 'sub_category'
        ItemCategory = 'item_category'
        Tags = 'tags'
        DepartmentId = 'department_id'
        AssetDisplayId = 'assets'
        DueBy = 'due_by'
        FirstResponseDueBy = 'fr_due_by'
        CustomFields = 'custom_fields'
    }

    $body = @{}
    $boundVendorNames = [System.Collections.Generic.List[string]]::new()
    foreach ($parameterName in $vendorByParameter.Keys) {
        if ($parameterName -in $Exclude) {
            continue
        }
        if (-not $BoundParameters.ContainsKey($parameterName)) {
            continue
        }
        $vendorName = $vendorByParameter[$parameterName]
        # PowerShell unboxes a Nullable[T] parameter at bind time: a bound
        # GroupId/DepartmentId/DueBy/etc. arrives here as its concrete type
        # or $null (an explicit -GroupId $null), never as a boxed
        # Nullable[T]. No unwrap is needed -- the value from BoundParameters
        # is already the concrete value or $null exactly as intended for
        # JSON null vs. omission.
        $value = $BoundParameters[$parameterName]
        if ($parameterName -eq 'AssetDisplayId' -and $null -ne $value) {
            $value = @([long]$value)
        }
        if ($parameterName -eq 'Description' -and $null -ne $value) {
            $value = [string]$value
        }
        $body[$vendorName] = $value
        $boundVendorNames.Add($vendorName)
    }

    return @{
        Body = $body
        BoundVendorNames = @($boundVendorNames)
    }
}
