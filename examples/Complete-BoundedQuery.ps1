function Complete-BoundedQuery {
    <#
    .SYNOPSIS
        Runs a bounded list query and emits results only if the command completes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [scriptblock]$Query,

        [int]$MaxRecords
    )

    $buffer = [System.Collections.Generic.List[object]]::new()
    try {
        & $Query $MaxRecords | ForEach-Object {
            [void]$buffer.Add($_)
        }
    } catch {
        if ([string]$_.FullyQualifiedErrorId -match 'PartialResults') {
            $buffer.Clear()
        }
        throw
    }

    $buffer.ToArray()
}
