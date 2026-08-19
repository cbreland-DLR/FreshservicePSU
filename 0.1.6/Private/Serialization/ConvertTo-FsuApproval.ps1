function ConvertTo-FsuApproval {
    <#
    .SYNOPSIS
        Maps a Freshservice approval payload to the Q13 output contract.
    #>
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [AllowNull()]
        $InputObject,

        [long]$TicketId
    )

    process {
        if ($null -eq $InputObject) {
            return
        }

        function Get-FsuApprovalProperty {
            param($Source, [string]$Name)
            if ($Source -is [System.Collections.IDictionary]) {
                if ($Source.Contains($Name)) { return $Source[$Name] }
                return $null
            }
            $property = $Source.PSObject.Properties[$Name]
            if ($null -eq $property) { return $null }
            return $property.Value
        }

        function ConvertTo-FsuUtcDateTime {
            param($Value)
            if ($null -eq $Value -or ($Value -is [string] -and [string]::IsNullOrWhiteSpace($Value))) { return $null }
            if ($Value -is [datetime]) {
                if ($Value.Kind -eq [System.DateTimeKind]::Utc) { return $Value }
                return $Value.ToUniversalTime()
            }
            $parsed = [datetime]::MinValue
            if ([datetime]::TryParse([string]$Value, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal, [ref]$parsed)) {
                return $parsed
            }
            return $null
        }

        $status = Get-FsuApprovalProperty -Source $InputObject -Name 'approval_status'
        $statusId = $null
        $statusName = $null
        if ($null -ne $status) {
            $statusId = Get-FsuApprovalProperty -Source $status -Name 'id'
            $statusName = Get-FsuApprovalProperty -Source $status -Name 'name'
        }

        $parentId = Get-FsuApprovalProperty -Source $InputObject -Name 'parent_id'
        $result = [PSCustomObject]@{
            PSTypeName = 'FreshservicePSU.Approval'
            Id = Get-FsuApprovalProperty -Source $InputObject -Name 'id'
            TicketId = if ($null -ne $parentId) { $parentId } elseif ($TicketId) { $TicketId } else { $null }
            ApproverId = Get-FsuApprovalProperty -Source $InputObject -Name 'approver_id'
            ApproverName = Get-FsuApprovalProperty -Source $InputObject -Name 'approver_name'
            UserId = Get-FsuApprovalProperty -Source $InputObject -Name 'user_id'
            UserName = Get-FsuApprovalProperty -Source $InputObject -Name 'user_name'
            ApprovalStatusId = $statusId
            ApprovalStatusName = $statusName
            Level = Get-FsuApprovalProperty -Source $InputObject -Name 'level'
            CreatedAt = ConvertTo-FsuUtcDateTime -Value (Get-FsuApprovalProperty -Source $InputObject -Name 'created_at')
            UpdatedAt = ConvertTo-FsuUtcDateTime -Value (Get-FsuApprovalProperty -Source $InputObject -Name 'updated_at')
            Delegatee = Get-FsuApprovalProperty -Source $InputObject -Name 'delegatee'
            ApprovalGroup = Get-FsuApprovalProperty -Source $InputObject -Name 'approval_group'
            LatestRemark = Get-FsuApprovalProperty -Source $InputObject -Name 'latest_remark'
        }
        $result
    }
}
