function Test-SPSLifecycleInputRedirected {
    <#
        .SYNOPSIS
        Tells whether the input of the process is redirected, so that no person types what the tool asks.

        .DESCRIPTION
        The confirmation of an Execute run is typed by a person. A script that pipes its answers, a scheduled task and a
        console that is not one cannot give it, and the tool stops instead of reading them. It is a function of its own so
        that the tests can say yes and no: the property of the console is not something that a test can replace.

        .EXAMPLE
        Test-SPSLifecycleInputRedirected
    #>
    [CmdletBinding()]
    [OutputType([System.Boolean])]
    param ()

    [System.Console]::IsInputRedirected
}
