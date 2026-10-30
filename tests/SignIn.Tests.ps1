BeforeAll {
    $script:Manifest = Join-Path -Path $PSScriptRoot -ChildPath '../src/Modules/SPSSiteLifecycle.Common/SPSSiteLifecycle.Common.psd1'
    $script:Module = Import-Module -Name $script:Manifest -Force -PassThru
    $script:Now = [System.DateTime]::new(2026, 10, 30, 9, 15, 0, [System.DateTimeKind]::Utc)
    $script:Tenant = '8f3d2c1b-4a5e-4f60-9b7a-0c1d2e3f4a5b'
    $script:Thumbprint = '0123456789abcdef0123456789abcdef01234567'
    $script:Client = '11111111-2222-3333-4444-555555555555'

    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers/ModuleStub.ps1')

    function script:New-SignInSetting {
        param([hashtable]$Override = @{})

        $values = [ordered]@{
            TenantName = 'Contoso'; AdminUrl = 'https://contoso-admin.sharepoint.com'; ClientId = $script:Client; RefusedTenants = @('microsoft', 'microsoftonline')
            Authentication = 'Interactive'; TenantId = $null; CertificateThumbprint = $null; CertificatePath = ''; CertificatePasswordVariable = $null
        }
        foreach ($key in $Override.Keys) { $values[$key] = $Override[$key] }
        [PSCustomObject]$values
    }

    function script:New-Secure {
        param([string]$Text)

        $secure = [System.Security.SecureString]::new()
        foreach ($character in $Text.ToCharArray()) { $secure.AppendChar($character) }
        $secure.MakeReadOnly()
        $secure
    }

    function script:Get-Argument {
        param($Setting, $Password = $null)

        & $script:Module { param($s, $p) Get-SPSLifecycleConnectionArgument -Setting $s -CertificatePassword $p } $Setting $Password
    }

    Install-Tripwire
}

AfterAll {
    Remove-Tripwire
}

Describe 'Get-SPSLifecycleConnectionArgument' {
    It 'asks for the interactive sign-in of the app of the client ID, in the domain of the tenant' {
        $arguments = Get-Argument -Setting (New-SignInSetting)

        @($arguments.Keys | Sort-Object) | Should -Be @('ClientId', 'Interactive', 'Tenant', 'Url')
        $arguments.Url | Should -BeExactly 'https://contoso-admin.sharepoint.com'
        $arguments.ClientId | Should -BeExactly $script:Client
        $arguments.Interactive | Should -BeTrue
        $arguments.Tenant | Should -BeExactly 'contoso.onmicrosoft.com'
    }

    It 'signs in interactively when the settings do not say how: an older settings object' {
        $setting = New-SignInSetting
        $setting.PSObject.Properties.Remove('Authentication')

        (Get-Argument -Setting $setting).Interactive | Should -BeTrue
    }

    It 'asks for the certificate of the store by its thumbprint, in capitals, in the tenant of the ID, and not for a sign-in of a person' {
        $arguments = Get-Argument -Setting (New-SignInSetting -Override @{ Authentication = 'Certificate'; TenantId = $script:Tenant.ToUpperInvariant(); CertificateThumbprint = $script:Thumbprint })

        @($arguments.Keys | Sort-Object) | Should -Be @('ClientId', 'Tenant', 'Thumbprint', 'Url')
        $arguments.Tenant | Should -BeExactly $script:Tenant
        $arguments.Thumbprint | Should -BeExactly $script:Thumbprint.ToUpperInvariant()
        $arguments.Url | Should -BeExactly 'https://contoso-admin.sharepoint.com'
    }

    It 'asks for the file and gives its password as it was given, a SecureString' {
        $password = New-Secure -Text 'Correct-Horse-1'

        $arguments = Get-Argument -Setting (New-SignInSetting -Override @{ Authentication = 'Certificate'; TenantId = $script:Tenant; CertificatePath = '/keys/app.pfx' }) -Password $password

        @($arguments.Keys | Sort-Object) | Should -Be @('CertificatePassword', 'CertificatePath', 'ClientId', 'Tenant', 'Url')
        $arguments.CertificatePath | Should -BeExactly '/keys/app.pfx'
        $arguments.CertificatePassword | Should -Be $password
        $arguments.Tenant | Should -BeExactly $script:Tenant
    }

    It 'gives no password for a file that has none' {
        $arguments = Get-Argument -Setting (New-SignInSetting -Override @{ Authentication = 'Certificate'; TenantId = $script:Tenant; CertificatePath = '/keys/app.pfx' })

        @($arguments.Keys | Sort-Object) | Should -Be @('CertificatePath', 'ClientId', 'Tenant', 'Url')
    }

    It 'stops when what it needs is not there or is not right, whatever the settings reader did: <Name>' -ForEach @(
        @{ Name = 'no tenant ID'; Override = @{ Authentication = 'Certificate'; CertificateThumbprint = '0123456789ABCDEF0123456789ABCDEF01234567' }; Expected = '*TenantId*' }
        @{ Name = 'a tenant ID that is not a GUID'; Override = @{ Authentication = 'Certificate'; TenantId = 'contoso.onmicrosoft.com'; CertificateThumbprint = '0123456789ABCDEF0123456789ABCDEF01234567' }; Expected = '*TenantId*GUID*' }
        @{ Name = 'a tenant ID of zeros'; Override = @{ Authentication = 'Certificate'; TenantId = '00000000-0000-0000-0000-000000000000'; CertificateThumbprint = '0123456789ABCDEF0123456789ABCDEF01234567' }; Expected = '*TenantId*GUID*' }
        @{ Name = 'no certificate at all'; Override = @{ Authentication = 'Certificate'; TenantId = '8f3d2c1b-4a5e-4f60-9b7a-0c1d2e3f4a5b' }; Expected = '*exactly one of CertificateThumbprint and CertificatePath*' }
        @{ Name = 'two certificates'; Override = @{ Authentication = 'Certificate'; TenantId = '8f3d2c1b-4a5e-4f60-9b7a-0c1d2e3f4a5b'; CertificateThumbprint = '0123456789ABCDEF0123456789ABCDEF01234567'; CertificatePath = '/keys/app.pfx' }; Expected = '*exactly one of CertificateThumbprint and CertificatePath*' }
        @{ Name = 'a thumbprint that is not one'; Override = @{ Authentication = 'Certificate'; TenantId = '8f3d2c1b-4a5e-4f60-9b7a-0c1d2e3f4a5b'; CertificateThumbprint = '01:23:45' }; Expected = '*CertificateThumbprint*40 hexadecimal*' }
        @{ Name = 'a way to sign in that is not one'; Override = @{ Authentication = 'Secret' }; Expected = '*Authentication*Interactive or Certificate*' }
        @{ Name = 'no client ID'; Override = @{ ClientId = '' }; Expected = '*ClientId*' }
    ) {
        { Get-Argument -Setting (New-SignInSetting -Override $Override) } | Should -Throw -ExpectedMessage $Expected
    }
}

Describe 'Test-SPSLifecycleCertificateDate' {
    BeforeAll {
        function script:Test-Date {
            param([datetime]$NotAfter, [datetime]$NotBefore = [datetime]::new(2025, 1, 1, 0, 0, 0, [System.DateTimeKind]::Utc))

            & $script:Module { param($a, $b, $n) Test-SPSLifecycleCertificateDate -NotBefore $b -NotAfter $a -Now $n } $NotAfter $NotBefore $script:Now
        }
    }

    It 'says that a certificate that ends in 30 days or more is valid, and says nothing' {
        $result = Test-Date -NotAfter $script:Now.AddDays(30)

        $result.State | Should -BeExactly 'Valid'
        $result.Message | Should -BeExactly ''
        (Test-Date -NotAfter $script:Now.AddDays(400)).State | Should -BeExactly 'Valid'
    }

    It 'warns, with the days left and the date, when it ends in less than 30 days' -ForEach @(
        @{ Left = [System.TimeSpan]::FromDays(29.99); Days = 29 }
        @{ Left = [System.TimeSpan]::FromDays(12); Days = 12 }
        @{ Left = [System.TimeSpan]::FromHours(5); Days = 0 }
        @{ Left = [System.TimeSpan]::FromSeconds(1); Days = 0 }
    ) {
        $result = Test-Date -NotAfter $script:Now.Add($Left)

        $result.State | Should -BeExactly 'Soon'
        $result.DaysLeft | Should -Be $Days
        $result.Message | Should -BeLike "The certificate ends in $Days day*(on $($script:Now.Add($Left).ToString('yyyy-MM-dd', [System.Globalization.CultureInfo]::InvariantCulture)))*add a new one to the app before then*App-Registration*"
    }

    It 'says that a certificate that has ended is expired, at the very moment it ends and after it' -ForEach @(
        @{ After = [System.TimeSpan]::Zero }
        @{ After = [System.TimeSpan]::FromDays(-1) }
        @{ After = [System.TimeSpan]::FromDays(-400) }
    ) {
        $result = Test-Date -NotAfter $script:Now.Add($After)

        $result.State | Should -BeExactly 'Expired'
        $result.Message | Should -BeLike 'The certificate expired on *: the sign-in would fail*'
    }

    It 'says that a certificate that is not valid yet is not' {
        $result = Test-Date -NotAfter $script:Now.AddYears(2) -NotBefore $script:Now.AddHours(1)

        $result.State | Should -BeExactly 'NotYetValid'
        $result.Message | Should -BeLike 'The certificate is not valid before *'
    }

    It 'reads the dates in UTC, whatever their kind' {
        $local = [System.DateTime]::SpecifyKind($script:Now.AddDays(10), [System.DateTimeKind]::Utc).ToLocalTime()

        (Test-Date -NotAfter $local).DaysLeft | Should -Be 10
    }

    It 'says expired before it says that it is not valid yet: a certificate that ended is of no use whatever its start' {
        (Test-Date -NotAfter $script:Now.AddDays(-1) -NotBefore $script:Now.AddDays(5)).State | Should -BeExactly 'Expired'
    }
}

Describe 'Get-SPSLifecycleSignInPassword' {
    BeforeAll {
        $script:Variable = 'SPSLC_TEST_PFX_PASSWORD'

        function script:Get-Password {
            param($Setting)

            & $script:Module { param($s) Get-SPSLifecycleSignInPassword -Setting $s } $Setting
        }

        function script:Set-PromptStub {
            param([object[]]$Answer = @(), [bool]$Redirected = $false)

            Set-ModuleStub -Stub @{
                'Test-SPSLifecycleInputRedirected' = @'
$script:StubLog.Add('redirected?')
$script:StubData.Redirected
'@
                'Read-Host'                        = @'
[CmdletBinding()]
param($Prompt, [switch]$AsSecureString)
$script:StubLog.Add("ask: $Prompt | secure=$($AsSecureString.IsPresent)")
$script:StubData.Answers[0]
'@
            } -Data @{ Answers = $Answer; Redirected = $Redirected }
        }
    }

    AfterEach {
        Clear-ModuleStub
        Remove-Item -LiteralPath "Env:$script:Variable" -ErrorAction SilentlyContinue
    }

    It 'gives no password, and reads nothing, for a sign-in that has none: <Name>' -ForEach @(
        @{ Name = 'interactive'; Override = @{} }
        @{ Name = 'a certificate of the store'; Override = @{ Authentication = 'Certificate'; TenantId = '8f3d2c1b-4a5e-4f60-9b7a-0c1d2e3f4a5b'; CertificateThumbprint = '0123456789ABCDEF0123456789ABCDEF01234567' } }
    ) {
        Set-PromptStub -Answer @((New-Secure -Text 'x'))
        $env:SPSLC_TEST_PFX_PASSWORD = 'should-not-be-read'

        $null -eq (Get-Password -Setting (New-SignInSetting -Override $Override)) | Should -BeTrue

        Get-StubLog | Should -HaveCount 0
    }

    It 'reads the password from the variable that the settings name, as a SecureString' {
        Set-PromptStub
        $env:SPSLC_TEST_PFX_PASSWORD = 'Correct-Horse-Battery-1'

        $password = Get-Password -Setting (New-SignInSetting -Override @{ Authentication = 'Certificate'; CertificatePath = '/keys/app.pfx'; CertificatePasswordVariable = $script:Variable })

        $password | Should -BeOfType [System.Security.SecureString]
        [System.Net.NetworkCredential]::new('', $password).Password | Should -BeExactly 'Correct-Horse-Battery-1'
        Get-StubLog | Should -HaveCount 0
    }

    It 'stops, and names the variable and the file, when the variable is not set or is empty, without asking: a run that nobody watches cannot answer' -ForEach @(
        @{ Name = 'not set'; Value = $null }
        @{ Name = 'empty'; Value = '' }
    ) {
        Set-PromptStub -Answer @((New-Secure -Text 'asked'))
        if ($null -ne $Value) { Set-Item -LiteralPath "Env:$script:Variable" -Value $Value }

        { Get-Password -Setting (New-SignInSetting -Override @{ Authentication = 'Certificate'; CertificatePath = '/keys/app.pfx'; CertificatePasswordVariable = $script:Variable }) } | Should -Throw -ExpectedMessage "*environment variable 'SPSLC_TEST_PFX_PASSWORD' is not set*app.pfx*never goes in the settings file*"

        Get-StubLog | Should -HaveCount 0
    }

    It 'asks for the password, typed and not shown, when no variable is named, and gives it' {
        Set-PromptStub -Answer @((New-Secure -Text 'Typed-Password-1'))

        $password = Get-Password -Setting (New-SignInSetting -Override @{ Authentication = 'Certificate'; CertificatePath = '/keys/app.pfx' })

        [System.Net.NetworkCredential]::new('', $password).Password | Should -BeExactly 'Typed-Password-1'
        Get-StubLog | Should -Be @('redirected?', 'ask: Password of app.pfx (empty if the file has none) | secure=True')
    }

    It 'gives no password when nothing is typed: a file that has none' {
        Set-PromptStub -Answer @((New-Secure -Text ''))

        $null -eq (Get-Password -Setting (New-SignInSetting -Override @{ Authentication = 'Certificate'; CertificatePath = '/keys/app.pfx' })) | Should -BeTrue
    }

    It 'stops, and says what to do, when there is no variable and no one to type: the input is redirected' {
        Set-PromptStub -Answer @((New-Secure -Text 'asked')) -Redirected $true

        { Get-Password -Setting (New-SignInSetting -Override @{ Authentication = 'Certificate'; CertificatePath = '/keys/app.pfx' }) } | Should -Throw -ExpectedMessage '*input is redirected*CertificatePasswordVariable*'

        Get-StubLog | Should -Be @('redirected?')
    }
}

Describe 'Read-SPSLifecycleSignInCertificate' {
    BeforeAll {
        function script:New-PfxFile {
            param([string]$Name = 'app.pfx', [string]$Password = 'Correct-Horse-Battery-1', [switch]$PublicOnly, [int]$Days = 100, [int]$StartDays = -1)

            $folder = Join-Path -Path $TestDrive -ChildPath ([System.Guid]::NewGuid().ToString('N'))
            $null = New-Item -Path $folder -ItemType Directory
            $rsa = [System.Security.Cryptography.RSA]::Create(2048)
            $request = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new('CN=SPSSiteLifecycleTest', $rsa, [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
            $certificate = $request.CreateSelfSigned([System.DateTimeOffset]::UtcNow.AddDays($StartDays), [System.DateTimeOffset]::UtcNow.AddDays($Days))
            $path = Join-Path -Path $folder -ChildPath $Name
            if ($PublicOnly) {
                [System.IO.File]::WriteAllBytes($path, $certificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert))
            }
            elseif ($Password) {
                [System.IO.File]::WriteAllBytes($path, $certificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx, $Password))
            }
            else {
                [System.IO.File]::WriteAllBytes($path, $certificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx))
            }

            [PSCustomObject]@{ Path = $path; Certificate = $certificate }
        }

        function script:Read-Certificate {
            param($Setting, $Password = $null)

            & $script:Module { param($s, $p) Read-SPSLifecycleSignInCertificate -Setting $s -Password $p } $Setting $Password
        }
    }

    It 'reads the thumbprint, the dates and whether the file holds a private key, from a .pfx file and its password' {
        $made = New-PfxFile

        $info = Read-Certificate -Setting (New-SignInSetting -Override @{ Authentication = 'Certificate'; CertificatePath = $made.Path }) -Password (New-Secure -Text 'Correct-Horse-Battery-1')

        $info.Thumbprint | Should -BeExactly $made.Certificate.Thumbprint.ToUpperInvariant()
        $info.HasPrivateKey | Should -BeTrue
        $info.NotAfter.Kind | Should -Be ([System.DateTimeKind]::Utc)
        ([System.Math]::Abs(($info.NotAfter - $made.Certificate.NotAfter.ToUniversalTime()).TotalSeconds)) | Should -BeLessThan 1
        ([System.Math]::Abs(($info.NotBefore - $made.Certificate.NotBefore.ToUniversalTime()).TotalSeconds)) | Should -BeLessThan 1
    }

    It 'reads a .pfx file that has no password' {
        $made = New-PfxFile -Password ''

        $info = Read-Certificate -Setting (New-SignInSetting -Override @{ Authentication = 'Certificate'; CertificatePath = $made.Path })

        $info.Thumbprint | Should -BeExactly $made.Certificate.Thumbprint.ToUpperInvariant()
    }

    It 'says that the password is not the right one, without telling it, or the one that was given' {
        $made = New-PfxFile

        $message = ''
        try { $null = Read-Certificate -Setting (New-SignInSetting -Override @{ Authentication = 'Certificate'; CertificatePath = $made.Path }) -Password (New-Secure -Text 'Wrong-Password-Typed-1') } catch { $message = $_.Exception.Message }

        $message | Should -BeLike "*app.pfx*could not be opened*password*"
        $message | Should -Not -BeLike '*Wrong-Password*'
        $message | Should -Not -BeLike '*Correct-Horse*'
    }

    It 'says that a file is not a certificate, and that a file that is not there is not' {
        $folder = Join-Path -Path $TestDrive -ChildPath ([System.Guid]::NewGuid().ToString('N'))
        $null = New-Item -Path $folder -ItemType Directory
        $garbage = Join-Path -Path $folder -ChildPath 'garbage.pfx'
        Set-Content -LiteralPath $garbage -Value 'this is not a certificate'

        { Read-Certificate -Setting (New-SignInSetting -Override @{ Authentication = 'Certificate'; CertificatePath = $garbage }) } | Should -Throw -ExpectedMessage '*garbage.pfx*could not be opened*'
        { Read-Certificate -Setting (New-SignInSetting -Override @{ Authentication = 'Certificate'; CertificatePath = (Join-Path -Path $folder -ChildPath 'missing.pfx') }) } | Should -Throw -ExpectedMessage '*missing.pfx*not there*'
    }

    It 'tells that a file that holds a certificate and no private key has none: it cannot sign in' {
        $made = New-PfxFile -Name 'public.cer' -PublicOnly

        $info = Read-Certificate -Setting (New-SignInSetting -Override @{ Authentication = 'Certificate'; CertificatePath = $made.Path })

        $info.HasPrivateKey | Should -BeFalse
    }

    It 'does not leave the file open: it can be deleted right after' {
        $made = New-PfxFile

        $null = Read-Certificate -Setting (New-SignInSetting -Override @{ Authentication = 'Certificate'; CertificatePath = $made.Path }) -Password (New-Secure -Text 'Correct-Horse-Battery-1')

        { Remove-Item -LiteralPath $made.Path -Force -ErrorAction Stop } | Should -Not -Throw
    }

    It 'is for Windows only when it is given a thumbprint, and says that macOS and Linux use the file' -Skip:($IsWindows) {
        { Read-Certificate -Setting (New-SignInSetting -Override @{ Authentication = 'Certificate'; CertificateThumbprint = '0123456789ABCDEF0123456789ABCDEF01234567' }) } | Should -Throw -ExpectedMessage '*Windows only*CertificatePath*'
    }

    It 'finds a certificate of the store of the user by its thumbprint, and says when it is not there' -Skip:(-not $IsWindows) {
        $made = New-PfxFile -Name 'store.pfx' -Password 'Correct-Horse-Battery-1'
        $store = [System.Security.Cryptography.X509Certificates.X509Store]::new('My', 'CurrentUser')
        $thumbprint = $made.Certificate.Thumbprint
        try {
            $store.Open('ReadWrite')
            $imported = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($made.Path, 'Correct-Horse-Battery-1', [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::UserKeySet -bor [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::PersistKeySet)
            $store.Add($imported)

            $info = Read-Certificate -Setting (New-SignInSetting -Override @{ Authentication = 'Certificate'; CertificateThumbprint = $thumbprint })
            $info.Thumbprint | Should -BeExactly $thumbprint.ToUpperInvariant()
            $info.HasPrivateKey | Should -BeTrue
        }
        finally {
            $store.Remove($imported)
            $store.Close()
        }

        { Read-Certificate -Setting (New-SignInSetting -Override @{ Authentication = 'Certificate'; CertificateThumbprint = ('F' * 40) }) } | Should -Throw -ExpectedMessage '*no certificate with the thumbprint*store*'
    }
}

Describe 'Open-SPSLifecycleTenantSession with a certificate' {
    BeforeAll {
        function script:Set-SessionStub {
            param([hashtable]$Data = @{})

            $values = @{
                Password = $null; ConnectFails = ''
                Certificate = [PSCustomObject]@{ Thumbprint = ('A' * 40); NotBefore = $script:Now.AddDays(-10); NotAfter = $script:Now.AddDays(300); HasPrivateKey = $true }
            }
            foreach ($key in $Data.Keys) { $values[$key] = $Data[$key] }

            Set-ModuleStub -Stub @{
                'Assert-SPSLifecyclePnPModule'       = @'
$script:StubLog.Add('module checked')
'@
                'Get-SPSLifecycleSignInPassword'     = @'
param($Setting)
$script:StubLog.Add('password')
$script:StubData.Password
'@
                'Read-SPSLifecycleSignInCertificate' = @'
param($Setting, $Password)
$script:StubLog.Add("certificate password=$($null -ne $Password)")
$script:StubData.Certificate
'@
                'Connect-PnPOnline'                  = @'
[CmdletBinding()]
param([string]$Url, [switch]$Interactive, [string]$ClientId, [string]$Tenant, [string]$Thumbprint, [string]$CertificatePath, $CertificatePassword, [switch]$ReturnConnection)
$script:StubLog.Add("connect Url=$Url Interactive=$($Interactive.IsPresent) ClientId=$ClientId Tenant=$Tenant Thumbprint=$Thumbprint Path=$CertificatePath Password=$($null -ne $CertificatePassword) Return=$($ReturnConnection.IsPresent)")
if ($script:StubData.ConnectFails) { throw $script:StubData.ConnectFails }
'a connection'
'@
            } -Data $values
        }

        # Opens the session, and gives it with the warnings that the sign-in gave.
        function script:Open-Session {
            param($Setting)

            & $script:Module {
                param($s, $n)
                $w = $null
                $session = Open-SPSLifecycleTenantSession -Setting $s -Now $n -WarningAction SilentlyContinue -WarningVariable w
                [PSCustomObject]@{ Session = $session; Warnings = @($w | ForEach-Object { "$_" }) }
            } $Setting $script:Now
        }

        function script:New-CertificateSetting {
            param([hashtable]$Override = @{})

            $values = @{ Authentication = 'Certificate'; TenantId = $script:Tenant; CertificateThumbprint = $script:Thumbprint }
            foreach ($key in $Override.Keys) { $values[$key] = $Override[$key] }
            New-SignInSetting -Override $values
        }
    }

    AfterEach {
        Clear-ModuleStub
    }

    It 'signs in with the certificate of the store, by its thumbprint, to the admin site, in the tenant of the ID, and keeps the connection to itself' {
        Set-SessionStub

        $result = Open-Session -Setting (New-CertificateSetting)

        Get-StubLog | Should -Be @(
            'module checked'
            'password'
            'certificate password=False'
            "connect Url=https://contoso-admin.sharepoint.com Interactive=False ClientId=$script:Client Tenant=$script:Tenant Thumbprint=$($script:Thumbprint.ToUpperInvariant()) Path= Password=False Return=True"
        )
        $result.Session.Connection | Should -BeExactly 'a connection'
        $result.Session.TenantName | Should -BeExactly 'contoso'
        $result.Session.AdminUrl | Should -BeExactly 'https://contoso-admin.sharepoint.com'
        @($result.Session.RefusedTenants) | Should -Be @('microsoft', 'microsoftonline')
        $result.Warnings | Should -HaveCount 0
    }

    It 'signs in with the file and its password, when the settings name a file' {
        Set-SessionStub -Data @{ Password = (New-Secure -Text 'Correct-Horse-Battery-1') }

        $null = Open-Session -Setting (New-CertificateSetting -Override @{ CertificateThumbprint = $null; CertificatePath = '/keys/app.pfx' })

        Get-StubLog | Should -Be @(
            'module checked'
            'password'
            'certificate password=True'
            "connect Url=https://contoso-admin.sharepoint.com Interactive=False ClientId=$script:Client Tenant=$script:Tenant Thumbprint= Path=/keys/app.pfx Password=True Return=True"
        )
    }

    It 'does not touch the certificate, and does not even load PnP.PowerShell, for a tenant that is refused' {
        Set-SessionStub

        { Open-Session -Setting (New-CertificateSetting -Override @{ TenantName = 'microsoft'; AdminUrl = 'https://microsoft-admin.sharepoint.com' }) } | Should -Throw -ExpectedMessage '*refused*'

        Get-StubLog | Should -HaveCount 0
    }

    It 'checks the settings before it asks for a password or reads a certificate: <Name>' -ForEach @(
        @{ Name = 'no tenant ID'; Override = @{ TenantId = $null }; Expected = '*TenantId*' }
        @{ Name = 'two certificates'; Override = @{ CertificatePath = '/keys/app.pfx' }; Expected = '*exactly one of*' }
        @{ Name = 'no client ID'; Override = @{ ClientId = '' }; Expected = '*ClientId*' }
    ) {
        Set-SessionStub

        { Open-Session -Setting (New-CertificateSetting -Override $Override) } | Should -Throw -ExpectedMessage $Expected

        Get-StubLog | Should -HaveCount 0
    }

    It 'stops before it signs in when the certificate has expired, is not valid yet, or has no private key: <Name>' -ForEach @(
        @{ Name = 'expired'; Certificate = @{ NotBefore = -400; NotAfter = -1; HasPrivateKey = $true }; Expected = '*expired*' }
        @{ Name = 'at the very moment it ends'; Certificate = @{ NotBefore = -400; NotAfter = 0; HasPrivateKey = $true }; Expected = '*expired*' }
        @{ Name = 'not valid yet'; Certificate = @{ NotBefore = 2; NotAfter = 400; HasPrivateKey = $true }; Expected = '*not valid before*' }
        @{ Name = 'no private key'; Certificate = @{ NotBefore = -10; NotAfter = 400; HasPrivateKey = $false }; Expected = '*no private key*' }
    ) {
        Set-SessionStub -Data @{ Certificate = [PSCustomObject]@{ Thumbprint = ('A' * 40); NotBefore = $script:Now.AddDays($Certificate.NotBefore); NotAfter = $script:Now.AddDays($Certificate.NotAfter); HasPrivateKey = $Certificate.HasPrivateKey } }

        { Open-Session -Setting (New-CertificateSetting) } | Should -Throw -ExpectedMessage $Expected

        @(Get-StubLog | Where-Object { $_ -like 'connect*' }) | Should -HaveCount 0
    }

    It 'warns, and signs in, when the certificate ends in less than 30 days, saying how many and what to do' {
        Set-SessionStub -Data @{ Certificate = [PSCustomObject]@{ Thumbprint = ('A' * 40); NotBefore = $script:Now.AddDays(-300); NotAfter = $script:Now.AddDays(12); HasPrivateKey = $true } }

        $result = Open-Session -Setting (New-CertificateSetting)

        $result.Warnings | Should -HaveCount 1
        $result.Warnings[0] | Should -BeLike 'The certificate ends in 12 days*add a new one to the app before then*'
        @(Get-StubLog | Where-Object { $_ -like 'connect*' }) | Should -HaveCount 1
    }

    It 'says that the sign-in failed, and why, as for the interactive one' {
        Set-SessionStub -Data @{ ConnectFails = 'AADSTS700027: Client assertion contains an invalid signature.' }

        { Open-Session -Setting (New-CertificateSetting) } | Should -Throw -ExpectedMessage '*sign-in*admin site*failed*AADSTS700027*'
    }

    It 'does not tell the password in the message of a sign-in that failed' {
        Set-SessionStub -Data @{ Password = (New-Secure -Text 'Correct-Horse-Battery-1'); ConnectFails = 'The certificate could not be opened.' }

        $message = ''
        try { $null = Open-Session -Setting (New-CertificateSetting -Override @{ CertificateThumbprint = $null; CertificatePath = '/keys/app.pfx' }) } catch { $message = $_.Exception.Message }

        $message | Should -BeLike '*could not be opened*'
        $message | Should -Not -BeLike '*Correct-Horse*'
    }
}
