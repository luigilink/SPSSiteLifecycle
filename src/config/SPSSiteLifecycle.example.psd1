# =====================================================================================
# SPSSiteLifecycle - settings file (example)
#
# Copy this file, fill it in, and give it to the script:
#   pwsh ./src/SPSSiteLifecycle.ps1 -ConfigFile ./contoso.psd1 -Phase Scan
#   pwsh ./src/SPSSiteLifecycle.ps1 -ConfigFile ./contoso.psd1 -Phase Act
#
# A setting you do not write keeps the default shown in its comment. An unknown setting
# stops the tool. A relative path is relative to the folder of this file.
# Every setting is explained on the Configuration page of the wiki.
# =====================================================================================
@{
    # ---- Shared by both phases ------------------------------------------------------

    # Required. The first part of your SharePoint address: contoso for contoso.sharepoint.com.
    TenantName            = 'contoso'

    # Required. Application (client) ID of your Microsoft Entra app registration, for the
    # interactive sign-in of PnP.PowerShell. The setup script src/Register-SPSSiteLifecycleApp.ps1
    # creates the app and shows this value (see the App-Registration page of the wiki).
    ClientId              = '11111111-2222-3333-4444-555555555555'

    # How the tool signs in: 'Interactive' (a person signs in, in a window) or 'Certificate' (the app
    # signs in alone, for a run that nobody watches). 'Certificate' needs TenantId and exactly one of
    # CertificateThumbprint and CertificatePath, and an app that was registered for it (see the
    # App-Registration page of the wiki). A password never goes in this file.
    # Authentication        = 'Interactive'

    # Certificate sign-in only. ID of your Microsoft Entra tenant (a GUID).
    # TenantId              = '66666666-7777-8888-9999-000000000000'

    # Certificate sign-in only. Thumbprint of a certificate of the Windows store (Windows only) ...
    # CertificateThumbprint = '0123456789ABCDEF0123456789ABCDEF01234567'

    # ... or the .pfx file of the certificate (any platform), kept outside the repository.
    # CertificatePath       = 'C:\Keys\SPSSiteLifecycle.pfx'

    # For a .pfx file: the name of the environment variable that holds its password. Without it the
    # tool asks for the password, which a run that nobody watches cannot.
    # CertificatePasswordVariable = 'SPSSITELIFECYCLE_PFX_PASSWORD'

    # Folder for the reports, the checkpoints and the lock journal.
    # OutputFolder          = 'Reports'

    # Tenants to refuse, in addition to microsoft and microsoftonline, which are always refused.
    # RefusedTenants        = @('contosoprod')

    # Lock states in which a site can be deleted or archived: ReadOnly, and Unlock if you want
    # to allow the direct deletion of an unlocked site. NoAccess is never accepted.
    # AcceptedLockStates    = @('ReadOnly')

    # A read-only site is deleted or archived only after it has been locked for this many days.
    # MinLockedDays         = 365

    # A site larger than this size, in GB, is never deleted (25600 removes the limit).
    # DeleteMaxSizeGB       = 1

    # CSV files that give the date each site was locked (Url, LockedOn, optional SiteId).
    # LockDateFiles         = @('lock-dates.csv')

    # CSV files (Url) listing the sites that must never be touched.
    # ExclusionFiles        = @('exclusions.csv')

    # CSV file where the Act phase records the sites it locks. Default: lock-journal.csv in OutputFolder.
    # LockJournal           = 'Reports\lock-journal.csv'

    # Separator of the CSV files the tool writes: Culture, ',', ';' or Tab.
    # CsvDelimiter          = 'Culture'

    # Extra date formats accepted in your CSV files. ISO 8601 dates are always accepted.
    # CsvDateFormats        = @('dd/MM/yyyy')

    # ---- Scan phase: find the sites and write the CSV -------------------------------

    Scan                  = @{
        # A site is a candidate when its last activity is older than this many days.
        # InactiveDays          = 365

        # Lock states that Scan lists. Add 'Unlock' to also look for unlocked inactive sites.
        # LockStates            = @('ReadOnly')

        # Activity reports (CSV from the Microsoft 365 admin center). Give at least one.
        SharePointUsageReport = 'SharePointSiteUsageDetail.csv'
        # TeamsActivityReport   = 'TeamsTeamActivityDetail.csv'
        # GroupsActivityReport  = 'Office365GroupsActivityDetail.csv'
    }

    # ---- Act phase: apply the decisions of the CSV ----------------------------------

    Act                   = @{
        # Required for the Act phase: the Scan CSV, once its Decision column is filled in.
        InputFile             = 'Reports\sites.csv'

        # $false: report only, nothing is changed. $true: apply the decisions, after the typed confirmation.
        # Execute               = $false

        # Maximum number of actions in one run.
        # MaxActions            = 25

        # Pause, in seconds, between two actions.
        # DelaySeconds          = 2

        # The CSV must not be older than this many days.
        # MaxCsvAgeDays         = 30

        # Before an archive, add the signed-in administrator as administrator of the site
        # collection. Requires UnlockBeforeArchive.
        # GrantSiteAdmin        = $false

        # Unlock a read-only site before archiving it, and lock it again afterwards.
        # UnlockBeforeArchive   = $false
    }
}
