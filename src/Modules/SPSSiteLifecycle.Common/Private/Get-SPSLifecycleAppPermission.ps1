function Get-SPSLifecycleAppPermission {
    <#
        .SYNOPSIS
        Returns the permissions that the setup script asks for, with what the tool uses each one for.

        .DESCRIPTION
        This table is the single source of truth for the permissions of the Microsoft Entra app: the setup script requests exactly these,
        its plan shows each one with its reason, and the App-Registration page of the wiki is generated from it (tools/Update-Documentation.ps1),
        so that a security team reads what the code does. Nothing is requested that the tool does not use today: the reports permission
        (Reports.Read.All) comes with the download of the activity reports, in its own issue.

        An app that signs in alone (the Certificate kind) gets application permissions, and an app that a person signs in with (the
        Interactive kind) gets delegated ones. Each row has Resource (Graph or SharePoint), Name, Type (Application or Delegated), Kind
        (Certificate or Interactive), UsedBy (the phases) and Reason.

        .EXAMPLE
        Get-SPSLifecycleAppPermission | Where-Object { $_.Kind -eq 'Interactive' }
    #>
    [CmdletBinding()]
    [OutputType([System.Management.Automation.PSObject[]])]
    param ()

    $listing = 'lists every site collection with its lock state, template and size (Scan), and reads a site again, locks or unlocks it, deletes it and requests its archive (Act)'
    $rows = @(
        , @('SharePoint', 'Sites.FullControl.All', 'Application', 'Certificate', 'Scan and Act', "Lets the app call the SharePoint admin API with no person signed in: it $listing. The admin API is called with this permission in the app-only mode, and no weaker one has been shown to work (an open point: it has to be measured in a lab).")
        , @('Graph', 'Group.ReadWrite.All', 'Application', 'Certificate', 'Act', 'Reads the Microsoft 365 group of a site before an action, and deletes it: a site that has a group is deleted through its group (Act). The Scan does not use it.')
        , @('SharePoint', 'AllSites.FullControl', 'Delegated', 'Interactive', 'Scan and Act', "Lets the tool call the SharePoint admin API as the administrator who signs in: it $listing. The permission is the most that the tool can do, and what the signed-in account may do in the tenant is the limit (it has to be a SharePoint administrator).")
        , @('Graph', 'Group.ReadWrite.All', 'Delegated', 'Interactive', 'Act', 'Reads the Microsoft 365 group of a site before an action, and deletes it, as the signed-in administrator: a site that has a group is deleted through its group (Act). The Scan does not use it.')
    )

    foreach ($row in $rows) {
        [PSCustomObject]@{
            Resource = $row[0]
            Name     = $row[1]
            Type     = $row[2]
            Kind     = $row[3]
            UsedBy   = $row[4]
            Reason   = $row[5]
        }
    }
}
