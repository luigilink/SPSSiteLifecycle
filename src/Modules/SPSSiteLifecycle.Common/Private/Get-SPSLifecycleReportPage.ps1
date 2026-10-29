function Get-SPSLifecycleReportPage {
    <#
        .SYNOPSIS
        Builds the text of the Report page of the wiki from the table of the report columns.

        .DESCRIPTION
        The page is generated, so that a column cannot exist without its documentation.
        tools/Update-Documentation.ps1 writes it, and a test fails when the committed page differs
        from this text. The text uses LF line endings.

        .EXAMPLE
        Get-SPSLifecycleReportPage
    #>
    [CmdletBinding()]
    [OutputType([System.String])]
    param ()

    $kindText = @{
        Text        = 'text'
        Guid        = 'GUID'
        Boolean     = '`True` or `False`'
        WholeNumber = 'whole number'
        Date        = 'date, ISO 8601, UTC'
        Run         = 'time of the run, `20261028T163000Z`'
        Blank       = 'empty, filled in by a person'
    }

    $lines = [System.Collections.Generic.List[System.String]]::new()
    $lines.Add('# Report')
    $lines.Add('')
    $lines.Add('> This page is generated from the table of the report columns of the module. Do not edit it by hand: change the table, then run `tools/Update-Documentation.ps1`. A test fails when this page is out of date.')
    $lines.Add('')
    $lines.Add('The Scan phase writes one CSV file, `sites-<time of the run>.csv`, in `OutputFolder`. A person reviews it in a spreadsheet and fills in the `Decision` column. The Act phase reads it.')
    $lines.Add('')
    $lines.Add('## How the file is written')
    $lines.Add('')
    $lines.Add('- UTF-8 with a byte order mark, so that Excel reads the accents. Windows line endings.')
    $lines.Add('- The separator comes from the `CsvDelimiter` setting (a semicolon for French by default). The tool reads a comma, a semicolon or a tab.')
    $lines.Add('- Sizes are whole megabytes and dates are ISO 8601 in UTC, whatever the culture of the machine. The time of the run is written in the compact form `20261028T163000Z`, which is meant to survive a round trip through a spreadsheet unchanged.')
    $lines.Add('- A size that is unknown stays empty. It is never written as 0.')
    $lines.Add('- Texts that come from the tenant, the title of a site above all, are neutralized against formula injection ([CWE-1236](https://cwe.mitre.org/data/definitions/1236.html)): a text that starts with `=`, `+`, `-`, `@`, a tab or a carriage return gets a leading apostrophe, so that a spreadsheet shows it and does not run it.')
    $lines.Add('- There is no column for the owners of a site, because they are personal data.')
    $lines.Add('- `Decision` is always written empty. The tool never decides in the place of a person.')
    $lines.Add('- An existing file is never overwritten. It is a reviewed document.')
    $lines.Add('')
    $lines.Add('## Columns')
    $lines.Add('')
    $lines.Add('The Act phase reads four columns only: `Url`, `SiteId`, `GeneratedOn` and `Decision`. Everything else is read again from its source or live, so what a spreadsheet changes (dates, `VRAI` and `FAUX`, decimal commas) cannot alter an action.')
    $lines.Add('')
    $lines.Add('| # | Column | Kind | Read by Act | Meaning |')
    $lines.Add('|---|--------|------|-------------|---------|')
    $position = 0
    foreach ($column in @(Get-SPSLifecycleReportColumn)) {
        $position++
        $read = if ($column.ReadByAct) { 'yes' } else { 'no' }
        $lines.Add("| $position | ``$($column.Name)`` | $($kindText[$column.Kind]) | $read | $($column.Description) |")
    }

    $lines.Add('')

    $lines -join "`n"
}
