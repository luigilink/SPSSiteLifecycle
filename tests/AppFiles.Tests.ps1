BeforeAll {
    $script:Manifest = Join-Path -Path $PSScriptRoot -ChildPath '../src/Modules/SPSSiteLifecycle.Common/SPSSiteLifecycle.Common.psd1'
    $script:Module = Import-Module -Name $script:Manifest -Force -PassThru
    $script:Repository = (Resolve-Path -LiteralPath (Join-Path -Path $PSScriptRoot -ChildPath '..')).ProviderPath

    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers/ModuleStub.ps1')

    function script:New-TestCertificate {
        param([string]$Folder, [string]$Name = 'SPSSiteLifecycle')

        $rsa = [System.Security.Cryptography.RSA]::Create(2048)
        $request = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new("CN=$Name", $rsa, [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
        $certificate = $request.CreateSelfSigned([System.DateTimeOffset]::UtcNow.AddDays(-1), [System.DateTimeOffset]::UtcNow.AddYears(2))
        $cer = Join-Path -Path $Folder -ChildPath "$Name.cer"
        [System.IO.File]::WriteAllBytes($cer, $certificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert))
        [PSCustomObject]@{ Certificate = $certificate; Cer = $cer }
    }

    function script:New-Folder {
        param([string]$Name)

        $path = Join-Path -Path $TestDrive -ChildPath $Name
        $null = New-Item -Path $path -ItemType Directory -Force
        $path
    }

    Install-Tripwire
}

AfterAll {
    Remove-Tripwire
}

Describe 'New-SPSLifecycleProtectedFolder' {
    It 'creates a folder that only the user can read, before anything is written in it' -Skip:($IsWindows) {
        $path = Join-Path -Path $TestDrive -ChildPath 'protected/inner'

        $created = & $script:Module { param($p) New-SPSLifecycleProtectedFolder -Path $p } $path

        $created | Should -BeTrue
        [System.IO.File]::GetUnixFileMode($path) | Should -Be ([System.IO.UnixFileMode]::UserRead -bor [System.IO.UnixFileMode]::UserWrite -bor [System.IO.UnixFileMode]::UserExecute)
    }

    It 'leaves a folder that exists as it is: it is the choice of the user' -Skip:($IsWindows) {
        $path = New-Folder -Name 'chosen'
        [System.IO.File]::SetUnixFileMode($path, [System.IO.UnixFileMode]'UserRead, UserWrite, UserExecute, GroupRead, GroupExecute')

        $created = & $script:Module { param($p) New-SPSLifecycleProtectedFolder -Path $p } $path

        $created | Should -BeFalse
        [System.IO.File]::GetUnixFileMode($path) | Should -Be ([System.IO.UnixFileMode]'UserRead, UserWrite, UserExecute, GroupRead, GroupExecute')
    }

    It 'restricts a folder that it creates to the user on Windows, and what is created in it' -Skip:(-not $IsWindows) {
        $path = Join-Path -Path $TestDrive -ChildPath 'protected'

        $null = & $script:Module { param($p) New-SPSLifecycleProtectedFolder -Path $p } $path

        $acl = Get-Acl -LiteralPath $path
        $acl.AreAccessRulesProtected | Should -BeTrue
        @($acl.Access) | Should -HaveCount 1
        $acl.Access[0].IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value | Should -BeExactly ([System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value)
        $acl.Access[0].FileSystemRights.ToString() | Should -BeExactly 'FullControl'

        $inner = Join-Path -Path $path -ChildPath 'inner.pfx'
        Set-Content -LiteralPath $inner -Value 'x'
        @((Get-Acl -LiteralPath $inner).Access | ForEach-Object { $_.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value } | Select-Object -Unique) | Should -Be @([System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value)
    }

    It 'refuses a file, and creates nothing with -WhatIf' {
        $file = Join-Path -Path $TestDrive -ChildPath 'afile'
        Set-Content -LiteralPath $file -Value 'x'
        { & $script:Module { param($p) New-SPSLifecycleProtectedFolder -Path $p } $file } | Should -Throw -ExpectedMessage '*is a file*'

        $path = Join-Path -Path $TestDrive -ChildPath 'whatif'
        $created = & $script:Module { param($p) New-SPSLifecycleProtectedFolder -Path $p -WhatIf } $path
        $created | Should -BeFalse
        Test-Path -LiteralPath $path | Should -BeFalse
    }
}

Describe 'Protect-SPSLifecyclePrivateKey' {
    It 'restricts the key to the user, whatever it was, and says so' -Skip:($IsWindows) {
        $folder = New-Folder -Name 'keys'
        $key = Join-Path -Path $folder -ChildPath 'SPSSiteLifecycle.pfx'
        Set-Content -LiteralPath $key -Value 'x'
        [System.IO.File]::SetUnixFileMode($key, [System.IO.UnixFileMode]'UserRead, UserWrite, GroupRead, OtherRead')

        $result = & $script:Module { param($p) Protect-SPSLifecyclePrivateKey -Path $p } $key

        $result | Should -BeTrue
        [System.IO.File]::GetUnixFileMode($key) | Should -Be ([System.IO.UnixFileMode]::UserRead -bor [System.IO.UnixFileMode]::UserWrite)
    }

    It 'restricts the key to the user on Windows' -Skip:(-not $IsWindows) {
        $folder = New-Folder -Name 'keys'
        $key = Join-Path -Path $folder -ChildPath 'SPSSiteLifecycle.pfx'
        Set-Content -LiteralPath $key -Value 'x'

        $result = & $script:Module { param($p) Protect-SPSLifecyclePrivateKey -Path $p } $key

        $result | Should -BeTrue
        $acl = Get-Acl -LiteralPath $key
        $acl.AreAccessRulesProtected | Should -BeTrue
        @($acl.Access) | Should -HaveCount 1
        $acl.Access[0].IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value | Should -BeExactly ([System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value)
        $acl.Access[0].AccessControlType.ToString() | Should -BeExactly 'Allow'
    }

    It 'gives nothing to protect when there is no file, and does not throw: <Case>' -ForEach @(
        @{ Case = 'a file that is not there' }
        @{ Case = 'a folder' }
    ) {
        $path = if ($Case -eq 'a folder') { New-Folder -Name 'afolder' } else { Join-Path -Path $TestDrive -ChildPath 'nothing.pfx' }

        & $script:Module { param($p) Protect-SPSLifecyclePrivateKey -Path $p } $path | Should -BeFalse
    }

    It 'warns, and does not throw, when the key cannot be restricted: it runs in a finally' -Skip:($IsWindows) {
        $folder = New-Folder -Name 'keys2'
        $key = Join-Path -Path $folder -ChildPath 'SPSSiteLifecycle.pfx'
        Set-Content -LiteralPath $key -Value 'x'
        Set-ModuleStub -Stub @{ 'Test-SPSLifecycleWindowsPlatform' = '$true' }
        try {
            $outcome = & $script:Module {
                param($p)
                $warnings = $null
                $protected = Protect-SPSLifecyclePrivateKey -Path $p -WarningAction SilentlyContinue -WarningVariable warnings
                [PSCustomObject]@{ Protected = $protected; Warnings = @($warnings) }
            } $key
        }
        finally {
            Clear-ModuleStub
        }

        $outcome.Protected | Should -BeFalse
        ($outcome.Warnings -join ' ') | Should -BeLike '*could not be restricted to your account*Restrict them by hand.*'
    }
}

Describe 'Read-SPSLifecycleCertificateInfo' {
    It 'reads the thumbprint and the end date of the public file, and nothing that is secret' {
        $folder = New-Folder -Name 'certs'
        $made = New-TestCertificate -Folder $folder

        $info = & $script:Module { param($p) Read-SPSLifecycleCertificateInfo -Path $p } $made.Cer

        $info.Thumbprint | Should -BeExactly $made.Certificate.Thumbprint.ToUpperInvariant()
        $info.Thumbprint | Should -MatchExactly '\A[0-9A-F]{40}\z'
        $info.NotAfter | Should -BeOfType [System.DateTime]
        $info.NotAfter.Kind | Should -Be ([System.DateTimeKind]::Utc)
        ([System.Math]::Abs(($info.NotAfter - $made.Certificate.NotAfter.ToUniversalTime()).TotalSeconds)) | Should -BeLessThan 1
        @($info.PSObject.Properties.Name) | Should -Be @('Thumbprint', 'NotAfter')
    }

    It 'gives nothing when the file is not a certificate, not there, or a folder' {
        $folder = New-Folder -Name 'certs2'
        $garbage = Join-Path -Path $folder -ChildPath 'garbage.cer'
        Set-Content -LiteralPath $garbage -Value 'this is not a certificate'

        foreach ($path in $garbage, (Join-Path -Path $folder -ChildPath 'missing.cer'), $folder) {
            $null -eq (& $script:Module { param($p) Read-SPSLifecycleCertificateInfo -Path $p } $path) | Should -BeTrue
        }
    }
}

Describe 'Add-SPSLifecycleCertificateToStore' {
    It 'is for Windows only, and says that macOS and Linux use the file' -Skip:($IsWindows) {
        $secure = [System.Security.SecureString]::new()
        { & $script:Module { param($s) Add-SPSLifecycleCertificateToStore -Path '/nowhere.pfx' -Password $s } $secure } | Should -Throw -ExpectedMessage '*Windows only*.pfx*'
    }

    It 'adds the certificate with its key to the CurrentUser store, and gives its thumbprint' -Skip:(-not $IsWindows) {
        $folder = New-Folder -Name 'store'
        $rsa = [System.Security.Cryptography.RSA]::Create(2048)
        $request = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new('CN=SPSSiteLifecycleTest', $rsa, [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
        $certificate = $request.CreateSelfSigned([System.DateTimeOffset]::UtcNow.AddDays(-1), [System.DateTimeOffset]::UtcNow.AddDays(2))
        $pfx = Join-Path -Path $folder -ChildPath 'SPSSiteLifecycleTest.pfx'
        [System.IO.File]::WriteAllBytes($pfx, $certificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx, 'Correct-Horse-1'))
        $password = [System.Security.SecureString]::new()
        foreach ($character in 'Correct-Horse-1'.ToCharArray()) { $password.AppendChar($character) }

        $thumbprint = $null
        try {
            $thumbprint = & $script:Module { param($p, $s) Add-SPSLifecycleCertificateToStore -Path $p -Password $s } $pfx $password

            $thumbprint | Should -BeExactly $certificate.Thumbprint.ToUpperInvariant()
            $stored = Get-Item -LiteralPath "Cert:\CurrentUser\My\$thumbprint"
            $stored.HasPrivateKey | Should -BeTrue
        }
        finally {
            if ($thumbprint) { Remove-Item -LiteralPath "Cert:\CurrentUser\My\$thumbprint" -ErrorAction SilentlyContinue }
        }
    }
}

Describe 'Set-SPSLifecycleOwnerOnlyAccess' {
    It 'is for Windows only' -Skip:($IsWindows) {
        { & $script:Module { Set-SPSLifecycleOwnerOnlyAccess -Path '/nowhere' } } | Should -Throw -ExpectedMessage '*Windows only*'
    }
}

Describe 'The .gitignore of the repository' {
    It 'keeps keys and certificates out of a commit: <Pattern>' -ForEach @(
        @{ Pattern = '*.pfx' }
        @{ Pattern = '*.cer' }
        @{ Pattern = '*.pem' }
        @{ Pattern = '*.key' }
        @{ Pattern = '*.p12' }
    ) {
        $lines = @(Get-Content -LiteralPath (Join-Path -Path $script:Repository -ChildPath '.gitignore') | ForEach-Object { $_.Trim() })

        $lines | Should -Contain $Pattern
    }
}
