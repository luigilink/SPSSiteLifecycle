# Release process

SPSSiteLifecycle follows [Semantic Versioning](https://semver.org/) and a tag-driven release flow handled by GitHub Actions. Versions below 1.0.0 are published as pre-releases (see [Design decisions](Design-Decisions), D1).

## Versioning

- **MAJOR**: breaking changes to the settings file, the CSV contract, the verdicts or the output format. 1.0.0 comes only after a real run, limited to one action, has been validated on a production tenant.
- **MINOR**: new capabilities, backward compatible. While the major version is 0, a minor bump may also carry a breaking change, and it is called out in the change log.
- **PATCH**: bug fixes and documentation.

The single source of truth for the version is `ModuleVersion` in `src/Modules/SPSSiteLifecycle.Common/SPSSiteLifecycle.Common.psd1`. While nothing is published, it stays at `0.0.0`; it changes only on a release branch.

## Nothing is frozen during development

- `main` never advertises a version that has not been published.
- `CHANGELOG.md` accumulates entries under a single `## [Unreleased]` heading. Add a bullet for every pull request, under `### Added`, `### Changed`, `### Fixed`, `### Removed` or `### Documentation`.
- `RELEASE-NOTES.md` holds the notes of the next release only. It is used as is as the body of the GitHub release, so it never accumulates past releases: their history lives in `CHANGELOG.md`.

## Steps

1. Create a release branch from an up-to-date `main`: `git checkout -b release/x.y.z`.
2. Set `ModuleVersion` to `x.y.z`.
3. In `CHANGELOG.md`, rename `## [Unreleased]` to `## [x.y.z] - YYYY-MM-DD` and add a new empty `## [Unreleased]` above it.
4. Replace the content of `RELEASE-NOTES.md` with the notes of this version only.
5. Run the tests and the analyzer locally:

   ```powershell
   Invoke-Pester -Path .\tests
   Invoke-ScriptAnalyzer -Path .\src, .\tools -Recurse -Settings .\PSScriptAnalyzerSettings.psd1
   ```

6. Commit, open a pull request to `main`, and merge it when CI is green.
7. Tag the merge commit and push the tag:

   ```powershell
   git tag vx.y.z
   git push origin vx.y.z
   ```

## What the automation does

- **Pester workflow** (`pester.yml`): on every pull request to `main`, runs the Pester suite on Windows and Linux with PowerShell 7, and PSScriptAnalyzer on `src` and `tools`.
- **Release workflow** (`release.yml`): on a `v*` tag, zips the contents of `src/` (the archive extracts straight to `config/`, `Modules/` and the script) and publishes a GitHub release with `RELEASE-NOTES.md` as its body. A tag that starts with `v0.` is published as a pre-release.
- **Wiki workflow** (`wiki.yml`): on a push to `main` that touches `wiki/**`, copies the `wiki/` folder to the GitHub wiki.

## Generated pages

The Configuration and Verdicts pages are generated from the settings schema and the verdict catalog in the module. After changing either, run `tools/Update-Documentation.ps1` and commit the result: a test fails when a page differs from what the module generates.

## Undoing a release

If a tag was pushed too early, delete it (`git tag -d vx.y.z`, then `git push origin --delete vx.y.z`), delete the GitHub release, fix, and tag again from the new head.
