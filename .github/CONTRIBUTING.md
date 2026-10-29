# SPSSiteLifecycle - Contributing

Thanks for your interest in improving SPSSiteLifecycle! Contributions of all kinds are welcome:
bug reports, feature requests, documentation, and pull requests.

## Before you start

- Search the [existing issues](https://github.com/luigilink/SPSSiteLifecycle/issues) to avoid duplicates.
- Read the [wiki](https://github.com/luigilink/SPSSiteLifecycle/wiki) for usage and configuration.

## Reporting bugs and requesting features

Use the [issue templates](https://github.com/luigilink/SPSSiteLifecycle/issues/new/choose) (bug report,
feature request, documentation request, improvement request) and fill in as much detail as possible.
Do not paste real tenant data (tenant names, site URLs, owner names, client IDs, usage reports):
replace it with made-up values.

## Pull requests

1. Fork the repository and create a topic branch from `main`.
2. Keep changes focused and commits atomic; reference the issue being resolved (e.g. `Closes #123`).
3. Add or update the relevant Pester tests under `tests/` and make sure they pass locally:

   ```powershell
   Invoke-Pester -Path .\tests
   Invoke-ScriptAnalyzer -Path .\src -Recurse -Settings .\PSScriptAnalyzerSettings.psd1
   ```

4. Add an entry under **Unreleased** in `CHANGELOG.md` describing what changed and how it affects users.
5. Update the wiki pages under `wiki/` when behaviour, parameters, or configuration change.
6. Open the pull request and complete the checklist in the PR template.

## Coding conventions

- Target PowerShell 7.4+ (required by PnP.PowerShell 3.x) and follow the existing SPS* toolkit style.
- Shared logic lives in the `SPSSiteLifecycle.Common` module (one function per file under `Public/` or `Private/`, named `<Verb>-SPSLifecycle<Noun>`); the entry script `src/SPSSiteLifecycle.ps1` orchestrates the run.
- Only the adapter functions under `Private/Adapters/` call PnP.PowerShell or Microsoft Graph: a test enforces it.
- The `ModuleVersion` in `SPSSiteLifecycle.Common.psd1` is the single source of truth for the version.
- The Configuration and Verdicts wiki pages are generated: run `tools/Update-Documentation.ps1` after changing the settings schema or the verdict catalog.
- PowerShell files are saved as UTF-8 with a BOM and CRLF line endings (see `.editorconfig` and `.gitattributes`).
- The safeguards of the tool (report only by default, double confirmation, `MaxActions`, live re-check
  before every action, protected sites) are not optional: do not weaken them without discussing it first.
- Tests run without a tenant: calls to PnP.PowerShell are mocked, and the fixtures contain made-up data only.
- Never commit customer or tenant data: tenant names, site URLs, client IDs, e-mail addresses, site lists,
  usage reports, inventories or logs. The `.gitignore` blocks `*.csv` outside `tests/` for that reason.
