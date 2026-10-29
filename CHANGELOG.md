# Change log for SPSSiteLifecycle

The format is based on and uses the types of changes according to [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Project skeleton: CI workflows (Pester on Windows and Linux, PSScriptAnalyzer, release,
  wiki sync), contribution files, issue and pull request templates, security policy and the
  first wiki pages.
- Common module `SPSSiteLifecycle.Common` and the settings file: a PowerShell data file read with
  a complete, strict check (unknown key, key in the wrong section, type, range, missing file,
  refused tenant), a schema that is the single source of truth, `Get-SPSLifecycleSetting` and an
  example file. The Microsoft corporate tenants are always refused.
