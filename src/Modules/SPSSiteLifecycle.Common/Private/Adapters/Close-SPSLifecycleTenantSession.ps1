function Close-SPSLifecycleTenantSession {
    <#
        .SYNOPSIS
        Ends the session that Open-SPSLifecycleTenantSession gave.

        .DESCRIPTION
        The connection was not made the current one of the PowerShell session, so Disconnect-PnPOnline would not end it:
        the context of the connection is disposed, which is what releases it. A failure here never hides the reason why the
        run ended.

        .PARAMETER Session
        The session.

        .EXAMPLE
        Close-SPSLifecycleTenantSession -Session $session
    #>
    [CmdletBinding()]
    [OutputType([System.Void])]
    param
    (
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        [System.Object]
        $Session
    )

    if ($null -eq $Session -or $null -eq $Session.Connection) {
        return
    }

    try {
        $context = $Session.Connection.Context
        if ($context -is [System.IDisposable]) {
            $context.Dispose()
        }
    }
    catch {
        Write-Verbose -Message "The session could not be closed: $($_.Exception.Message)"
    }
}
