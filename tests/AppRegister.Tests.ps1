BeforeAll {
    $script:Manifest = Join-Path -Path $PSScriptRoot -ChildPath '../src/Modules/SPSSiteLifecycle.Common/SPSSiteLifecycle.Common.psd1'
    $script:Module = Import-Module -Name $script:Manifest -Force -PassThru
    $script:Pwsh = (Get-Process -Id $PID).Path
    $script:Now = [System.DateTime]::new(2026, 10, 30, 9, 15, 0, [System.DateTimeKind]::Utc)
    $script:ClientId = '4d3c2b1a-0f9e-4d8c-8b7a-6f5e4d3c2b1a'
    $script:Thumbprint = '0123456789ABCDEF0123456789ABCDEF01234567'
    $script:Password = 'Correct-Horse-Battery-1'

    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers/ModuleStub.ps1')
    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers/Signal.ps1')

    # What the registration depends on, replaced: the checks of PnP.PowerShell, the answers of the person, the cmdlet (which, like the real one,
    # writes the certificate files before it fails), and what is done to the key and to the store.
    function script:Set-RegisterStub {
        param([hashtable]$Data = @{})

        $values = @{
            Redirected = $false; Answers = @('contoso'); AnswerIndex = 0; PnPMissing = $false; PasswordFails = ''; Windows = $false
            Record = [PSCustomObject]@{ ClientId = $script:ClientId; Thumbprint = $script:Thumbprint }
            Fail = ''; WriteFiles = $true; Protect = $true; StoreFails = ''; StoreThumbprint = $script:Thumbprint
            Info = [PSCustomObject]@{ Thumbprint = $script:Thumbprint; NotAfter = [System.DateTime]::new(2028, 10, 29, 22, 0, 0, [System.DateTimeKind]::Utc) }
            Key = [PSCustomObject]@{ Thumbprint = $script:Thumbprint; HasPrivateKey = $true }
            Password = $script:Password
        }
        foreach ($key in $Data.Keys) { $values[$key] = $Data[$key] }

        Set-ModuleStub -Stub @{
            'Assert-SPSLifecyclePnPModule'         = @'
$script:StubLog.Add('pnp check')
if ($script:StubData.PnPMissing) { throw 'PnP.PowerShell is not installed.' }
'@
            'Test-SPSLifecycleInputRedirected'     = @'
$script:StubLog.Add('redirected?')
$script:StubData.Redirected
'@
            'Read-Host'                            = @'
[CmdletBinding()]
param($Prompt)
$script:StubLog.Add("ask: $Prompt")
$answer = $script:StubData.Answers[$script:StubData.AnswerIndex]
$script:StubData.AnswerIndex++
$answer
'@
            'Read-SPSLifecycleCertificatePassword' = @'
$script:StubLog.Add('password')
if ($script:StubData.PasswordFails) { throw $script:StubData.PasswordFails }
$secure = [System.Security.SecureString]::new()
foreach ($character in $script:StubData.Password.ToCharArray()) { $secure.AppendChar($character) }
$secure
'@
            'Register-SPSLifecycleEntraApp'        = @'
param($Plan, $CertificatePassword)
$folderExists = $false
if ($Plan.Kind -eq 'Certificate') { $folderExists = Test-Path -LiteralPath $Plan.Certificate.Folder }
$script:StubLog.Add("register $($Plan.Kind) $($Plan.TenantDomain) $($Plan.ApplicationName) password=$($null -ne $CertificatePassword) folder=$folderExists")
if ($Plan.Kind -eq 'Certificate' -and $script:StubData.WriteFiles) {
    Set-Content -LiteralPath $Plan.Certificate.PfxPath -Value 'THE KEY'
    Set-Content -LiteralPath $Plan.Certificate.CerPath -Value 'THE CERTIFICATE'
}
if ($script:StubData.Fail) { throw $script:StubData.Fail }
$script:StubData.Record
'@
            'Protect-SPSLifecyclePrivateKey'       = @'
param($Path)
$script:StubLog.Add("protect $(Split-Path -Path $Path -Leaf)")
$script:StubData.Protect
'@
            'Read-SPSLifecycleCertificateInfo'     = @'
param($Path)
$script:StubLog.Add("read $(Split-Path -Path $Path -Leaf)")
$script:StubData.Info
'@
            'Read-SPSLifecycleKeyFile'             = @'
param($Path, $Password)
$script:StubLog.Add("key $(Split-Path -Path $Path -Leaf) password=$($null -ne $Password)")
$script:StubData.Key
'@
            'Add-SPSLifecycleCertificateToStore'   = @'
param($Path, $Password)
$script:StubLog.Add("store $(Split-Path -Path $Path -Leaf) password=$($null -ne $Password)")
if ($script:StubData.StoreFails) { throw $script:StubData.StoreFails }
$script:StubData.StoreThumbprint
'@
            'Test-SPSLifecycleWindowsPlatform'     = @'
$script:StubData.Windows
'@
        } -Data $values

        if ($values.Windows -or $IsWindows) {
            # The real function makes the mode of Unix or an access control list of Windows, and each exists on its own system only: where the
            # tests say that the system is Windows, or where it is, the folder is plain.
            Set-ModuleStub -Stub @{
                'New-SPSLifecycleProtectedFolder' = @'
param($Path)
$null = New-Item -Path $Path -ItemType Directory -Force
$true
'@
            } -Data (& $script:Module { $script:StubData })
        }
    }

    # Runs the registration and gives what it did: the result, the lines of information, the warnings, the error and the log of the stubs.
    function script:Invoke-TestRegister {
        param([hashtable]$Parameter, [switch]$All)

        $arguments = @{ TenantName = 'contoso'; Now = $script:Now }
        foreach ($key in $Parameter.Keys) { $arguments[$key] = $Parameter[$key] }
        $message = ''
        $result = $null
        $info = $null
        $warnings = $null
        $stream = @()
        try {
            if ($All) {
                $stream = @(Register-SPSLifecycleApp @arguments -InformationAction Continue -Verbose -Debug:$false 4>&1 5>&1 3>&1 6>&1)
                $result = @($stream | Where-Object { $_ -is [System.Management.Automation.PSCustomObject] -and $null -ne $_.PSObject.Properties['ClientId'] })[0]
            }
            else {
                $result = Register-SPSLifecycleApp @arguments -InformationAction SilentlyContinue -InformationVariable info -WarningAction SilentlyContinue -WarningVariable warnings
            }
        }
        catch {
            $message = $_.Exception.Message
        }

        [PSCustomObject]@{
            Result   = $result
            Info     = @($info | ForEach-Object { "$($_.MessageData)" })
            Warnings = @($warnings | ForEach-Object { "$_" })
            Error    = $message
            Log      = @(Get-StubLog)
            Stream   = @($stream | ForEach-Object { "$_" })
        }
    }

    # The folder that a person gives: the key folder is made in it, named after the app.
    function script:New-KeyFolder {
        Join-Path -Path $TestDrive -ChildPath "keys-$([System.Guid]::NewGuid().ToString('N'))"
    }

    function script:Get-KeyPath {
        param([string]$Parent, [string]$Leaf = 'SPSSiteLifecycle.pfx')

        Join-Path -Path (Join-Path -Path $Parent -ChildPath 'SPSSiteLifecycle') -ChildPath $Leaf
    }

    $script:PromptInteractive = "ask: Register the app 'SPSSiteLifecycle' (Interactive) in the tenant contoso, with the permissions SharePoint AllSites.FullControl, Graph Group.ReadWrite.All. Type the name of the tenant to go on"
    $script:PromptCertificate = "ask: Register the app 'SPSSiteLifecycle' (Certificate) in the tenant contoso, with the permissions SharePoint Sites.FullControl.All, Graph Group.ReadWrite.All. Type the name of the tenant to go on"

    Install-Tripwire
}

AfterAll {
    Remove-Tripwire
}

Describe 'Register-SPSLifecycleApp: what is checked first, and the plan' {
    BeforeEach {
        Set-RegisterStub
    }

    AfterEach {
        Clear-ModuleStub
    }

    It 'refuses a tenant that the tool refuses, and does nothing: <Tenant>' -ForEach @(
        @{ Tenant = 'microsoft' }
        @{ Tenant = 'MicrosoftOnline' }
        @{ Tenant = 'contoso.sharepoint.com' }
    ) {
        $run = Invoke-TestRegister -Parameter @{ TenantName = $Tenant }

        $run.Error | Should -BeLike '*TenantName*'
        $run.Log | Should -HaveCount 0
        $run.Info | Should -HaveCount 0
    }

    It 'refuses a name that is not valid, and does nothing' {
        $run = Invoke-TestRegister -Parameter @{ ApplicationName = '../x' }

        $run.Error | Should -BeLike '*ApplicationName*'
        $run.Log | Should -HaveCount 0
    }

    It 'refuses what only a certificate takes, for an app that a person signs in with: <Name>' -ForEach @(
        @{ Name = 'OutputFolder'; Parameter = @{ OutputFolder = '/keys' } }
        @{ Name = 'ValidYears'; Parameter = @{ ValidYears = 3 } }
        @{ Name = 'UseCertificateStore'; Parameter = @{ UseCertificateStore = $true } }
    ) {
        $run = Invoke-TestRegister -Parameter $Parameter

        $run.Error | Should -BeLike "-$Name is for the Certificate kind*"
        $run.Log | Should -HaveCount 0
    }

    It 'refuses the certificate store where there is none, and does nothing' {
        $run = Invoke-TestRegister -Parameter @{ Kind = 'Certificate'; OutputFolder = (New-KeyFolder); UseCertificateStore = $true }

        $run.Error | Should -BeLike '*Windows only*.pfx file*'
        $run.Log | Should -HaveCount 0
    }

    It 'refuses a number of years outside 1 to 30' -ForEach @(
        @{ Years = 0 }
        @{ Years = 31 }
        @{ Years = -2 }
    ) {
        $run = Invoke-TestRegister -Parameter @{ Kind = 'Certificate'; OutputFolder = (New-KeyFolder); ValidYears = $Years }

        $run.Error | Should -Not -BeNullOrEmpty
        $run.Log | Should -HaveCount 0
    }

    It 'refuses a folder inside a repository, and the folder of the tool, before it shows the plan or asks anything' {
        $repository = Join-Path -Path $TestDrive -ChildPath 'repo'
        $null = New-Item -Path (Join-Path -Path $repository -ChildPath '.git') -ItemType Directory -Force

        $run = Invoke-TestRegister -Parameter @{ Kind = 'Certificate'; OutputFolder = (Join-Path -Path $repository -ChildPath 'keys') }
        $run.Error | Should -BeLike '*inside a repository*'
        $run.Info | Should -HaveCount 0
        $run.Log | Should -HaveCount 0

        $tool = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..')).ProviderPath
        $run = Invoke-TestRegister -Parameter @{ Kind = 'Certificate'; OutputFolder = (Join-Path -Path $tool -ChildPath 'keys') }
        $run.Error | Should -Match 'inside (a repository|the folder of the tool)'
        $run.Log | Should -HaveCount 0
    }

    It 'refuses a key folder that is already there, with a key in it or not, and does nothing' {
        $folder = New-KeyFolder
        $null = New-Item -Path (Join-Path -Path $folder -ChildPath 'SPSSiteLifecycle') -ItemType Directory -Force
        Set-Content -LiteralPath (Get-KeyPath -Parent $folder) -Value 'x'

        $run = Invoke-TestRegister -Parameter @{ Kind = 'Certificate'; OutputFolder = $folder }

        $run.Error | Should -BeLike '*SPSSiteLifecycle*already there*nothing in it is replaced*'
        $run.Log | Should -HaveCount 0
        Get-Content -LiteralPath (Get-KeyPath -Parent $folder) | Should -BeExactly 'x'
    }

    It 'shows the plan and stops with -WhatIf: nothing is asked, nothing is created' {
        $folder = New-KeyFolder

        $run = Invoke-TestRegister -Parameter @{ Kind = 'Certificate'; OutputFolder = $folder; WhatIf = $true }

        $run.Error | Should -BeNullOrEmpty
        $null -eq $run.Result | Should -BeTrue
        $run.Info[0] | Should -BeLike 'App registration plan (nothing has been changed yet)*'
        ($run.Info -join "`n") | Should -BeLike "*$folder*"
        $run.Log | Should -HaveCount 0
        Test-Path -LiteralPath $folder | Should -BeFalse
    }

    It 'puts the files in a .spssitelifecycle folder of the profile of the user when no folder is given' {
        $run = Invoke-TestRegister -Parameter @{ Kind = 'Certificate'; WhatIf = $true }

        $run.Error | Should -BeNullOrEmpty
        ($run.Info -join "`n") | Should -BeLike '*.spssitelifecycle*SPSSiteLifecycle.pfx*'
    }

    It 'shows the plan before it asks for anything, and says what is asked' {
        $run = Invoke-TestRegister -Parameter @{ Kind = 'Interactive' }

        $run.Info[0] | Should -BeLike 'App registration plan*'
        ($run.Info -join "`n") | Should -BeLike '*Delegated permissions requested*AllSites.FullControl*Group.ReadWrite.All*'
    }
}

Describe 'Register-SPSLifecycleApp: the confirmation' {
    BeforeEach {
        Set-RegisterStub
    }

    AfterEach {
        Clear-ModuleStub
    }

    It 'checks PnP.PowerShell before it asks anything: a person should not type for nothing' {
        Set-RegisterStub -Data @{ PnPMissing = $true }

        $run = Invoke-TestRegister -Parameter @{}

        $run.Error | Should -BeLike '*PnP.PowerShell is not installed*'
        $run.Log | Should -Be @('pnp check')
    }

    It 'stops, with nothing done, when what is typed is not the tenant, and asks for no password' {
        Set-RegisterStub -Data @{ Answers = @('fabrikam') }

        $run = Invoke-TestRegister -Parameter @{ Kind = 'Certificate'; OutputFolder = (New-KeyFolder) }

        $run.Error | Should -BeLike '*does not match the tenant (contoso). Nothing was changed.'
        $run.Log | Should -Be @('pnp check', 'redirected?', $script:PromptCertificate)
    }

    It 'stops before it asks when the input is redirected' {
        Set-RegisterStub -Data @{ Redirected = $true }

        $run = Invoke-TestRegister -Parameter @{}

        $run.Error | Should -BeLike '*input is redirected*'
        $run.Log | Should -Be @('pnp check', 'redirected?')
    }

    It 'goes on when the tenant is typed in another case, with spaces around it' {
        Set-RegisterStub -Data @{ Answers = @('  CONTOSO ') }

        $run = Invoke-TestRegister -Parameter @{}

        $run.Error | Should -BeNullOrEmpty
        $run.Result.ClientId | Should -BeExactly $script:ClientId
    }
}

Describe 'Register-SPSLifecycleApp: an app that a person signs in with' {
    AfterEach {
        Clear-ModuleStub
    }

    It 'registers it, says what to put in the settings file, and gives the client ID' {
        Set-RegisterStub

        $run = Invoke-TestRegister -Parameter @{}

        $run.Error | Should -BeNullOrEmpty
        $run.Log | Should -Be @('pnp check', 'redirected?', $script:PromptInteractive, 'register Interactive contoso.onmicrosoft.com SPSSiteLifecycle password=False folder=False')
        @($run.Result.PSObject.Properties.Name) | Should -Be @('TenantName', 'ApplicationName', 'Kind', 'ClientId', 'Thumbprint', 'ExpiresOn', 'PfxPath', 'CerPath', 'KeyProtected', 'StoredInCertificateStore')
        $run.Result.ClientId | Should -BeExactly $script:ClientId
        $run.Result.Kind | Should -BeExactly 'Interactive'
        $run.Result.PfxPath | Should -BeExactly ''
        $run.Result.KeyProtected | Should -BeExactly $false
        $run.Result.StoredInCertificateStore | Should -BeExactly $false
        $run.Info | Should -Contain "    TenantName = 'contoso'"
        $run.Info | Should -Contain "    ClientId   = '$script:ClientId'"
    }

    It 'asks for no password, makes no folder and protects no key' {
        Set-RegisterStub

        $run = Invoke-TestRegister -Parameter @{}

        @($run.Log | Where-Object { $_ -like 'password*' -or $_ -like 'protect*' -or $_ -like 'store*' -or $_ -like 'read *' }) | Should -HaveCount 0
    }

    It 'goes through the name that is given, and the device code when it is asked for' {
        Set-RegisterStub

        $run = Invoke-TestRegister -Parameter @{ ApplicationName = 'My-App'; DeviceLogin = $true }

        $run.Log[-1] | Should -BeLike 'register Interactive contoso.onmicrosoft.com My-App*'
        ($run.Info -join "`n") | Should -BeLike '*device code*'
    }

    It 'says that the name is taken, and that nothing was created, with no file to speak of' {
        Set-RegisterStub -Data @{ Fail = 'The application with name SPSSiteLifecycle already exists.' }

        $run = Invoke-TestRegister -Parameter @{}

        $run.Error | Should -BeLike "An application named 'SPSSiteLifecycle' already exists in this tenant, so nothing was created.*another name with -ApplicationName*"
        $run.Error | Should -Not -BeLike '*certificate files*'
    }

    It 'says that nothing came back when the sign-in was cancelled' {
        Set-RegisterStub -Data @{ Record = $null }

        $run = Invoke-TestRegister -Parameter @{}

        $run.Error | Should -BeLike '*gave nothing back*cancelled*no app was created as far as is known*Microsoft Entra admin center*'
    }
}

Describe 'Register-SPSLifecycleApp: an app that signs in alone, with a certificate' {
    AfterEach {
        Clear-ModuleStub
    }

    It 'asks the password after the tenant, makes the folder, registers, protects the key, reads the certificate, and says what to keep' {
        Set-RegisterStub
        $folder = New-KeyFolder

        $run = Invoke-TestRegister -Parameter @{ Kind = 'Certificate'; OutputFolder = $folder }

        $run.Error | Should -BeNullOrEmpty
        $run.Log | Should -Be @(
            'pnp check'
            'redirected?'
            $script:PromptCertificate
            'password'
            'register Certificate contoso.onmicrosoft.com SPSSiteLifecycle password=True folder=True'
            'protect SPSSiteLifecycle.pfx'
            'read SPSSiteLifecycle.cer'
            'key SPSSiteLifecycle.pfx password=True'
            'protect SPSSiteLifecycle.pfx'
        )
        $run.Result.Thumbprint | Should -BeExactly $script:Thumbprint
        $run.Result.PfxPath | Should -BeExactly (Get-KeyPath -Parent $folder)
        $run.Result.CerPath | Should -BeExactly (Get-KeyPath -Parent $folder -Leaf 'SPSSiteLifecycle.cer')
        $run.Result.ExpiresOn | Should -Be ([System.DateTime]::new(2028, 10, 29, 22, 0, 0, [System.DateTimeKind]::Utc))
        $run.Result.KeyProtected | Should -BeExactly $true
        $run.Result.StoredInCertificateStore | Should -BeExactly $false
        ($run.Info -join "`n") | Should -BeLike "*thumbprint $script:Thumbprint, and it ends on 2028-10-29*"
        ($run.Info -join "`n") | Should -BeLike '*can be read by your account only*'
    }

    It 'makes a folder that only the user can read, before the key is written in it' -Skip:($IsWindows) {
        Set-RegisterStub
        $folder = New-KeyFolder

        $null = Invoke-TestRegister -Parameter @{ Kind = 'Certificate'; OutputFolder = $folder }

        [System.IO.File]::GetUnixFileMode((Join-Path -Path $folder -ChildPath 'SPSSiteLifecycle')) | Should -Be ([System.IO.UnixFileMode]::UserRead -bor [System.IO.UnixFileMode]::UserWrite -bor [System.IO.UnixFileMode]::UserExecute)
    }

    It 'makes the certificate valid for 2 years when it is not told otherwise' {
        Set-RegisterStub

        $run = Invoke-TestRegister -Parameter @{ Kind = 'Certificate'; OutputFolder = (New-KeyFolder) }

        ($run.Info -join "`n") | Should -BeLike '*self-signed, valid 2 years (until about*'
    }

    It 'accepts the thumbprint that the store gives in lower case: it is the same certificate' {
        Set-RegisterStub -Data @{ Windows = $true; StoreThumbprint = $script:Thumbprint.ToLowerInvariant() }

        $run = Invoke-TestRegister -Parameter @{ Kind = 'Certificate'; OutputFolder = (New-KeyFolder); UseCertificateStore = $true }

        $run.Error | Should -BeNullOrEmpty
        $run.Result.StoredInCertificateStore | Should -BeExactly $true
    }

    It 'checks the folder again once it exists, and stops before the cmdlet writes in a folder that is then found inside a repository or the tool' {
        Set-RegisterStub
        Set-ModuleStub -Stub @{
            'Assert-SPSLifecycleOutsideRepository' = @'
param($Path, $ToolRoot)
if (Test-Path -LiteralPath $Path) { throw "The folder '$Path' is inside a repository (found once it was made)." }
'@
        } -Data (& $script:Module { $script:StubData })
        $folder = New-KeyFolder

        $run = Invoke-TestRegister -Parameter @{ Kind = 'Certificate'; OutputFolder = $folder }

        $run.Error | Should -BeLike '*inside a repository (found once it was made)*'
        @($run.Log | Where-Object { $_ -like 'register*' }) | Should -HaveCount 0
        Test-Path -LiteralPath (Join-Path -Path $folder -ChildPath 'SPSSiteLifecycle') | Should -BeFalse
    }

    It 'does not say that the registration was interrupted when it ended, with an app or with a failure' {
        Set-RegisterStub
        $run = Invoke-TestRegister -Parameter @{ Kind = 'Certificate'; OutputFolder = (New-KeyFolder) }
        ($run.Warnings -join "`n") | Should -Not -BeLike '*interrupted*'

        Set-RegisterStub -Data @{ Fail = 'The application with name SPSSiteLifecycle already exists.' }
        $run = Invoke-TestRegister -Parameter @{ Kind = 'Certificate'; OutputFolder = (New-KeyFolder) }
        $run.Error | Should -Not -BeNullOrEmpty
        ($run.Warnings -join "`n") | Should -Not -BeLike '*interrupted*'
    }

    It 'dates the end of the certificate from the certificate that the app got, and from nothing that was only planned' {
        Set-RegisterStub -Data @{ Info = [PSCustomObject]@{ Thumbprint = $script:Thumbprint; NotAfter = [System.DateTime]::new(2031, 10, 29, 22, 0, 0, [System.DateTimeKind]::Utc) } }

        $run = Invoke-TestRegister -Parameter @{ Kind = 'Certificate'; OutputFolder = (New-KeyFolder); ValidYears = 5 }

        $run.Result.ExpiresOn | Should -Be ([System.DateTime]::new(2031, 10, 29, 22, 0, 0, [System.DateTimeKind]::Utc))
    }

    It 'says that the key could not be restricted when it could not' {
        Set-RegisterStub -Data @{ Protect = $false }

        $run = Invoke-TestRegister -Parameter @{ Kind = 'Certificate'; OutputFolder = (New-KeyFolder) }

        $run.Error | Should -BeNullOrEmpty
        $run.Result.KeyProtected | Should -BeExactly $false
        ($run.Info -join "`n") | Should -BeLike '*could not be restricted to your account: do it by hand*'
    }

    It 'adds the certificate to the store of the user when it is asked to, on Windows' {
        Set-RegisterStub -Data @{ Windows = $true }

        $run = Invoke-TestRegister -Parameter @{ Kind = 'Certificate'; OutputFolder = (New-KeyFolder); UseCertificateStore = $true }

        $run.Log | Should -Contain 'store SPSSiteLifecycle.pfx password=True'
        $run.Result.StoredInCertificateStore | Should -BeTrue
        ($run.Info -join "`n") | Should -BeLike "*Cert:\CurrentUser\My\$script:Thumbprint*"
    }

    It 'does not add it to the store when it is not asked to' {
        Set-RegisterStub -Data @{ Windows = $true }

        $run = Invoke-TestRegister -Parameter @{ Kind = 'Certificate'; OutputFolder = (New-KeyFolder) }

        @($run.Log | Where-Object { $_ -like 'store*' }) | Should -HaveCount 0
        $run.Result.StoredInCertificateStore | Should -BeFalse
    }

    It 'warns, and goes on with the file, when the certificate cannot be added to the store' {
        Set-RegisterStub -Data @{ Windows = $true; StoreFails = 'Access is denied.' }

        $run = Invoke-TestRegister -Parameter @{ Kind = 'Certificate'; OutputFolder = (New-KeyFolder); UseCertificateStore = $true }

        $run.Error | Should -BeNullOrEmpty
        $run.Result.StoredInCertificateStore | Should -BeFalse
        ($run.Warnings -join ' ') | Should -BeLike '*could not be added to the CurrentUser store (Access is denied)*'
        ($run.Info -join "`n") | Should -Not -BeLike '*Cert:\CurrentUser*'
    }

    It 'stops, before the folder and the cmdlet, when the password is refused' {
        Set-RegisterStub -Data @{ PasswordFails = 'The two passwords are not the same. Nothing was changed.' }
        $folder = New-KeyFolder

        $run = Invoke-TestRegister -Parameter @{ Kind = 'Certificate'; OutputFolder = $folder }

        $run.Error | Should -BeLike '*not the same*'
        $run.Log[-1] | Should -Be 'password'
        Test-Path -LiteralPath $folder | Should -BeFalse
    }

    It 'stops, and says what to do, when the cmdlet did not write the files' {
        Set-RegisterStub -Data @{ WriteFiles = $false }

        $run = Invoke-TestRegister -Parameter @{ Kind = 'Certificate'; OutputFolder = (New-KeyFolder) }

        $run.Error | Should -BeLike "*The app 'SPSSiteLifecycle' was created (client ID $script:ClientId), but PnP.PowerShell did not write*Delete the app*"
    }

    It 'stops when the certificate of the file is not the one that the app got' {
        Set-RegisterStub -Data @{ Info = [PSCustomObject]@{ Thumbprint = ('F' * 40); NotAfter = [System.DateTime]::UtcNow } }

        $run = Invoke-TestRegister -Parameter @{ Kind = 'Certificate'; OutputFolder = (New-KeyFolder) }

        $run.Error | Should -BeLike "*is not the one that the app got (thumbprint $script:Thumbprint)*Delete the app*"
    }
}

Describe 'Register-SPSLifecycleApp: when it fails, and what became of the files' {
    AfterEach {
        Clear-ModuleStub
    }

    It 'removes the files that the cmdlet wrote, and the folder, when the name is taken: PnP.PowerShell says so before it creates the app' {
        Set-RegisterStub -Data @{ Fail = 'The application with name SPSSiteLifecycle already exists.' }
        $folder = New-KeyFolder

        $run = Invoke-TestRegister -Parameter @{ Kind = 'Certificate'; OutputFolder = $folder }

        $run.Error | Should -BeLike '*already exists in this tenant, so nothing was created.*were removed*'
        Test-Path -LiteralPath (Get-KeyPath -Parent $folder) | Should -BeFalse
        Test-Path -LiteralPath (Get-KeyPath -Parent $folder -Leaf 'SPSSiteLifecycle.cer') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path -Path $folder -ChildPath 'SPSSiteLifecycle') | Should -BeFalse -Because 'the key folder was made for this run, and is empty'
        $run.Log | Should -Contain 'protect SPSSiteLifecycle.pfx'
    }

    It 'keeps the files when an app may exist, and says so: <Name>' -ForEach @(
        @{ Name = 'the account is refused: a refusal of Graph can come after the app was created'; Fail = 'Authorization_RequestDenied: Insufficient privileges to complete the operation.'; Expected = '*refused your account*does not prove it*look for an app named*were kept*' }
        @{ Name = 'the consent failed'; Fail = 'AADSTS65001: The user or administrator has not consented.'; Expected = '*may have been created*were kept*' }
        @{ Name = 'nobody can tell'; Fail = 'A task was canceled.'; Expected = '*may or may not exist*were kept*' }
    ) {
        Set-RegisterStub -Data @{ Fail = $Fail }
        $folder = New-KeyFolder

        $run = Invoke-TestRegister -Parameter @{ Kind = 'Certificate'; OutputFolder = $folder }

        $run.Error | Should -BeLike $Expected
        Test-Path -LiteralPath (Get-KeyPath -Parent $folder) | Should -BeTrue
        Test-Path -LiteralPath (Get-KeyPath -Parent $folder -Leaf 'SPSSiteLifecycle.cer') | Should -BeTrue
        $run.Error | Should -BeLike "*$(Get-KeyPath -Parent $folder)*"
        $run.Error | Should -Not -BeLike '*Nothing was created.*'
    }

    It 'does not delete a key after a refusal that came when the app already existed: the only copy' {
        Set-RegisterStub -Data @{ Fail = 'Response status code does not indicate success: 403 (Forbidden). Authorization_RequestDenied (the consent)' }
        $folder = New-KeyFolder

        $null = Invoke-TestRegister -Parameter @{ Kind = 'Certificate'; OutputFolder = $folder }

        (Get-Content -LiteralPath (Get-KeyPath -Parent $folder)) | Should -BeExactly 'THE KEY'
    }

    It 'removes nothing but the two files of the app, by their names, and keeps the folder when something else is in it' {
        Set-RegisterStub -Data @{ Fail = 'The application with name SPSSiteLifecycle already exists.' }
        Set-ModuleStub -Stub @{
            'Register-SPSLifecycleEntraApp' = @'
param($Plan, $CertificatePassword)
Set-Content -LiteralPath $Plan.Certificate.PfxPath -Value 'THE KEY'
Set-Content -LiteralPath $Plan.Certificate.CerPath -Value 'THE CERTIFICATE'
Set-Content -LiteralPath (Join-Path -Path $Plan.Certificate.Folder -ChildPath 'notes.txt') -Value 'not ours to remove'
throw $script:StubData.Fail
'@
        } -Data (& $script:Module { $script:StubData })
        $folder = New-KeyFolder

        $run = Invoke-TestRegister -Parameter @{ Kind = 'Certificate'; OutputFolder = $folder }

        $run.Error | Should -BeLike '*were removed*'
        Test-Path -LiteralPath (Get-KeyPath -Parent $folder) | Should -BeFalse
        Test-Path -LiteralPath (Get-KeyPath -Parent $folder -Leaf 'notes.txt') | Should -BeTrue
    }

    It 'says which files could not be removed when one cannot, and that no app uses them' {
        Set-RegisterStub -Data @{ Fail = 'The application with name SPSSiteLifecycle already exists.' }
        Set-ModuleStub -Stub @{
            'Register-SPSLifecycleEntraApp' = @'
param($Plan, $CertificatePassword)
$null = New-Item -Path $Plan.Certificate.PfxPath -ItemType Directory
Set-Content -LiteralPath (Join-Path -Path $Plan.Certificate.PfxPath -ChildPath 'inner.txt') -Value 'x'
throw $script:StubData.Fail
'@
        } -Data (& $script:Module { $script:StubData })
        $folder = New-KeyFolder

        $run = Invoke-TestRegister -Parameter @{ Kind = 'Certificate'; OutputFolder = $folder }

        $run.Error | Should -BeLike "*could not be removed (delete them by hand, no app uses them): $(Get-KeyPath -Parent $folder)*"
    }

    It 'keeps the files, and says so, when the cmdlet gave nothing back after it wrote them' {
        Set-RegisterStub -Data @{ Record = $null }
        $folder = New-KeyFolder

        $run = Invoke-TestRegister -Parameter @{ Kind = 'Certificate'; OutputFolder = $folder }

        $run.Error | Should -BeLike '*gave nothing back*were kept*an app may exist that they belong to*'
        Test-Path -LiteralPath (Get-KeyPath -Parent $folder) | Should -BeTrue
    }

    It 'removes the folder that it made, and says that nothing came back, when the sign-in was cancelled before any file was written' {
        Set-RegisterStub -Data @{ Record = $null; WriteFiles = $false }
        $folder = New-KeyFolder

        $run = Invoke-TestRegister -Parameter @{ Kind = 'Certificate'; OutputFolder = $folder }

        $run.Error | Should -BeLike '*gave nothing back*'
        $run.Error | Should -Not -BeLike '*were kept*'
        Test-Path -LiteralPath (Join-Path -Path $folder -ChildPath 'SPSSiteLifecycle') | Should -BeFalse
    }

    It 'removes the folder that it made when the registration failed and wrote nothing, and keeps one that holds a file' {
        Set-RegisterStub -Data @{ Fail = 'A task was canceled.'; WriteFiles = $false }
        $folder = New-KeyFolder

        $null = Invoke-TestRegister -Parameter @{ Kind = 'Certificate'; OutputFolder = $folder }

        Test-Path -LiteralPath (Join-Path -Path $folder -ChildPath 'SPSSiteLifecycle') | Should -BeFalse
    }
}

Describe 'Register-SPSLifecycleApp: what it checks after the registration, which is no success unless the key is the key' {
    AfterEach {
        Clear-ModuleStub
    }

    It 'stops, and says what to do, when the certificate file cannot be read as a certificate' {
        Set-RegisterStub -Data @{ Info = $null }

        $run = Invoke-TestRegister -Parameter @{ Kind = 'Certificate'; OutputFolder = (New-KeyFolder) }

        $run.Error | Should -BeLike "The app 'SPSSiteLifecycle' was created (client ID $script:ClientId), but the certificate file '*' cannot be read as a certificate*Delete the app*"
        $null -eq $run.Result | Should -BeTrue
    }

    It 'stops when the key file cannot be opened with the password that was typed, or is not a key at all' {
        Set-RegisterStub -Data @{ Key = $null }

        $run = Invoke-TestRegister -Parameter @{ Kind = 'Certificate'; OutputFolder = (New-KeyFolder) }

        $run.Error | Should -BeLike "*was created (client ID $script:ClientId), but the key file '*' cannot be opened with the password that was typed, or is not a .pfx file*Delete the app*"
        $null -eq $run.Result | Should -BeTrue
    }

    It 'stops when the key file holds no private key, or the key of another certificate: <Name>' -ForEach @(
        @{ Name = 'no private key'; Key = @{ Thumbprint = '0123456789ABCDEF0123456789ABCDEF01234567'; HasPrivateKey = $false } }
        @{ Name = 'another certificate'; Key = @{ Thumbprint = ('F' * 40); HasPrivateKey = $true } }
    ) {
        Set-RegisterStub -Data @{ Key = [PSCustomObject]$Key }

        $run = Invoke-TestRegister -Parameter @{ Kind = 'Certificate'; OutputFolder = (New-KeyFolder) }

        $run.Error | Should -BeLike "*does not hold the private key of the certificate that the app got (thumbprint $script:Thumbprint)*Delete the app*"
        $null -eq $run.Result | Should -BeTrue
    }

    It 'does not say that the certificate is in the store when what was added is not the one that the app got' {
        Set-RegisterStub -Data @{ Windows = $true; StoreThumbprint = ('F' * 40) }

        $run = Invoke-TestRegister -Parameter @{ Kind = 'Certificate'; OutputFolder = (New-KeyFolder); UseCertificateStore = $true }

        $run.Result.StoredInCertificateStore | Should -BeFalse
        ($run.Warnings -join ' ') | Should -BeLike '*added to the CurrentUser store is not the one that the app got*'
    }
}

Describe 'Register-SPSLifecycleApp: the password' {
    AfterEach {
        Clear-ModuleStub
    }

    It 'is never shown, logged, thrown or returned: <Name>' -ForEach @(
        @{ Name = 'a registration that works'; Data = @{} }
        @{ Name = 'a name that is taken'; Data = @{ Fail = "The application with name SPSSiteLifecycle already exists. Password was $script:Password" } }
        @{ Name = 'a failure that nobody can tell'; Data = @{ Fail = 'A task was canceled.' } }
        @{ Name = 'a certificate that is not the one that the app got'; Data = @{ Info = [PSCustomObject]@{ Thumbprint = ('F' * 40); NotAfter = [System.DateTime]::UtcNow } } }
    ) {
        $secret = 'Correct-Horse-Battery-1'
        Set-RegisterStub -Data (@{ Password = $secret } + $Data)

        $run = Invoke-TestRegister -Parameter @{ Kind = 'Certificate'; OutputFolder = (New-KeyFolder) } -All

        $text = @($run.Stream) + @($run.Error) + @($run.Warnings) + @($run.Info) + @($run.Result | ConvertTo-Json -Depth 5 -Compress) + @($Error | ForEach-Object { "$_" })
        if ($Name -eq 'a name that is taken') {
            # What PnP.PowerShell says is told as it is, so the one case that proves nothing is the one where the message holds it.
            $text = @($text | Where-Object { $_ -notlike '*Password was*' })
        }

        ($text -join "`n") | Should -Not -BeLike "*$secret*"
    }

    It 'is given to the cmdlet as a SecureString, and to nothing else' {
        Set-RegisterStub

        $null = Invoke-TestRegister -Parameter @{ Kind = 'Certificate'; OutputFolder = (New-KeyFolder) }

        @(Get-StubLog | Where-Object { $_ -like 'register*' }) | Should -Be @('register Certificate contoso.onmicrosoft.com SPSSiteLifecycle password=True folder=True')
    }
}

Describe 'Register-SPSLifecycleApp: a run that is interrupted' {
    BeforeAll {
        # Ctrl+C raises a PipelineStoppedException, which a catch does not catch: only a finally runs. This runs the registration in a process of
        # its own, where the cmdlet has written the key with the mode that a file gets by default and then is interrupted (Mode inject), or waits to
        # be (Mode wait: it writes ready.txt first), and the key is restricted by the real function.
        function script:New-InterruptedRegisterScript {
            param([string]$Folder, [string]$Mode)

            $template = @'
$ErrorActionPreference = 'Stop'
$module = Import-Module -Name '@@MANIFEST@@' -Force -PassThru
& $module {
    param($folder, $mode)
    $script:Folder = $folder
    $script:Mode = $mode
    function script:Assert-SPSLifecyclePnPModule { }
    function script:Test-SPSLifecycleInputRedirected { $false }
    function script:Read-Host { param($Prompt) 'contoso' }
    function script:Read-SPSLifecycleCertificatePassword { $s = [System.Security.SecureString]::new(); foreach ($c in 'Correct-Horse-1'.ToCharArray()) { $s.AppendChar($c) }; $s }
    function script:Write-Warning { param([string]$Message) [System.IO.File]::AppendAllText((Join-Path -Path $script:Folder -ChildPath 'warnings.txt'), "$Message`n") }
    function script:Register-SPSLifecycleEntraApp {
        param($Plan, $CertificatePassword)
        Set-Content -LiteralPath $Plan.Certificate.PfxPath -Value 'THE KEY'
        [System.IO.File]::SetUnixFileMode($Plan.Certificate.PfxPath, [System.IO.UnixFileMode]'UserRead, UserWrite, GroupRead, OtherRead')
        if ($script:Mode -eq 'inject') { throw [System.Management.Automation.PipelineStoppedException]::new() }
        [System.IO.File]::WriteAllText((Join-Path -Path $script:Folder -ChildPath 'ready.txt'), 'ready')
        Microsoft.PowerShell.Utility\Start-Sleep -Seconds 120
    }
} '@@FOLDER@@' '@@MODE@@'
$null = Register-SPSLifecycleApp -TenantName contoso -Kind Certificate -OutputFolder '@@FOLDER@@/keys' -InformationAction SilentlyContinue
'@
            $file = Join-Path -Path $Folder -ChildPath 'run.ps1'
            [System.IO.File]::WriteAllText($file, $template.Replace('@@MANIFEST@@', $script:Manifest).Replace('@@FOLDER@@', $Folder).Replace('@@MODE@@', $Mode))
            $file
        }
    }

    It 'leaves the key that the cmdlet wrote restricted to the user, and says what may be left in the tenant' -Skip:($IsWindows) {
        $folder = Join-Path -Path $TestDrive -ChildPath ([System.Guid]::NewGuid().ToString('N'))
        $null = New-Item -Path $folder -ItemType Directory
        $file = New-InterruptedRegisterScript -Folder $folder -Mode 'inject'

        $null = & $script:Pwsh -NoProfile -File $file 2>&1

        $key = Join-Path -Path $folder -ChildPath 'keys/SPSSiteLifecycle/SPSSiteLifecycle.pfx'
        Test-Path -LiteralPath $key | Should -BeTrue
        [System.IO.File]::GetUnixFileMode($key) | Should -Be ([System.IO.UnixFileMode]::UserRead -bor [System.IO.UnixFileMode]::UserWrite)
        (Get-Content -LiteralPath (Join-Path -Path $folder -ChildPath 'warnings.txt') -Raw) | Should -BeLike "*The registration was interrupted. The app 'SPSSiteLifecycle' may have been created*Microsoft Entra admin center*were kept.*"
    }

    It 'does the same when the process receives the signal that Ctrl+C sends, while the cmdlet waits' -Skip:($IsWindows) {
        if (-not (Test-ChildHonorsSigint -Pwsh $script:Pwsh)) {
            Set-ItResult -Skipped -Because 'the signal of Ctrl+C does not reach a child process here: the tests were started in the background of a shell'
            return
        }

        $folder = Join-Path -Path $TestDrive -ChildPath ([System.Guid]::NewGuid().ToString('N'))
        $null = New-Item -Path $folder -ItemType Directory
        $file = New-InterruptedRegisterScript -Folder $folder -Mode 'wait'

        $info = [System.Diagnostics.ProcessStartInfo]::new($script:Pwsh)
        foreach ($argument in '-NoProfile', '-NonInteractive', '-File', $file) { $info.ArgumentList.Add($argument) }
        $info.UseShellExecute = $false
        $info.RedirectStandardInput = $true
        $info.RedirectStandardOutput = $true
        $info.RedirectStandardError = $true
        $process = [System.Diagnostics.Process]::Start($info)
        try {
            $null = $process.StandardOutput.ReadToEndAsync()
            $null = $process.StandardError.ReadToEndAsync()
            $ready = Join-Path -Path $folder -ChildPath 'ready.txt'
            $deadline = [System.DateTime]::UtcNow.AddSeconds(90)
            while (-not (Test-Path -LiteralPath $ready) -and [System.DateTime]::UtcNow -lt $deadline -and -not $process.HasExited) {
                Start-Sleep -Milliseconds 200
            }

            Test-Path -LiteralPath $ready | Should -BeTrue -Because 'the child process has to be in the registration before it is interrupted'
            $null = & /bin/kill -INT $process.Id
            $process.WaitForExit(60000) | Should -BeTrue -Because 'the interrupted process has to end'
        }
        finally {
            if (-not $process.HasExited) { $process.Kill($true) }
        }

        $key = Join-Path -Path $folder -ChildPath 'keys/SPSSiteLifecycle/SPSSiteLifecycle.pfx'
        [System.IO.File]::GetUnixFileMode($key) | Should -Be ([System.IO.UnixFileMode]::UserRead -bor [System.IO.UnixFileMode]::UserWrite)
        (Get-Content -LiteralPath (Join-Path -Path $folder -ChildPath 'warnings.txt') -Raw) | Should -BeLike '*The registration was interrupted*'
    }
}
