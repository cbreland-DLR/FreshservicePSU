function ConvertTo-FsuEmbedQuery {
    <#
    .SYNOPSIS
        Builds the Freshservice include query value from validated embed names.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [AllowEmptyCollection()]
        [string[]]$Include
    )

    $names = @($Include | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($names.Count -eq 0) {
        return $null
    }

    return (($names | ForEach-Object { $_.Trim().ToLowerInvariant() }) -join ',')
}
