BeforeAll {
    $script:Manifest = Join-Path -Path $PSScriptRoot -ChildPath '../src/Modules/SPSSiteLifecycle.Common/SPSSiteLifecycle.Common.psd1'
    $script:Module = Import-Module -Name $script:Manifest -Force -PassThru
    $script:Now = [System.DateTime]::new(2026, 10, 30, 9, 15, 0, [System.DateTimeKind]::Utc)
    $script:ClientId = '4d3c2b1a-0f9e-4d8c-8b7a-6f5e4d3c2b1a'
    $script:Thumbprint = '0123456789abcdef0123456789abcdef01234567'
    $script:Pfx = 'Correct-Horse-Battery-1'

    . (Join-Path -Path $PSScriptRoot -ChildPath 'Helpers/ModuleStub.ps1')

    function script:New-Folder {
        param([string]$Name)

        $path = Join-Path -Path $TestDrive -ChildPath $Name
        $null = New-Item -Path $path -ItemType Directory -Force
        $path
    }

    # A link to a folder: a symbolic link, or a junction on Windows, which needs no right.
    function script:New-FolderLink {
        param([string]$Path, [string]$Target)

        $null = New-Item -Path $Path -ItemType $(if ($IsWindows) { 'Junction' } else { 'SymbolicLink' }) -Value $Target
    }

    function script:New-Secure {
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

Describe 'Resolve-SPSLifecyclePhysicalPath' {
    BeforeAll {
        function script:Resolve-Physical {
            param([string]$Path)

            & $script:Module { param($p) Resolve-SPSLifecyclePhysicalPath -Path $p } $Path
        }
    }

    It 'gives a path that holds no link as it is, whether it exists or not' {
        $folder = New-Folder -Name 'plain'

        Resolve-Physical -Path $folder | Should -BeExactly $folder
        Resolve-Physical -Path (Join-Path -Path $folder -ChildPath 'not/yet/there') | Should -BeExactly (Join-Path -Path $folder -ChildPath 'not/yet/there')
    }

    It 'gives the target of a link, and what is after the link' {
        $target = New-Folder -Name 'target-a'
        $null = New-Item -Path (Join-Path -Path $target -ChildPath 'inner') -ItemType Directory
        $link = Join-Path -Path $TestDrive -ChildPath 'link-a'
        New-FolderLink -Path $link -Target $target

        Resolve-Physical -Path $link | Should -BeExactly $target
        Resolve-Physical -Path (Join-Path -Path $link -ChildPath 'inner') | Should -BeExactly (Join-Path -Path $target -ChildPath 'inner')
    }

    It 'follows a link in the middle of a path, to a folder that is not there yet' {
        $target = New-Folder -Name 'target-b'
        $link = Join-Path -Path $TestDrive -ChildPath 'link-b'
        New-FolderLink -Path $link -Target $target

        Resolve-Physical -Path (Join-Path -Path (Join-Path -Path $link -ChildPath 'keys') -ChildPath 'SPSSiteLifecycle') | Should -BeExactly (Join-Path -Path (Join-Path -Path $target -ChildPath 'keys') -ChildPath 'SPSSiteLifecycle')
    }

    It 'follows a chain of links' {
        $target = New-Folder -Name 'target-c'
        $second = Join-Path -Path $TestDrive -ChildPath 'link-c2'
        $first = Join-Path -Path $TestDrive -ChildPath 'link-c1'
        New-FolderLink -Path $second -Target $target
        New-FolderLink -Path $first -Target $second

        Resolve-Physical -Path $first | Should -BeExactly $target
    }

    It 'reads a relative link from the folder that holds it' -Skip:($IsWindows) {
        $null = New-Folder -Name 'rel/target-d'
        $link = Join-Path -Path (New-Folder -Name 'rel') -ChildPath 'link-d'
        $null = New-Item -Path $link -ItemType SymbolicLink -Value 'target-d'

        Resolve-Physical -Path $link | Should -BeExactly (Join-Path -Path (Join-Path -Path $TestDrive -ChildPath 'rel') -ChildPath 'target-d')
    }

    It 'follows a link that leads nowhere to where it would lead' -Skip:($IsWindows) {
        $link = Join-Path -Path $TestDrive -ChildPath 'link-broken'
        $missing = Join-Path -Path $TestDrive -ChildPath 'missing-target'
        $null = New-Item -Path $link -ItemType SymbolicLink -Value $missing

        Resolve-Physical -Path $link | Should -BeExactly $missing
    }

    It 'refuses a loop of links, instead of going round for ever' -Skip:($IsWindows) {
        $first = Join-Path -Path $TestDrive -ChildPath 'loop-1'
        $second = Join-Path -Path $TestDrive -ChildPath 'loop-2'
        $null = New-Item -Path $first -ItemType SymbolicLink -Value $second
        $null = New-Item -Path $second -ItemType SymbolicLink -Value $first

        { Resolve-Physical -Path $first } | Should -Throw -ExpectedMessage '*too many links*'
    }

    It 'follows a long chain of links in one step: it does not count each of them as a place where the path was resolved again' -Skip:($IsWindows) {
        $real = New-Folder -Name 'chain-real'
        $next = $real
        foreach ($number in 34..0) {
            $link = Join-Path -Path $TestDrive -ChildPath "chain-$number"
            $null = New-Item -Path $link -ItemType SymbolicLink -Value $next
            $next = $link
        }

        Resolve-Physical -Path (Join-Path -Path $TestDrive -ChildPath 'chain-0') | Should -BeExactly $real
    }

    It 'goes through 32 places where the path has to be resolved again, and refuses the 33rd' -Skip:($IsWindows) {
        $real = New-Folder -Name 'hop-real'
        foreach ($hops in 32, 33) {
            $name = "hop$hops"
            foreach ($number in ($hops - 1)..0) {
                $target = if ($number -eq ($hops - 1)) { Join-Path -Path $real -ChildPath 's' } else { Join-Path -Path (Join-Path -Path $TestDrive -ChildPath "$name-$($number + 1)") -ChildPath 's' }
                $null = New-Item -Path (Join-Path -Path $TestDrive -ChildPath "$name-$number") -ItemType SymbolicLink -Value $target
            }
        }

        # Each link adds the folder that follows it to what is left of the path.
        Resolve-Physical -Path (Join-Path -Path $TestDrive -ChildPath 'hop32-0') | Should -BeExactly ($real + ('/s' * 32))
        { Resolve-Physical -Path (Join-Path -Path $TestDrive -ChildPath 'hop33-0') } | Should -Throw -ExpectedMessage '*too many links*'
    }
}

Describe 'Assert-SPSLifecycleOutsideRepository' {
    BeforeAll {
        function script:Assert-Outside {
            param([string]$Path, [string]$ToolRoot = '')

            & $script:Module { param($p, $t) Assert-SPSLifecycleOutsideRepository -Path $p -ToolRoot $t } $Path $ToolRoot
        }

        function script:New-Repository {
            param([string]$Name)

            $path = New-Folder -Name $Name
            $null = New-Item -Path (Join-Path -Path $path -ChildPath '.git') -ItemType Directory
            $path
        }
    }

    It 'lets a folder outside any repository and outside the tool through, whether it exists or not' {
        $tool = New-Folder -Name 'tool-ok'

        { Assert-Outside -Path (New-Folder -Name 'fine') -ToolRoot $tool } | Should -Not -Throw
        { Assert-Outside -Path (Join-Path -Path $TestDrive -ChildPath 'fine/not/there') -ToolRoot $tool } | Should -Not -Throw
    }

    It 'refuses a folder that is written inside a repository, at any depth' {
        $repository = New-Repository -Name 'repo-lex'

        { Assert-Outside -Path (Join-Path -Path $repository -ChildPath 'a/b/c') } | Should -Throw -ExpectedMessage '*inside a repository*'
    }

    It 'refuses a folder that is outside a repository by its name and inside it by where it leads: a link out of the repository to a folder of it' {
        $repository = New-Repository -Name 'repo-link'
        $inside = New-Folder -Name 'repo-link/sub'
        $link = Join-Path -Path $TestDrive -ChildPath 'innocent'
        New-FolderLink -Path $link -Target $inside

        { Assert-Outside -Path $link } | Should -Throw -ExpectedMessage '*inside a repository*the folder leads there*'
        { Assert-Outside -Path (Join-Path -Path $link -ChildPath 'keys/SPSSiteLifecycle') } | Should -Throw -ExpectedMessage '*inside a repository*the folder leads there*'
    }

    It 'refuses a folder that leads to the folder of the tool, though it is a repository or not' {
        $tool = New-Folder -Name 'tool-link'
        $link = Join-Path -Path $TestDrive -ChildPath 'tool-door'
        New-FolderLink -Path $link -Target (New-Folder -Name 'tool-link/src')

        { Assert-Outside -Path $link -ToolRoot $tool } | Should -Throw -ExpectedMessage '*inside the folder of the tool*the folder leads there*'
    }

    It 'refuses the folder of the tool itself, and what is in it, whatever the case of the letters' {
        $tool = New-Folder -Name 'Tool-Case-Of-Letters'
        $other = $tool.ToUpperInvariant()

        { Assert-Outside -Path $tool -ToolRoot $tool } | Should -Throw -ExpectedMessage '*inside the folder of the tool*'
        { Assert-Outside -Path $other -ToolRoot $tool } | Should -Throw -ExpectedMessage '*inside the folder of the tool*'
        { Assert-Outside -Path (Join-Path -Path $other -ChildPath 'keys') -ToolRoot $tool } | Should -Throw -ExpectedMessage '*inside the folder of the tool*'
    }

    It 'refuses the folder of the tool when the tool itself is reached through a link' {
        $tool = New-Folder -Name 'tool-real'
        $toolLink = Join-Path -Path $TestDrive -ChildPath 'tool-by-link'
        New-FolderLink -Path $toolLink -Target $tool

        { Assert-Outside -Path (Join-Path -Path $tool -ChildPath 'keys') -ToolRoot $toolLink } | Should -Throw -ExpectedMessage '*inside the folder of the tool*'
    }
}

Describe 'Assert-SPSLifecycleOwnerOnlyAccess' {
    It 'lets a folder that only its owner can read through, on macOS and Linux' -Skip:($IsWindows) {
        $folder = New-Folder -Name 'private'
        [System.IO.File]::SetUnixFileMode($folder, [System.IO.UnixFileMode]'UserRead, UserWrite, UserExecute')

        { & $script:Module { param($p) Assert-SPSLifecycleOwnerOnlyAccess -Path $p } $folder } | Should -Not -Throw
    }

    It 'refuses a folder that anyone else can read, write or enter, and one that its owner cannot use: <Mode>' -ForEach @(
        @{ Mode = 'UserRead, UserWrite, UserExecute, GroupRead, GroupExecute' }
        @{ Mode = 'UserRead, UserWrite, UserExecute, OtherExecute' }
        @{ Mode = 'UserRead, UserWrite, UserExecute, GroupWrite' }
        @{ Mode = 'UserRead, UserWrite, UserExecute, GroupRead, GroupWrite, GroupExecute, OtherRead, OtherWrite, OtherExecute' }
        @{ Mode = 'UserRead, UserExecute' }
        @{ Mode = 'UserRead, UserWrite' }
    ) {
        if ($IsWindows) {
            Set-ItResult -Skipped -Because 'Windows has no mode'
            return
        }

        $folder = New-Folder -Name "mode-$([System.Guid]::NewGuid().ToString('N'))"
        [System.IO.File]::SetUnixFileMode($folder, [System.IO.UnixFileMode]$Mode)

        { & $script:Module { param($p) Assert-SPSLifecycleOwnerOnlyAccess -Path $p } $folder } | Should -Throw -ExpectedMessage '*has the mode*only its owner can read (700)*Nothing was written in it*'
    }

    It 'refuses a folder that has the access list that it inherited, and lets one through that is for the account alone, on Windows' -Skip:(-not $IsWindows) {
        $inherited = New-Folder -Name 'inherited'
        { & $script:Module { param($p) Assert-SPSLifecycleOwnerOnlyAccess -Path $p } $inherited } | Should -Throw -ExpectedMessage '*more than the account that runs the tool*'

        $own = Join-Path -Path $TestDrive -ChildPath 'own'
        $null = & $script:Module { param($p) New-SPSLifecycleProtectedFolder -Path $p } $own
        { & $script:Module { param($p) Assert-SPSLifecycleOwnerOnlyAccess -Path $p } $own } | Should -Not -Throw
    }
}

Describe 'Assert-SPSLifecycleOwnerOnlyAccess, on Windows, when the list is protected but is not for the account alone' {
    It 'refuses a list that has another account, a refusal for the account, or nobody: <Name>' -Skip:(-not $IsWindows) -ForEach @(
        @{ Name = 'another account'; Own = 'Allow'; Others = $true }
        @{ Name = 'a refusal for the account'; Own = 'Deny'; Others = $false }
        @{ Name = 'nobody'; Own = ''; Others = $false }
    ) {
        $user = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
        $everyone = [System.Security.Principal.SecurityIdentifier]::new([System.Security.Principal.WellKnownSidType]::WorldSid, $null)
        $folder = New-Folder -Name "acl-$([System.Guid]::NewGuid().ToString('N'))"
        $inherit = [System.Security.AccessControl.InheritanceFlags]::ContainerInherit -bor [System.Security.AccessControl.InheritanceFlags]::ObjectInherit
        $rights = [System.Security.AccessControl.FileSystemRights]::FullControl
        $none = [System.Security.AccessControl.PropagationFlags]::None
        try {
            $acl = [System.Security.AccessControl.DirectorySecurity]::new()
            $acl.SetAccessRuleProtection($true, $false)
            if ($Own) {
                $acl.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new($user, $rights, $inherit, $none, [System.Security.AccessControl.AccessControlType]$Own))
            }

            if ($Others) {
                $acl.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new($everyone, $rights, $inherit, $none, [System.Security.AccessControl.AccessControlType]::Allow))
            }

            Set-Acl -LiteralPath $folder -AclObject $acl

            { & $script:Module { param($p) Assert-SPSLifecycleOwnerOnlyAccess -Path $p } $folder } | Should -Throw -ExpectedMessage '*more than the account that runs the tool*'
        }
        finally {
            $acl = [System.Security.AccessControl.DirectorySecurity]::new()
            $acl.SetAccessRuleProtection($true, $false)
            $acl.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new($user, $rights, $inherit, $none, [System.Security.AccessControl.AccessControlType]::Allow))
            Set-Acl -LiteralPath $folder -AclObject $acl
        }
    }
}

Describe 'New-SPSLifecycleProtectedFolder, when the folder is not as it must be' {
    AfterEach {
        Clear-ModuleStub
    }

    It 'removes the folder that it made, and stops with the reason, so that nothing is written in it' {
        $folder = Join-Path -Path $TestDrive -ChildPath 'refused-folder'
        Set-ModuleStub -Stub @{
            'Assert-SPSLifecycleOwnerOnlyAccess' = @'
param($Path)
throw "The folder '$Path' has the mode 755. Nothing was written in it."
'@
        }

        { & $script:Module { param($p) New-SPSLifecycleProtectedFolder -Path $p } $folder } | Should -Throw -ExpectedMessage '*has the mode 755*Nothing was written in it*'

        Test-Path -LiteralPath $folder | Should -BeFalse
    }
}

Describe 'Clear-SPSLifecycleKeyFolder' {
    BeforeAll {
        function script:Clear-Key {
            param([string]$Folder, [switch]$FolderOnly)

            & $script:Module { param($f, $o) Clear-SPSLifecycleKeyFolder -Folder $f -ApplicationName 'SPSSiteLifecycle' -FolderOnly:$o -Confirm:$false } $Folder $FolderOnly.IsPresent
        }
    }

    It 'removes the two files of the app and the folder that is then empty' {
        $folder = New-Folder -Name 'clear-1'
        Set-Content -LiteralPath (Join-Path -Path $folder -ChildPath 'SPSSiteLifecycle.pfx') -Value 'k'
        Set-Content -LiteralPath (Join-Path -Path $folder -ChildPath 'SPSSiteLifecycle.cer') -Value 'c'

        $result = Clear-Key -Folder $folder

        @($result.Removed) | Should -Be @((Join-Path -Path $folder -ChildPath 'SPSSiteLifecycle.pfx'), (Join-Path -Path $folder -ChildPath 'SPSSiteLifecycle.cer'))
        $result.FolderRemoved | Should -BeTrue
        Test-Path -LiteralPath $folder | Should -BeFalse
    }

    It 'removes nothing else, and keeps the folder when something else is in it, with no -Recurse' {
        $folder = New-Folder -Name 'clear-2'
        Set-Content -LiteralPath (Join-Path -Path $folder -ChildPath 'SPSSiteLifecycle.pfx') -Value 'k'
        Set-Content -LiteralPath (Join-Path -Path $folder -ChildPath 'other.txt') -Value 'o'
        $null = New-Item -Path (Join-Path -Path $folder -ChildPath 'sub') -ItemType Directory

        $result = Clear-Key -Folder $folder

        $result.FolderRemoved | Should -BeExactly $false
        Test-Path -LiteralPath (Join-Path -Path $folder -ChildPath 'other.txt') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path -Path $folder -ChildPath 'sub') | Should -BeTrue
        Test-Path -LiteralPath (Join-Path -Path $folder -ChildPath 'SPSSiteLifecycle.pfx') | Should -BeFalse
    }

    It 'does not follow a link of the name of a file, and says that it did not remove it' {
        $folder = New-Folder -Name 'clear-3'
        $secret = Join-Path -Path $TestDrive -ChildPath 'precious.txt'
        Set-Content -LiteralPath $secret -Value 'precious'
        $link = Join-Path -Path $folder -ChildPath 'SPSSiteLifecycle.pfx'
        if ($IsWindows) {
            $null = New-Item -Path $link -ItemType HardLink -Value $secret
        }
        else {
            $null = New-Item -Path $link -ItemType SymbolicLink -Value $secret
        }

        $result = Clear-Key -Folder $folder

        if (-not $IsWindows) {
            @($result.NotRemoved) | Should -Be @($link)
            Test-Path -LiteralPath $link | Should -BeTrue
        }

        Get-Content -LiteralPath $secret | Should -BeExactly 'precious'
    }

    It 'says that a folder of the name of a file is not removed' {
        $folder = New-Folder -Name 'clear-4'
        $null = New-Item -Path (Join-Path -Path $folder -ChildPath 'SPSSiteLifecycle.pfx') -ItemType Directory

        $result = Clear-Key -Folder $folder

        @($result.NotRemoved) | Should -Be @((Join-Path -Path $folder -ChildPath 'SPSSiteLifecycle.pfx'))
        Test-Path -LiteralPath (Join-Path -Path $folder -ChildPath 'SPSSiteLifecycle.pfx') | Should -BeTrue
    }

    It 'with -FolderOnly, removes an empty folder and nothing that is in a folder that is not' {
        $empty = New-Folder -Name 'clear-5'
        $full = New-Folder -Name 'clear-6'
        Set-Content -LiteralPath (Join-Path -Path $full -ChildPath 'SPSSiteLifecycle.pfx') -Value 'k'

        (Clear-Key -Folder $empty -FolderOnly).FolderRemoved | Should -BeTrue
        (Clear-Key -Folder $full -FolderOnly).FolderRemoved | Should -BeExactly $false

        Test-Path -LiteralPath $empty | Should -BeFalse
        Test-Path -LiteralPath (Join-Path -Path $full -ChildPath 'SPSSiteLifecycle.pfx') | Should -BeTrue
    }

    It 'does not throw, and removes nothing, for a folder that is not there or is a link' {
        { Clear-Key -Folder (Join-Path -Path $TestDrive -ChildPath 'never-made') } | Should -Not -Throw

        $target = New-Folder -Name 'clear-7-target'
        $link = Join-Path -Path $TestDrive -ChildPath 'clear-7-link'
        New-FolderLink -Path $link -Target $target
        (Clear-Key -Folder $link -FolderOnly).FolderRemoved | Should -BeExactly $false
        Test-Path -LiteralPath $target | Should -BeTrue
    }
}

Describe 'Read-SPSLifecycleKeyFile' {
    BeforeAll {
        function script:New-KeyFile {
            param([switch]$PublicOnly, [string]$Password = $script:Pfx)

            $folder = New-Folder -Name "keyfile-$([System.Guid]::NewGuid().ToString('N'))"
            $rsa = [System.Security.Cryptography.RSA]::Create(2048)
            $request = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new('CN=SPSSiteLifecycleTest', $rsa, [System.Security.Cryptography.HashAlgorithmName]::SHA256, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
            $certificate = $request.CreateSelfSigned([System.DateTimeOffset]::UtcNow.AddDays(-1), [System.DateTimeOffset]::UtcNow.AddDays(100))
            $path = Join-Path -Path $folder -ChildPath 'app.pfx'
            if ($PublicOnly) { [System.IO.File]::WriteAllBytes($path, $certificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)) }
            else { [System.IO.File]::WriteAllBytes($path, $certificate.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx, $Password)) }
            [PSCustomObject]@{ Path = $path; Certificate = $certificate }
        }

        function script:Read-Key {
            param([string]$Path, $Password)

            & $script:Module { param($p, $s) Read-SPSLifecycleKeyFile -Path $p -Password $s } $Path $Password
        }
    }

    It 'says what the file holds: the thumbprint of the certificate and the private key' {
        $made = New-KeyFile

        $key = Read-Key -Path $made.Path -Password (New-Secure -Text $script:Pfx)

        $key.Thumbprint | Should -BeExactly $made.Certificate.Thumbprint.ToUpperInvariant()
        $key.HasPrivateKey | Should -BeTrue
        @($key.PSObject.Properties.Name) | Should -Be @('Thumbprint', 'HasPrivateKey')
    }

    It 'says that a file that holds only the certificate has no private key' {
        $made = New-KeyFile -PublicOnly

        (Read-Key -Path $made.Path -Password (New-Secure -Text $script:Pfx)).HasPrivateKey | Should -BeFalse
    }

    It 'gives nothing, and does not throw, for a wrong password, a file that is not a key, and a file that is not there' {
        $made = New-KeyFile
        $garbage = Join-Path -Path (New-Folder -Name 'garbage-key') -ChildPath 'app.pfx'
        Set-Content -LiteralPath $garbage -Value 'not a key'

        $null -eq (Read-Key -Path $made.Path -Password (New-Secure -Text 'Another-Password-1')) | Should -BeTrue
        $null -eq (Read-Key -Path $garbage -Password (New-Secure -Text $script:Pfx)) | Should -BeTrue
        $null -eq (Read-Key -Path (Join-Path -Path $TestDrive -ChildPath 'missing.pfx') -Password (New-Secure -Text $script:Pfx)) | Should -BeTrue
    }

    It 'does not keep the file open' {
        $made = New-KeyFile

        $null = Read-Key -Path $made.Path -Password (New-Secure -Text $script:Pfx)

        { Remove-Item -LiteralPath $made.Path -Force -ErrorAction Stop } | Should -Not -Throw
    }
}

Describe 'Test-SPSLifecycleSecureStringEqual' {
    It 'tells whether two SecureStrings hold the same text: <Name>' -ForEach @(
        @{ Name = 'the same'; First = 'Correct-Horse-1'; Second = 'Correct-Horse-1'; Expected = $true }
        @{ Name = 'one letter apart'; First = 'Correct-Horse-1'; Second = 'Correct-Horse-2'; Expected = $false }
        @{ Name = 'the first letter apart'; First = 'Xorrect-Horse-1'; Second = 'Correct-Horse-1'; Expected = $false }
        @{ Name = 'a case apart'; First = 'correct-horse-1'; Second = 'Correct-Horse-1'; Expected = $false }
        @{ Name = 'a longer one'; First = 'Correct-Horse-1'; Second = 'Correct-Horse-1 '; Expected = $false }
        @{ Name = 'a shorter one'; First = 'Correct-Horse'; Second = 'Correct-Horse-1'; Expected = $false }
        @{ Name = 'both empty'; First = ''; Second = ''; Expected = $true }
        @{ Name = 'letters that are not ASCII'; First = "caf$([char]0x00E9)-123456"; Second = "caf$([char]0x00E9)-123456"; Expected = $true }
        @{ Name = 'a letter that looks like another'; First = "caf$([char]0x00E9)-123456"; Second = 'cafe-1234567'; Expected = $false }
    ) {
        & $script:Module { param($a, $b) Test-SPSLifecycleSecureStringEqual -First $a -Second $b } (New-Secure -Text $First) (New-Secure -Text $Second) | Should -Be $Expected
    }
}

Describe 'ConvertTo-SPSLifecycleSecretFreeText' {
    BeforeAll {
        function script:Remove-Secret {
            param([string]$Text, [string[]]$Secret = @())

            & $script:Module { param($t, $s) ConvertTo-SPSLifecycleSecretFreeText -Text $t -Secret $s } $Text $Secret
        }
    }

    It 'gives a text that holds nothing of the kind as it is, trimmed' {
        Remove-Secret -Text '  The application with name X already exists.  ' | Should -BeExactly 'The application with name X already exists.'
        Remove-Secret -Text 'AADSTS65001: The user or administrator has not consented. Trace ID: 0a1b2c3d-0000-4000-8000-000000000000' | Should -BeExactly 'AADSTS65001: The user or administrator has not consented. Trace ID: 0a1b2c3d-0000-4000-8000-000000000000'
        Remove-Secret -Text $null | Should -BeExactly ''
    }

    It 'takes out a key in a PEM block, whole, or cut off, and what is around it stays' {
        $key = "-----BEGIN PRIVATE KEY-----`nMIIEvQIBADANBgkqhkiG9w0BAQEFAASCBKcwggSjAgEAAoIBAQC7`n-----END PRIVATE KEY-----"

        Remove-Secret -Text "failed: $key then more" | Should -BeExactly 'failed: [removed] then more'
        Remove-Secret -Text "failed: -----BEGIN PRIVATE KEY-----`nMIIEvQIBADANBgkqhkiG" | Should -BeExactly 'failed: [removed]'
    }

    It 'takes out a long run of base64, which the whole certificate with its private key is, and leaves the short ones' {
        $blob = 'MIIKcQIBAzCCCjcGCSqGSIb3DQEHAaCCCigEggokMIIKIDCCBhcGCSqGSIb3DQEHBqCCBggwggYEAgEAMIIF/QYJKoZIhvcNAQcBMBwGCiqGSIb3DQEMAQMwDgQI' * 3

        Remove-Secret -Text "The upload failed: $blob==" | Should -BeExactly 'The upload failed: [removed]'
        Remove-Secret -Text 'The id is 0a1b2c3d4e5f60718293a4b5c6d7e8f9' | Should -BeExactly 'The id is 0a1b2c3d4e5f60718293a4b5c6d7e8f9'
    }

    It 'takes out each secret that it is given, wherever it is, and more than once' {
        Remove-Secret -Text 'Bad password Correct-Horse-1 for the file; Correct-Horse-1 again' -Secret @('Correct-Horse-1') | Should -BeExactly 'Bad password [removed] for the file; [removed] again'
    }

    It 'cuts a text when it is longer than 800 characters, and only then' {
        $exact = ('abcd ' * 159) + 'abcde'

        $exact.Length | Should -Be 800
        Remove-Secret -Text $exact | Should -BeExactly $exact
        Remove-Secret -Text ($exact + 'f') | Should -BeExactly ($exact + '...')
    }

    It 'cuts a text that is too long, after the rest was taken out' {
        $text = Remove-Secret -Text ('word ' * 400)

        $text.Length | Should -BeLessOrEqual 803
        $text | Should -BeLike '*...'
    }
}

Describe 'Register-SPSLifecycleEntraApp, as the last barrier' {
    BeforeAll {
        function script:New-AppPlan {
            param([string]$Kind = 'Certificate')

            $parameters = @{ TenantName = 'contoso'; ApplicationName = 'SPSSiteLifecycle'; Kind = $Kind; Now = $script:Now }
            if ($Kind -eq 'Certificate') { $parameters['Folder'] = '/keys/spslc/SPSSiteLifecycle' }
            & $script:Module { param($p) Get-SPSLifecycleAppPlan @p } $parameters
        }

        function script:Set-PnPStub {
            param([string]$Mode = 'ok')

            Set-ModuleStub -Stub @{
                'Assert-SPSLifecyclePnPModule'  = @'
$script:StubLog.Add('pnp check')
'@
                'Register-PnPEntraIDApp'        = @'
[CmdletBinding()]
param($ApplicationName, $Tenant, $OutPath, $ValidYears, $CertificatePassword, $GraphApplicationPermissions, $SharePointApplicationPermissions)
$script:StubLog.Add("register $Tenant | graph=$($GraphApplicationPermissions -join ',') | sharepoint=$($SharePointApplicationPermissions -join ',') | out=$OutPath | years=$ValidYears")
$script:StubData.Bound = $PSBoundParameters
switch ($script:StubData.Mode) {
    'noisy' {
        Write-Warning 'WARNING-WITH-SECRET MIIKcQIBAzCCCjcGCSqGSIb3DQEHAaCCCigEggokMIIKIDCCBhcGCSqGSIb3DQEHBqCCBggwggYEAgEAMIIF/QYJKoZIhvcNAQcBMBwGCiqGSIb3DQEMAQMwDgQI'
        Write-Verbose 'VERBOSE-WITH-SECRET'
        Write-Debug 'DEBUG-WITH-SECRET'
        Write-Information 'INFORMATION-WITH-SECRET' -InformationAction Continue
        [PSCustomObject]@{ 'AzureAppId/ClientId' = '4d3c2b1a-0f9e-4d8c-8b7a-6f5e4d3c2b1a'; 'Certificate Thumbprint' = '0123456789abcdef0123456789abcdef01234567'; Base64Encoded = 'THE-PFX' }
    }
    'fail' {
        throw "Upload failed for Correct-Horse-Battery-1 and MIIKcQIBAzCCCjcGCSqGSIb3DQEHAaCCCigEggokMIIKIDCCBhcGCSqGSIb3DQEHBqCCBggwggYEAgEAMIIF/QYJKoZIhvcNAQcBMBwGCiqGSIb3DQEMAQMwDgQI and -----BEGIN PRIVATE KEY-----`nabc`n-----END PRIVATE KEY-----"
    }
    default { [PSCustomObject]@{ 'AzureAppId/ClientId' = '4d3c2b1a-0f9e-4d8c-8b7a-6f5e4d3c2b1a'; 'Certificate Thumbprint' = '0123456789abcdef0123456789abcdef01234567' } }
}
'@
            } -Data @{ Mode = $Mode; Bound = $null }
        }

        function script:Invoke-Adapter {
            param($Plan, $Password = $null)

            & $script:Module { param($p, $s) Register-SPSLifecycleEntraApp -Plan $p -CertificatePassword $s } $Plan $Password
        }
    }

    AfterEach {
        Clear-ModuleStub
    }

    It 'refuses a plan that names one tenant and another domain, and registers nothing: the domain is what the cmdlet signs in to' {
        Set-PnPStub
        $plan = New-AppPlan
        $plan.TenantDomain = 'microsoft.onmicrosoft.com'

        { Invoke-Adapter -Plan $plan -Password (New-Secure -Text $script:Pfx) } | Should -Throw -ExpectedMessage "*not the plan of the tenant 'contoso'*microsoft.onmicrosoft.com*nothing was registered*"

        @(Get-StubLog | Where-Object { $_ -like 'register*' }) | Should -HaveCount 0
    }

    It 'refuses a plan that asks for other permissions than the ones of the kind, or for more: <Name>' -ForEach @(
        @{ Name = 'a permission added'; Edit = { param($p) $p.Permissions = @($p.Permissions) + [PSCustomObject]@{ Resource = 'Graph'; Name = 'Directory.ReadWrite.All'; Type = 'Application'; Kind = 'Certificate'; UsedBy = 'x'; Reason = 'x' } } }
        @{ Name = 'a permission removed'; Edit = { param($p) $p.Permissions = @($p.Permissions | Select-Object -First 1) } }
        @{ Name = 'another permission'; Edit = { param($p) $p.Permissions = @([PSCustomObject]@{ Resource = 'Graph'; Name = 'Directory.ReadWrite.All'; Type = 'Application'; Kind = 'Certificate'; UsedBy = 'x'; Reason = 'x' }, ($p.Permissions | Select-Object -Last 1)) } }
        @{ Name = 'a type changed'; Edit = { param($p) $p.Permissions[0].Type = 'Delegated' } }
    ) {
        Set-PnPStub
        $plan = New-AppPlan
        & $Edit $plan

        { Invoke-Adapter -Plan $plan -Password (New-Secure -Text $script:Pfx) } | Should -Throw -ExpectedMessage '*not the plan of the tenant*permissions*nothing was registered*'

        @(Get-StubLog | Where-Object { $_ -like 'register*' }) | Should -HaveCount 0
    }

    It 'gives the cmdlet what the tool would have planned, whatever else the plan says: the years, the folder, the domain and the permissions are rebuilt' {
        Set-PnPStub
        $plan = New-AppPlan

        $null = Invoke-Adapter -Plan $plan -Password (New-Secure -Text $script:Pfx)

        @(Get-StubLog | Where-Object { $_ -like 'register*' }) | Should -Be @('register contoso.onmicrosoft.com | graph=Group.ReadWrite.All | sharepoint=Sites.FullControl.All | out=/keys/spslc/SPSSiteLifecycle | years=2')
    }

    It 'refuses a number of years outside 1 to 30, and a kind that is not one, whoever made the plan' -ForEach @(
        @{ Name = '0 years'; Edit = { param($p) $p.Certificate.ValidYears = 0 } }
        @{ Name = '31 years'; Edit = { param($p) $p.Certificate.ValidYears = 31 } }
        @{ Name = 'a kind that is not one'; Edit = { param($p) $p.Kind = 'Everything' } }
    ) {
        Set-PnPStub
        $plan = New-AppPlan
        & $Edit $plan

        { Invoke-Adapter -Plan $plan -Password (New-Secure -Text $script:Pfx) } | Should -Throw

        @(Get-StubLog | Where-Object { $_ -like 'register*' }) | Should -HaveCount 0
    }

    It 'does not pass on what the cmdlet writes on its warning, verbose, debug and information streams, and does not give its secrets' {
        Set-PnPStub -Mode 'noisy'

        $stream = @(& $script:Module { param($p, $s) Register-SPSLifecycleEntraApp -Plan $p -CertificatePassword $s -Verbose -Debug:$false -InformationAction Continue *>&1 } (New-AppPlan) (New-Secure -Text $script:Pfx))
        $text = ($stream | ForEach-Object { "$_" | Out-String }) -join "`n"

        $text | Should -Not -BeLike '*WITH-SECRET*'
        $text | Should -Not -BeLike '*MIIKcQ*'
        $text | Should -Not -BeLike '*THE-PFX*'
        @($stream | Where-Object { $_ -is [System.Management.Automation.PSCustomObject] -and $null -ne $_.PSObject.Properties['ClientId'] }) | Should -HaveCount 1
    }

    It 'tells the message of a failure without a key, a run of base64 or the password, and leaves nothing of it in $Error' {
        Set-PnPStub -Mode 'fail'
        $Error.Clear()

        $message = ''
        try { $null = Invoke-Adapter -Plan (New-AppPlan) -Password (New-Secure -Text $script:Pfx) } catch { $message = $_.Exception.Message }

        $message | Should -BeLike 'Upload failed for [[]removed] and [[]removed] and [[]removed]'
        (($Error | ForEach-Object { "$($_.Exception.Message)" }) -join "`n") | Should -Not -BeLike '*Correct-Horse*'
        (($Error | ForEach-Object { "$($_.Exception.Message)" }) -join "`n") | Should -Not -BeLike '*MIIKcQ*'
        (($Error | ForEach-Object { "$($_.Exception.Message)" }) -join "`n") | Should -Not -BeLike '*PRIVATE KEY*'
    }
}
