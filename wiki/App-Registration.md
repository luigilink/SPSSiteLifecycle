# App registration

> This page is generated from the table of the permissions of the module. Do not edit it by hand: change the table, then run `tools/Update-Documentation.ps1`. A test fails when this page is out of date.

The tool signs in to your tenant with a Microsoft Entra app registration that you create once: PnP.PowerShell no longer brings an app of its own. A script does it in one guided run. This page says what the script does, so that a security team can review it, and how to do the same by hand.

## The script

```powershell
# See the plan and stop: nothing is asked, nothing is created
pwsh ./src/Register-SPSSiteLifecycleApp.ps1 -TenantName contoso -WhatIf

# An app that a person signs in with (what the tool uses today)
pwsh ./src/Register-SPSSiteLifecycleApp.ps1 -TenantName contoso

# An app that signs in alone, with a certificate, for a run that nobody watches
pwsh ./src/Register-SPSSiteLifecycleApp.ps1 -TenantName contoso -Kind Certificate
```

In this order, and the tenant is changed only at the end:

1. **It checks what you gave.** The tenant must be the name of a tenant (`contoso` for `contoso.sharepoint.com`), and never one of the Microsoft corporate tenants. The name of the app is 1 to 64 letters, digits, dots, dashes or underscores (it is also the name of the certificate files). For a certificate, the folder that you give is where a new folder named after the app is made for the key: that one must not be there already (a folder, a file or a link: nothing is ever written in a place that is taken), and neither may be inside a repository or the folder of the tool, by what is written or by where it leads (a link is followed).
2. **It shows the plan:** the tenant and the domain that the sign-in goes to, the name of the app, the kind, the permissions with what the tool uses each for, the certificate (its years, the date it ends, its files), and the roles that create the app and give the consent. With `-WhatIf` it stops here.
3. **A person types the name of the tenant.** The script stops when the input is redirected, because a confirmation that a script gave is not a person's. For a certificate, the password of the private key is typed too, twice (12 characters or more), as a `SecureString`: it is never shown, never on a command line, never written in a file or in the output.
4. **The key folder is made, new, and checked.** It is created before the key, for your account alone (the mode `700`, or an access list on Windows), checked, and checked again where it really is: the script does not go on when it is not as it must be. PnP.PowerShell writes the key before the tenant says that the app can be created, so what keeps it from others is this folder.
5. **PnP.PowerShell registers the app:** it signs in (a browser window, or a device code with `-DeviceLogin`), stops if an app of that name already exists, creates the app with its permissions, and runs the consent. The script does not look for an existing app itself, because the cmdlet does, and nothing can be read in the tenant before the first app exists.
6. **It restricts the key to your account,** even when the run is interrupted, and tells what may be left in the tenant. When the name is taken, which PnP.PowerShell says before it creates the app, it removes the two files that the cmdlet wrote (by their names, and the folder when it is empty). In every other failure it keeps them, a refusal of Microsoft Graph included: only that message proves that no app was created, and the key may be the only copy of the one of an app that exists. After a success it checks that the certificate is the one that the app got, and that the key file opens with your password and holds its private key.
7. **It shows what to put in the settings file** (`TenantName`, `ClientId`, and for a certificate `Authentication`, `TenantId` and the certificate), the thumbprint and the date the certificate ends. No secret is written in the settings or in the repository: the repository ignores `*.pfx`, `*.cer`, `*.pem`, `*.key` and `*.p12`, in case one lands there anyway.

The script exits with `0` when the app was registered, and with `1` on any error, after a message that says what was and was not created and what to do next.

## The two kinds of app

| Kind | Who signs in | Certificate | Permissions | Use |
|------|--------------|-------------|-------------|-----|
| `Interactive` (the default) | A person, in a browser window | None | Delegated | What the tool uses today: put the `ClientId` in the settings file. The account that signs in has to be a SharePoint administrator. |
| `Certificate` | The app itself, with no person | Self-signed, 2 years by default (1 to 30 with `-ValidYears`) | Application | A run that nobody watches (a scheduled task, a server): `Authentication = 'Certificate'` in the settings, see below. |

## Permissions

The script requests exactly these, and nothing else. An app that signs in alone gets application permissions; an app that a person signs in with gets delegated ones, which are limited by what the account that signs in may do.

| Kind | Resource | Permission | Type | Used by | What the tool uses it for |
|------|----------|------------|------|---------|---------------------------|
| `Certificate` | SharePoint | `Sites.FullControl.All` | Application | Scan and Act | Lets the app call the SharePoint admin API with no person signed in: it lists every site collection with its lock state, template and size (Scan), and reads a site again, locks or unlocks it, deletes it and requests its archive (Act). The admin API is called with this permission in the app-only mode, and no weaker one has been shown to work (an open point: it has to be measured in a lab). |
| `Certificate` | Graph | `Group.ReadWrite.All` | Application | Act | Reads the Microsoft 365 group of a site before an action, and deletes it: a site that has a group is deleted through its group (Act). The Scan does not use it. |
| `Interactive` | SharePoint | `AllSites.FullControl` | Delegated | Scan and Act | Lets the tool call the SharePoint admin API as the administrator who signs in: it lists every site collection with its lock state, template and size (Scan), and reads a site again, locks or unlocks it, deletes it and requests its archive (Act). The permission is the most that the tool can do, and what the signed-in account may do in the tenant is the limit (it has to be a SharePoint administrator). |
| `Interactive` | Graph | `Group.ReadWrite.All` | Delegated | Act | Reads the Microsoft 365 group of a site before an action, and deletes it, as the signed-in administrator: a site that has a group is deleted through its group (Act). The Scan does not use it. |

The reports permission (`Reports.Read.All`) is not requested: it comes when the tool downloads the activity reports itself. Whether a weaker permission than `Sites.FullControl.All` reads the list of the sites in the app-only mode is an open point that only a lab can settle ([Design decisions](Design-Decisions), D13).

## Who can do it

- **Create the app:** a user who is allowed to register applications. The tenant may allow every user to, or the account needs a role such as Application Developer, Application Administrator, Cloud Application Administrator or Global Administrator.
- **Give the consent,** according to [Microsoft Learn](https://learn.microsoft.com/entra/identity/enterprise-apps/grant-admin-consent): a Privileged Role Administrator can for any permission of any API; a Cloud Application Administrator or an Application Administrator can for any permission except the application permissions of Microsoft Graph. So the `Certificate` kind needs a Privileged Role Administrator or a Global Administrator, and the `Interactive` kind needs one of the four roles.

When the consent cannot be given, the app is created all the same. Ask an administrator who can to open the app in the Microsoft Entra admin center (App registrations, the app, API permissions) and select **Grant admin consent**, or to open `https://login.microsoftonline.com/<tenant>.onmicrosoft.com/adminconsent?client_id=<Application (client) ID>` with the ID of the Overview page.

## The certificate

- **Self-signed, 2 years by default.** The default of PnP.PowerShell is 10 years and its maximum is 30: a certificate that lives that long is a key that nobody remembers. Choose the number of years with `-ValidYears`.
- **Files:** `<name>.pfx` (the private key, protected by the password) and `<name>.cer` (the certificate, public), in `<folder>/<name>`, a new folder that only your account can read (the mode `700`, and `600` for the key, on macOS and Linux, and an access control list on Windows), outside any repository and the folder of the tool. The default folder is `.spssitelifecycle` in your profile. Keep it out of a synchronized folder.
- **The Windows store:** with `-UseCertificateStore` (Windows only) the certificate is also added to your `CurrentUser` store after the registration, to be used by its thumbprint. macOS and Linux have no store and use the `.pfx` file.
- **A key that is lost cannot be given back.** Keep the `.pfx` and its password in a safe place.

## Sign in with the certificate

The app of the `Certificate` kind signs in alone, so that a run can go on with nobody there. Put the lines that the script shows in the settings file (see the [Configuration](Configuration) page):

```powershell
@{
    TenantName     = 'contoso'
    ClientId       = '<the Application (client) ID of the app>'
    Authentication = 'Certificate'
    TenantId       = '<the ID of your Microsoft Entra tenant>'
    CertificatePath = 'C:\Keys\SPSSiteLifecycle.pfx'                         # or CertificateThumbprint = '...' (Windows store)
    CertificatePasswordVariable = 'SPSSITELIFECYCLE_PFX_PASSWORD'           # the name of an environment variable
}
```

- **A password never goes in the settings file.** A key such as `CertificatePassword` is refused. The password of the `.pfx` file is read from the environment variable that `CertificatePasswordVariable` names (set it in the account that runs the task); a variable that is not set stops the run. Without `CertificatePasswordVariable` the tool asks for the password, typed and never shown, which a run that nobody watches cannot answer. A certificate of the Windows store has no password.
- **The certificate is checked before the sign-in.** The run stops when it has expired, is not valid yet, or has no private key (a `.cer` file is not enough), and warns when it ends in less than 30 days. Renew it as described below.
- **What does not change.** The refused tenants are refused, and the Act phase with `Execute` still needs a person to type its confirmation: an unattended run is a Scan, or an Act in report-only mode.

## Without the script

The same, by hand, in the Microsoft Entra admin center ([register an application](https://learn.microsoft.com/entra/identity-platform/quickstart-register-app)):

1. **App registrations, New registration.** Name it, and keep *Accounts in this organizational directory only*. For the `Interactive` kind add the platform *Mobile and desktop applications* with the redirect URI `http://localhost`, and allow public client flows (Authentication). The `Certificate` kind needs no redirect URI.
2. **API permissions, Add a permission:** the permissions of the table above for the kind that you want, then **Grant admin consent** (see the roles above).
3. **Certificate kind only: Certificates & secrets, Certificates, Upload certificate:** the `.cer` file of a certificate that you made (a self-signed one is enough). Keep its private key where only you can read it.
4. **Overview:** copy the *Application (client) ID* into `ClientId` of the settings file.

## Renewal and removal

- **Renew a certificate before it ends:** make a new one, upload its `.cer` to the app (Certificates & secrets) while the old one is still valid, use the new one in your settings, then delete the old one from the app.
- **Remove the app after a campaign:** delete it in the Microsoft Entra admin center (App registrations), which takes its consent with it, delete the `.pfx` and the `.cer`, and on Windows remove the certificate from the store: `Remove-Item Cert:\CurrentUser\My\<thumbprint>`.

## Links

- [Register-PnPEntraIDApp](https://pnp.github.io/powershell/cmdlets/Register-PnPEntraIDApp.html) and [Register-PnPEntraIDAppForInteractiveLogin](https://pnp.github.io/powershell/cmdlets/Register-PnPEntraIDAppForInteractiveLogin.html), which the script builds on.
- [Grant tenant-wide admin consent to an application](https://learn.microsoft.com/entra/identity/enterprise-apps/grant-admin-consent), on Microsoft Learn.
- [Microsoft Graph permissions reference](https://learn.microsoft.com/graph/permissions-reference), on Microsoft Learn.
