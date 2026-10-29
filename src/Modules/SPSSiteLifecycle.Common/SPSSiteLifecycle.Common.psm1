# =====================================================================================
# SPSSiteLifecycle.Common - module loader
#
# Dot-sources every *.ps1 in Private/ (adapters included) and Public/, then exports only
# the public function names. Private functions remain accessible inside the module but
# are hidden from callers.
# =====================================================================================

$script:ModuleRoot = $PSScriptRoot

$private = @(Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Private') -Filter '*.ps1' -Recurse -ErrorAction SilentlyContinue)
$public = @(Get-ChildItem -Path (Join-Path -Path $PSScriptRoot -ChildPath 'Public') -Filter '*.ps1' -Recurse -ErrorAction SilentlyContinue)

foreach ($file in @($private + $public)) {
    try {
        . $file.FullName
    }
    catch {
        throw "Failed to import function file '$($file.FullName)': $_"
    }
}

if ($public.Count -gt 0) {
    Export-ModuleMember -Function $public.BaseName
}
