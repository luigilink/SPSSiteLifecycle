BeforeAll {
    $manifest = Join-Path -Path $PSScriptRoot -ChildPath '../src/Modules/SPSSiteLifecycle.Common/SPSSiteLifecycle.Common.psd1'
    $script:Module = Import-Module -Name $manifest -Force -PassThru
}

Describe 'ConvertTo-SPSLifecycleColumnKey' {
    It 'gives <Name> the key <Expected>' -ForEach @(
        @{ Name = 'SiteId'; Expected = 'siteid' }
        @{ Name = 'Site ID'; Expected = 'siteid' }
        @{ Name = 'Site_Id'; Expected = 'siteid' }
        @{ Name = 'SITE-ID'; Expected = 'siteid' }
        @{ Name = "Site$([char]0xAD)Id"; Expected = 'siteid' }
        @{ Name = "Site$([char]0x200B)Id"; Expected = 'siteid' }
        @{ Name = "Site$([char]0xA0)Id"; Expected = 'siteid' }
        @{ Name = 'ＳｉｔｅＩｄ'; Expected = 'siteid' }
        @{ Name = 'Locked On'; Expected = 'lockedon' }
        @{ Name = 'Équipe'; Expected = 'équipe' }
        @{ Name = '日本'; Expected = '日本' }
        @{ Name = ''; Expected = '' }
        @{ Name = '---'; Expected = '' }
    ) {
        (& $script:Module { param($n) ConvertTo-SPSLifecycleColumnKey -Name $n } $Name) | Should -BeExactly $Expected
    }

    It 'gives two different names two different keys' {
        (& $script:Module { ConvertTo-SPSLifecycleColumnKey -Name 'Site Id' }) | Should -Not -BeExactly (& $script:Module { ConvertTo-SPSLifecycleColumnKey -Name 'Site Url' })
    }

    It 'does not depend on the culture: <Culture>' -ForEach @(
        @{ Culture = 'tr-TR' }
        @{ Culture = 'fr-FR' }
        @{ Culture = 'de-DE' }
    ) {
        $previous = [System.Globalization.CultureInfo]::CurrentCulture
        try {
            [System.Globalization.CultureInfo]::CurrentCulture = [System.Globalization.CultureInfo]::GetCultureInfo($Culture)

            (& $script:Module { ConvertTo-SPSLifecycleColumnKey -Name 'SITE ID' }) | Should -BeExactly 'siteid'
        }
        finally {
            [System.Globalization.CultureInfo]::CurrentCulture = $previous
        }
    }
}

Describe 'Assert-SPSLifecycleCsvHeader' {
    BeforeAll {
        function script:Assert-TestHeader {
            param([string[]]$Name, [string[]]$Required = @(), [string[]]$Optional = @())
            & $script:Module { param($n, $r, $o) Assert-SPSLifecycleCsvHeader -Name $n -RequiredColumn $r -OptionalColumn $o -Source 'test.csv' } $Name $Required $Optional
        }
    }

    It 'accepts a header that has every required column, whatever the case and the spaces around the names' {
        { Assert-TestHeader -Name ' URL ', 'siteid', 'LockedOn' -Required 'Url', 'SiteId', 'LockedOn' } | Should -Not -Throw
    }

    It 'accepts a header without an optional column, and with columns that it does not know' {
        { Assert-TestHeader -Name 'Url', 'Note', 'Owner Display Name' -Required 'Url' -Optional 'SiteId' } | Should -Not -Throw
    }

    It 'accepts empty names, as a spreadsheet writes after the last column' {
        { Assert-TestHeader -Name 'Url', '', '  ' -Required 'Url' } | Should -Not -Throw
    }

    It 'stops on a column that appears twice, whatever its case' {
        { Assert-TestHeader -Name 'Url', 'SiteId', 'url' -Required 'Url' } | Should -Throw -ExpectedMessage "*more than once in 'test.csv'*url*"
    }

    It 'stops on a required column that is missing, and lists the columns that are there, with their hidden characters shown' {
        { Assert-TestHeader -Name 'Url', "Note$([char]0xAD)s" -Required 'Url', 'SiteId' } | Should -Throw -ExpectedMessage '*not found*SiteId*Columns present: Url, Note\u00ADs*'
    }

    It 'says that a column looks like the required one that is missing, rather than that the required one is missing' {
        { Assert-TestHeader -Name 'Url', "Site$([char]0xAD)Id" -Required 'Url', 'SiteId' } | Should -Throw -ExpectedMessage "*Site\u00ADId*looks like 'SiteId'*"
    }

    It 'says that the file is empty when there is no name' {
        { Assert-TestHeader -Name @() -Required 'Url' } | Should -Throw -ExpectedMessage '*the file is empty*'
    }

    It 'stops on a lookalike of an optional column: <Header>' -ForEach @(
        @{ Header = 'Site ID' }
        @{ Header = 'Site_Id' }
        @{ Header = "Site$([char]0xAD)Id" }
        @{ Header = "Site$([char]0x200B)Id" }
    ) {
        { Assert-TestHeader -Name 'Url', $Header -Required 'Url' -Optional 'SiteId' } | Should -Throw -ExpectedMessage "*test.csv*looks like 'SiteId'*Rename*"
    }

    It 'stops on a lookalike of a required column that is also there, because it is ambiguous' {
        { Assert-TestHeader -Name 'Url', 'U r l' -Required 'Url' } | Should -Throw -ExpectedMessage "*looks like 'Url'*"
    }

    It 'says that a column looks like a known one even when the known one is also there, not that a column is repeated' {
        { Assert-TestHeader -Name 'Url', 'SiteId', "Site$([char]0xAD)Id" -Required 'Url' -Optional 'SiteId' } | Should -Throw -ExpectedMessage "*looks like 'SiteId'*"
    }

    It 'shows the hidden character of the lookalike' {
        { Assert-TestHeader -Name 'Url', "Site$([char]0xAD)Id" -Required 'Url' -Optional 'SiteId' } | Should -Throw -ExpectedMessage '*Site\u00ADId*'
    }
}

Describe 'Test-SPSLifecycleWebAddress' {
    It 'accepts <Text>' -ForEach @(
        @{ Text = 'https://contoso.sharepoint.com/sites/a' }
        @{ Text = 'HTTP://CONTOSO.sharepoint.com:443/Sites/HR/' }
        @{ Text = 'https://contoso.sharepoint.com' }
        @{ Text = 'https://contoso.sharepoint.com/sites/%C3%A9quipe' }
        @{ Text = 'https://contoso.sharepoint.com/sites/équipe' }
        @{ Text = 'https://contoso.sharepoint.com/sites/a%20b' }
        @{ Text = 'https://contoso.sharepoint.com/sites/a,b' }
    ) {
        (& $script:Module { param($t) Test-SPSLifecycleWebAddress -Text $t } $Text) | Should -BeTrue
    }

    It 'refuses <Name>' -ForEach @(
        @{ Name = 'an empty text'; Text = '' }
        @{ Name = 'a path'; Text = 'sites/a' }
        @{ Name = 'a path from the root'; Text = '/sites/a' }
        @{ Name = 'an address without a scheme'; Text = '//contoso.sharepoint.com/sites/a' }
        @{ Name = 'another scheme'; Text = 'ftp://contoso.sharepoint.com/sites/a' }
        @{ Name = 'a file address'; Text = 'file:///c:/sites/a' }
        @{ Name = 'a script'; Text = 'javascript:alert(1)' }
        @{ Name = 'an address with no host'; Text = 'https://' }
        @{ Name = 'an address with no host and a path'; Text = 'http:///sites/a' }
        @{ Name = 'an address with a space'; Text = 'https://contoso.sharepoint.com/sites/a b' }
        @{ Name = 'a text with a tab'; Text = "https://contoso.sharepoint.com/sites/a`tb" }
        @{ Name = 'a text on two lines'; Text = "https://contoso.sharepoint.com/sites/a`r`nhttps://contoso.sharepoint.com/sites/b" }
        @{ Name = 'a zero-width space'; Text = [string][char]0x200B }
        @{ Name = 'an address with a zero-width space'; Text = "https://contoso.sharepoint.com/sites/a$([char]0x200B)" }
        @{ Name = 'an address with a soft hyphen'; Text = "https://contoso.sharepoint.com/sites/a$([char]0xAD)b" }
        @{ Name = 'an address with a no-break space'; Text = "https://contoso.sharepoint.com/sites/a$([char]0xA0)b" }
        @{ Name = 'an address that starts with a space'; Text = ' https://contoso.sharepoint.com/sites/a' }
        @{ Name = 'an address with a byte order mark'; Text = "$([char]0xFEFF)https://contoso.sharepoint.com/sites/a" }
    ) {
        (& $script:Module { param($t) Test-SPSLifecycleWebAddress -Text $t } $Text) | Should -BeFalse
    }

    It 'refuses a null' {
        (& $script:Module { Test-SPSLifecycleWebAddress -Text $null }) | Should -BeFalse
    }
}
