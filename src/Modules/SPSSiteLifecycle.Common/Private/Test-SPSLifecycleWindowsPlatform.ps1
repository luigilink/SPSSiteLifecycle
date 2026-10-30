function Test-SPSLifecycleWindowsPlatform {
    <#
        .SYNOPSIS
        Tells whether the tool runs on Windows.

        .DESCRIPTION
        Windows has a certificate store that PnP.PowerShell uses by thumbprint, and access control lists for the files. macOS and Linux have
        neither, and use the mode of a file. It is a function of its own so that the tests can say yes and no on any machine.

        .EXAMPLE
        Test-SPSLifecycleWindowsPlatform
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param ()

    [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)
}
