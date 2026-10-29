@{
    RootModule        = 'SPSSiteLifecycle.Common.psm1'
    ModuleVersion     = '0.0.0'
    GUID              = 'eb535666-1bd8-4039-8276-e6df9cdf3058'
    Author            = 'Jean-Cyril DROUHIN'
    CompanyName       = 'luigilink'
    Copyright         = '(c) Jean-Cyril DROUHIN. All rights reserved.'
    Description       = 'Shared functions for the SPSSiteLifecycle tool: settings file, CSV and activity report importers, verdicts, and the two phases (Scan and Act) that find inactive or read-only SharePoint Online sites and delete or archive the reviewed ones.'

    PowerShellVersion = '7.4'

    FunctionsToExport = @(
        'Get-SPSLifecycleSetting'
    )

    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()

    PrivateData = @{
        PSData = @{
            Tags       = @('SharePoint', 'SharePointOnline', 'Lifecycle', 'Cleanup', 'Archive', 'PnP.PowerShell')
            LicenseUri = 'https://github.com/luigilink/SPSSiteLifecycle/blob/main/LICENSE'
            ProjectUri = 'https://github.com/luigilink/SPSSiteLifecycle'
        }
    }
}
