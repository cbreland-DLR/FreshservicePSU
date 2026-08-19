@{
    Severity            = @('Error', 'Warning')
    IncludeDefaultRules = $true

    # PSUseBOMForUnicodeEncodedFile conflicts directly with this project's
    # documented convention (docs/ARCHITECTURE.md §11, Serialization
    # conventions) of UTF-8 without a BOM on every file the pipeline writes,
    # including its own source and test files.
    #
    # PSUseDeclaredVarsMoreThanAssignments false-positives on Pester 5 files:
    # variables assigned in a `BeforeAll`/`BeforeDiscovery` block and consumed
    # only inside `It`/`Context` blocks are, correctly, out of the analyzer's
    # static scope, so it cannot see the later use.
    ExcludeRules        = @(
        'PSUseBOMForUnicodeEncodedFile',
        'PSUseDeclaredVarsMoreThanAssignments'
    )
}
