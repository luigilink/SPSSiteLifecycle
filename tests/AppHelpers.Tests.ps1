BeforeAll {
    $script:Manifest = Join-Path -Path $PSScriptRoot -ChildPath '../src/Modules/SPSSiteLifecycle.Common/SPSSiteLifecycle.Common.psd1'
    $script:Module = Import-Module -Name $script:Manifest -Force -PassThru
    $script:Now = [System.DateTime]::new(2026, 10, 30, 9, 15, 0, [System.DateTimeKind]::Utc)

    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers/ModuleStub.ps1')

    function script:New-AppPlan {
        param([string]$Kind = 'Interactive')

        $parameters = @{ TenantName = 'Contoso'; ApplicationName = 'SPSSiteLifecycle'; Kind = $Kind; Now = $script:Now }
        if ($Kind -eq 'Certificate') { $parameters['Folder'] = '/keys/spslc' }
        & $script:Module { param($p) Get-SPSLifecycleAppPlan @p } $parameters
    }

    function script:ConvertTo-Secure {
        param([string]$Text)

        $secure = [System.Security.SecureString]::new()
        foreach ($character in $Text.ToCharArray()) { $secure.AppendChar($character) }
        $secure.MakeReadOnly()
        $secure
    }

    Install-Tripwire
}

AfterAll {
    Remove-Tripwire
}

Describe 'Get-SPSLifecycleAppFailureKind' {
    It 'tells that the name is taken, from the message of PnP.PowerShell' {
        & $script:Module { Get-SPSLifecycleAppFailureKind -Message 'The application with name SPSSiteLifecycle already exists.' } | Should -BeExactly 'AppExists'
        & $script:Module { Get-SPSLifecycleAppFailureKind -Message 'Checking... The application with name my-app_2 already exists. More text.' } | Should -BeExactly 'AppExists'
    }

    It 'tells that the account was refused by Microsoft Graph: <Message>' -ForEach @(
        @{ Message = 'Authorization_RequestDenied: Insufficient privileges to complete the operation.' }
        @{ Message = 'Insufficient privileges to complete the operation.' }
        @{ Message = 'Response status code does not indicate success: 403 (Forbidden).' }
        @{ Message = 'Response status code does not indicate success: 401 (Unauthorized).' }
        @{ Message = '{"error":{"code":"Authorization_RequestDenied","message":"x"}}' }
        @{ Message = '{ "error": { "code": "AccessDenied" } }' }
        @{ Message = '"code" : "InvalidAuthenticationToken"' }
    ) {
        & $script:Module { param($m) Get-SPSLifecycleAppFailureKind -Message $m } $Message | Should -BeExactly 'Forbidden'
    }

    It 'tells that a Microsoft Entra error came after the app was created, from its code: <Message>' -ForEach @(
        @{ Message = 'AADSTS65001: The user or administrator has not consented to use the application.' }
        @{ Message = 'The sign-in failed: AADSTS90094: An administrator needs to grant permission.' }
    ) {
        & $script:Module { param($m) Get-SPSLifecycleAppFailureKind -Message $m } $Message | Should -BeExactly 'Consent'
    }

    It 'does not tell what it cannot: <Message>' -ForEach @(
        @{ Message = 'A task was canceled.' }
        @{ Message = 'The operation timed out.' }
        @{ Message = '' }
        @{ Message = $null }
        @{ Message = 'the application with name x already exists' }
    ) {
        & $script:Module { param($m) Get-SPSLifecycleAppFailureKind -Message $m } $Message | Should -BeExactly 'Unknown'
    }

    It 'reads the first kind when a message says more than one: the name that is taken wins, then the refusal' {
        & $script:Module { Get-SPSLifecycleAppFailureKind -Message 'The application with name X already exists. 403 (Forbidden) AADSTS1' } | Should -BeExactly 'AppExists'
        & $script:Module { Get-SPSLifecycleAppFailureKind -Message '403 (Forbidden) AADSTS65001' } | Should -BeExactly 'Forbidden'
    }
}

Describe 'Format-SPSLifecycleAppFailure' {
    BeforeAll {
        function script:Format-Failure {
            param([string]$Kind, [string]$Message = 'The thing failed.', [string]$PlanKind = 'Certificate', [string[]]$Removed = @(), [string[]]$Kept = @(), [string[]]$NotRemoved = @())

            $plan = New-AppPlan -Kind $PlanKind
            & $script:Module { param($k, $m, $p, $r, $kp, $n) Format-SPSLifecycleAppFailure -Kind $k -Message $m -Plan $p -FilesRemoved $r -FilesKept $kp -FilesNotRemoved $n } $Kind $Message $plan $Removed $Kept $NotRemoved
        }
    }

    It 'says that the name is taken and that nothing was created, and what to do' {
        $text = Format-Failure -Kind AppExists

        $text | Should -BeLike "*An application named 'SPSSiteLifecycle' already exists in this tenant, so nothing was created.*"
        $text | Should -BeLike '*another name with -ApplicationName*Microsoft Entra admin center*'
    }

    It 'says that the account is not allowed, with the reason, the roles that are, and that nothing was created' {
        $text = Format-Failure -Kind Forbidden -Message 'Authorization_RequestDenied.'

        $text | Should -BeLike '*not allowed to create an app registration*(Authorization_RequestDenied)*Nothing was created.*'
        $text | Should -BeLike '*Application Developer*Global Administrator*'
    }

    It 'says that the consent may be what is missing, who gives it, and how, with the link of the tenant' {
        $text = Format-Failure -Kind Consent -Message 'AADSTS65001: not consented.'

        $text | Should -BeLike "*stopped at the sign-in or at the consent: AADSTS65001: not consented. The app 'SPSSiteLifecycle' may have been created*"
        $text | Should -BeLike '*Privileged Role Administrator*Grant admin consent*'
        $text | Should -BeLike '*https://login.microsoftonline.com/contoso.onmicrosoft.com/adminconsent?client_id=<the Application (client) ID of the Overview page>*'
    }

    It 'says that nobody can tell whether the app exists when it cannot tell' {
        $text = Format-Failure -Kind Unknown -Message 'A task was canceled.'

        $text | Should -BeLike "*The registration stopped: A task was canceled. The app 'SPSSiteLifecycle' may or may not exist*delete it before you run the script again*"
    }

    It 'tells the message of the error without its end, whatever it ends with' {
        (Format-Failure -Kind Unknown -Message 'Stopped...') | Should -BeLike '*stopped: Stopped. The app*'
    }

    It 'says what became of the files: removed, kept, or not removed' {
        (Format-Failure -Kind AppExists -Removed @('/keys/a.pfx', '/keys/a.cer')) | Should -BeLike '*were removed, since no app uses them.*'
        (Format-Failure -Kind Consent -Kept @('/keys/a.pfx')) | Should -BeLike '*The certificate files were kept (/keys/a.pfx): the key may be the one of an app that exists.*'
        (Format-Failure -Kind AppExists -NotRemoved @('/keys/a.pfx', '/keys/a.cer')) | Should -BeLike '*could not be removed (delete them by hand, no app uses them): /keys/a.pfx, /keys/a.cer.*'
    }

    It 'says nothing of files when there are none, as for an app that signs in with a person' {
        foreach ($kind in 'AppExists', 'Forbidden', 'Consent', 'Unknown') {
            (Format-Failure -Kind $kind -PlanKind Interactive) | Should -Not -BeLike '*certificate files*'
        }
    }

    It 'is written with one space between its sentences, and none at its ends, with files and without: <Kind>' -ForEach @(
        @{ Kind = 'AppExists' }
        @{ Kind = 'Forbidden' }
        @{ Kind = 'Consent' }
        @{ Kind = 'Unknown' }
    ) {
        foreach ($text in (Format-Failure -Kind $Kind -PlanKind Interactive), (Format-Failure -Kind $Kind -Removed @('/keys/a.pfx')), (Format-Failure -Kind $Kind -Kept @('/keys/a.pfx'), '/keys/a.cer')) {
            $text | Should -Not -Match '  '
            $text | Should -Not -Match '\A\s|\s\z'
        }
    }
}

Describe 'Format-SPSLifecycleAppResult' {
    BeforeAll {
        function script:Format-Result {
            param([string]$Kind, [hashtable]$Override = @{})

            $plan = New-AppPlan -Kind $Kind
            $values = [ordered]@{
                ClientId = '4d3c2b1a-0f9e-4d8c-8b7a-6f5e4d3c2b1a'; Thumbprint = ''; ExpiresOn = $null; PfxPath = ''; CerPath = ''; KeyProtected = $false; StoredInCertificateStore = $false
            }
            if ($Kind -eq 'Certificate') {
                $values['Thumbprint'] = '0123456789ABCDEF0123456789ABCDEF01234567'
                $values['ExpiresOn'] = [System.DateTime]::new(2028, 10, 30, 0, 0, 0, [System.DateTimeKind]::Utc)
                $values['PfxPath'] = '/keys/spslc/SPSSiteLifecycle.pfx'
                $values['CerPath'] = '/keys/spslc/SPSSiteLifecycle.cer'
                $values['KeyProtected'] = $true
            }
            foreach ($key in $Override.Keys) { $values[$key] = $Override[$key] }
            & $script:Module { param($p, $r) Format-SPSLifecycleAppResult -Plan $p -Result ([PSCustomObject]$r) } $plan $values
        }
    }

    It 'gives the lines to paste in the settings file, and the next step, for an app that a person signs in with' {
        $lines = Format-Result -Kind Interactive

        $lines[0] | Should -BeExactly "The app 'SPSSiteLifecycle' is registered in the tenant contoso, and the consent was given."
        $lines | Should -Contain "    TenantName = 'contoso'"
        $lines | Should -Contain "    ClientId   = '4d3c2b1a-0f9e-4d8c-8b7a-6f5e4d3c2b1a'"
        ($lines -join "`n") | Should -BeLike '*Next: run the Scan*SharePoint administrator*'
        ($lines -join "`n") | Should -Not -BeLike '*thumbprint*'
    }

    It 'gives the thumbprint, the date it ends, the files and what to keep, for the certificate kind' {
        $text = (Format-Result -Kind Certificate) -join "`n"

        $text | Should -BeLike '*thumbprint 0123456789ABCDEF0123456789ABCDEF01234567, and it ends on 2028-10-30: add a new certificate to the app before then*'
        $text | Should -BeLike '*Private key (.pfx): /keys/spslc/SPSSiteLifecycle.pfx*Public key (.cer):  /keys/spslc/SPSSiteLifecycle.cer*'
        $text | Should -BeLike '*can be read by your account only*safe place*'
        $text | Should -BeLike "*ClientId   = '4d3c2b1a-0f9e-4d8c-8b7a-6f5e4d3c2b1a'*"
        $text | Should -BeLike '*sign-in of the tool with this certificate is not available in this version*'
    }

    It 'says that the key could not be restricted, and to do it by hand, when it could not' {
        $text = (Format-Result -Kind Certificate -Override @{ KeyProtected = $false }) -join "`n"

        $text | Should -BeLike '*could not be restricted to your account: do it by hand*'
        $text | Should -Not -BeLike '*can be read by your account only*'
    }

    It 'speaks of the certificate store only when the certificate is in it' {
        ((Format-Result -Kind Certificate) -join "`n") | Should -Not -BeLike '*CurrentUser*'
        ((Format-Result -Kind Certificate -Override @{ StoredInCertificateStore = $true }) -join "`n") | Should -BeLike '*Cert:\CurrentUser\My\0123456789ABCDEF0123456789ABCDEF01234567*'
    }

    It 'says that nothing secret was written' {
        foreach ($kind in 'Interactive', 'Certificate') {
            (Format-Result -Kind $kind)[-1] | Should -BeLike 'Nothing secret was written*'
        }
    }

    It 'writes the date that the certificate ends the same way whatever the culture of the machine, a calendar that is not Gregorian included' {
        $thai = [System.Globalization.CultureInfo]::new('th-TH')
        if ($thai.DateTimeFormat.Calendar -isnot [System.Globalization.ThaiBuddhistCalendar]) {
            Set-ItResult -Skipped -Because 'this machine has no culture data for the Buddhist calendar'
            return
        }

        $previous = [System.Globalization.CultureInfo]::CurrentCulture
        try {
            [System.Globalization.CultureInfo]::CurrentCulture = $thai
            $text = (Format-Result -Kind Certificate) -join "`n"
        }
        finally {
            [System.Globalization.CultureInfo]::CurrentCulture = $previous
        }

        $text | Should -BeLike '*it ends on 2028-10-30*'
    }
}

Describe 'Read-SPSLifecycleCertificatePassword' {
    BeforeAll {
        function script:Read-Password {
            param([string[]]$Answer)

            $secure = @($Answer | ForEach-Object { ConvertTo-Secure -Text $_ })
            Set-ModuleStub -Stub @{
                'Read-Host' = @'
[CmdletBinding()]
param($Prompt, [switch]$AsSecureString)
$script:StubLog.Add("ask: $Prompt | secure=$($AsSecureString.IsPresent)")
$answer = $script:StubData.Answers[$script:StubData.Index]
$script:StubData.Index++
$answer
'@
            } -Data @{ Answers = $secure; Index = 0 }

            & $script:Module { Read-SPSLifecycleCertificatePassword }
        }
    }

    AfterEach {
        Clear-ModuleStub
    }

    It 'gives the password, as a SecureString, when it is typed twice the same' {
        $password = Read-Password -Answer @('Correct-Horse-1', 'Correct-Horse-1')

        $password | Should -BeOfType [System.Security.SecureString]
        [System.Net.NetworkCredential]::new('', $password).Password | Should -BeExactly 'Correct-Horse-1'
        @(Get-StubLog) | Should -HaveCount 2
    }

    It 'asks for a SecureString both times, so that nothing that is typed is shown' {
        $null = Read-Password -Answer @('Correct-Horse-1', 'Correct-Horse-1')

        @(Get-StubLog | Where-Object { $_ -notlike '*secure=True' }) | Should -HaveCount 0
    }

    It 'stops when the password has fewer than 12 characters, without asking again, and does not tell it' {
        { Read-Password -Answer @('Short-Pw-11', 'Short-Pw-11') } | Should -Throw -ExpectedMessage '*fewer than 12 characters*Nothing was changed.'

        @(Get-StubLog) | Should -HaveCount 1
    }

    It 'accepts a password of exactly 12 characters' {
        { Read-Password -Answer @('Exactly-12-ch', 'Exactly-12-ch') } | Should -Not -Throw
        { Read-Password -Answer @('Twelve-chars', 'Twelve-chars') } | Should -Not -Throw
    }

    It 'stops when the two are not the same, and does not tell either: <Second>' -ForEach @(
        @{ Second = 'Correct-Horse-2' }
        @{ Second = 'correct-horse-1' }
        @{ Second = 'Correct-Horse-1 ' }
        @{ Second = '' }
    ) {
        $message = ''
        try { $null = Read-Password -Answer @('Correct-Horse-1', $Second) } catch { $message = $_.Exception.Message }

        $message | Should -BeLike '*not the same*Nothing was changed.'
        $message | Should -Not -BeLike '*Correct-Horse*'
    }
}

Describe 'Confirm-SPSLifecycleAppRegistration' {
    BeforeAll {
        function script:Invoke-Confirm {
            param([string[]]$Answer = @('contoso'), [bool]$Redirected = $false)

            Set-ModuleStub -Stub @{
                'Test-SPSLifecycleInputRedirected' = @'
$script:StubLog.Add('redirected?')
$script:StubData.Redirected
'@
                'Read-Host'                        = @'
[CmdletBinding()]
param($Prompt)
$script:StubLog.Add("ask: $Prompt")
$answer = $script:StubData.Answers[$script:StubData.Index]
$script:StubData.Index++
$answer
'@
            } -Data @{ Redirected = $Redirected; Answers = $Answer; Index = 0 }

            $plan = New-AppPlan
            & $script:Module { param($p) Confirm-SPSLifecycleAppRegistration -Plan $p } $plan
        }
    }

    AfterEach {
        Clear-ModuleStub
    }

    It 'goes on when the name of the tenant is typed, in any case and with spaces around it: <Typed>' -ForEach @(
        @{ Typed = 'contoso' }
        @{ Typed = 'CONTOSO' }
        @{ Typed = '  Contoso  ' }
    ) {
        { Invoke-Confirm -Answer @($Typed) } | Should -Not -Throw

        @(Get-StubLog) | Should -Be @('redirected?', 'ask: Type the name of the tenant to register the app in it')
    }

    It 'stops, with nothing changed, when what is typed is not the tenant: <Typed>' -ForEach @(
        @{ Typed = 'fabrikam' }
        @{ Typed = '' }
        @{ Typed = 'contoso.sharepoint.com' }
        @{ Typed = 'contoso1' }
    ) {
        { Invoke-Confirm -Answer @($Typed) } | Should -Throw -ExpectedMessage '*does not match the tenant (contoso). Nothing was changed.'
    }

    It 'stops before it asks anything when the input is redirected: a confirmation that a script gave is not a person''s' {
        { Invoke-Confirm -Redirected $true } | Should -Throw -ExpectedMessage '*input is redirected*Nothing was changed.'

        @(Get-StubLog) | Should -Be @('redirected?')
    }
}
