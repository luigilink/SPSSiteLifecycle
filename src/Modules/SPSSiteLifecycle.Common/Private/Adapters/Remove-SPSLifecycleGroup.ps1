function Remove-SPSLifecycleGroup {
    <#
        .SYNOPSIS
        Deletes a Microsoft 365 group, which deletes its site some time later. This changes the tenant.

        .DESCRIPTION
        One operation: Remove-PnPMicrosoft365Group, by the ID of the group as a GUID and never by a name. The group goes to the
        recycle bin of the groups (Microsoft Entra), and SharePoint deletes the site of the group some time later (from 4 minutes
        to under 5 hours in the lab). The target is checked first (see Assert-SPSLifecycleWriteTarget).

        .PARAMETER Session
        The session (see Open-SPSLifecycleTenantSession).

        .PARAMETER GroupId
        The ID of the group.

        .EXAMPLE
        Remove-SPSLifecycleGroup -Session $session -GroupId $site.GroupId
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    [OutputType([System.Void])]
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.PSObject]
        $Session,

        [Parameter(Mandatory = $true)]
        [System.String]
        $GroupId
    )

    Assert-SPSLifecycleWriteTarget -Session $Session -GroupId $GroupId

    $guid = [System.Guid]::Parse($GroupId)
    if (-not $PSCmdlet.ShouldProcess($guid.ToString(), 'Delete the Microsoft 365 group')) {
        return
    }

    try {
        $null = Remove-PnPMicrosoft365Group -Identity $guid -Connection $Session.Connection -ErrorAction Stop
    }
    catch {
        throw "The group $($guid.ToString()) could not be deleted: $($_.Exception.Message.Trim().TrimEnd('.'))."
    }
}
