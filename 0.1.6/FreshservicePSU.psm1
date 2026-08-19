[CmdletBinding()]
param()

$private = @(Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Private') -Filter '*.ps1' -Recurse -File -ErrorAction SilentlyContinue | Sort-Object -Property FullName)
$public = @(Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Public')  -Filter '*.ps1' -Recurse -File -ErrorAction SilentlyContinue | Sort-Object -Property FullName)

foreach ($import in @($private + $public)) {
    try {
        . $import.FullName
    } catch {
        throw "Unable to dot source [$($import.FullName)]: $_"
    }
}

# The manifest FunctionsToExport list is the only export surface.
