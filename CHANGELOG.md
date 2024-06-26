# Changelog

## [Unreleased]

## [0.9.11] - 2024-02-20
### Changed
- Reduced the container image size by 60% (@bougyman)

### Fixed
- Fixed sqlite problem with ruby 3.3 (https://github.com/sparklemotion/sqlite3-ruby/issues/434) by pinning to alpine 3.18 (@bougyman)

## [0.9.10] - 2024-02-08
### Fixed
- Fixed rubocop offenses (@bougyman)

## [0.9.8] - 2024-02-08
### Added
- Added the console subcommand to get a pry console (@bougyman)

## [0.9.7] - 2024-02-08
### Added
- Added the plc wrapper for container running, and ssh for git ops in the container (@bougyman)

## [0.9.5] - 2024-02-08
### Added
- Added build_image to build/push container image (@bougyman)
- Added user information to comment list in issue view (@bougyman)

## [0.9.4] - 2024-02-07
### Fixed
- Fixed issue with canceled issues showing up in lcls (@bougyman)

## [0.9.3] - 2024-02-07
### Fixed
- Fixed probblem with tempfile for editing operations (@bougyman)

## [0.9.1] - 2024-02-06
### Fixed
- Fixed wrapper to be more normal about help when listing leaf commands (@bougyman)

## [0.9.0] - 2024-02-06
### Added
- Added version. Ready for 0.9.0, now test-test-test-test before 1.0 (@bougyman)

## [0.8.6] - 2024-02-06
### Fixed
- Fixed completion for lc alias (@bougyman)

## [0.8.4] - 2024-02-06
### Added
- Added version command (@bougyman)

## [0.8.1] - 2024-02-06
### Fixed
- Fixed problem with setting verbosity (@bougyman)

## [0.8.0] - 2024-02-06
### Added
- Added Containerfile to build oci image (@bougyman)

## [0.7.7] - 2024-02-06
### Added
- Added ability to attach project to command (@bougyman)
- Added issue pr command (@bougyman)
- Added lcomment alias to add comments to issues (@bougyman)

## [0.7.5] - 2024-02-05
### Fixed
- Fixed problem when choosing from multiple completed states (@bougyman)

## [0.7.3] - 2024-02-04
### Fixed
- Fixed problem with issue relationship to user (@bougyman)

## [0.7.2] - 2024-02-04
### Fixed
- Fixed problem when trying to develop an unassigned issue (@bougyman)

## [0.7.1] - 2024-02-04
### Fixed
- Fixed extra output when commenting on an inssue (@bougyman)

## [0.7.0] - 2024-02-04
### Added
- Added better help when using the lc bin and aliases (@bougyman)

## [0.6.1] - 2024-02-04
### Added
- Added lcreate alias (@bougyman)

## [0.6.0] - 2024-02-04

## [0.5.5] - 2024-02-04
### Added
- Added lclose alias and 'issue update' subcommand (@bougyman)

## [0.5.4] - 2024-02-04

## [0.5.3] - 2024-02-03
### Added
- Added support for multiline descriptions without failing (@bougyman)

### Changed
- Changed default branch to use upstream default branch name (@bougyman)

## [0.5.2] - 2024-02-03
### Added
- Added new changelog management system (changelog-rb) (@bougyman)

[Unreleased]: https://github.com/rubyists/linear-cli/compare/v0.9.11...HEAD
[0.9.11]: https://github.com/rubyists/linear-cli/compare/v0.9.10...v0.9.11
[0.9.10]: https://github.com/rubyists/linear-cli/compare/0.9.8...v0.9.10
[0.9.8]: https://github.com/rubyists/linear-cli/compare/v0.9.7...0.9.8
[0.9.7]: https://github.com/rubyists/linear-cli/compare/v0.9.5...v0.9.7
[0.9.5]: https://github.com/rubyists/linear-cli/compare/v0.9.4...v0.9.5
[0.9.4]: https://github.com/rubyists/linear-cli/compare/v0.9.3...v0.9.4
[0.9.3]: https://github.com/rubyists/linear-cli/compare/v0.9.1...v0.9.3
[0.9.1]: https://github.com/rubyists/linear-cli/compare/v0.9.0...v0.9.1
[0.9.0]: https://github.com/rubyists/linear-cli/compare/v0.8.6...v0.9.0
[0.8.6]: https://github.com/rubyists/linear-cli/compare/v0.8.4...v0.8.6
[0.8.4]: https://github.com/rubyists/linear-cli/compare/v0.8.1...v0.8.4
[0.8.1]: https://github.com/rubyists/linear-cli/compare/v0.8.0...v0.8.1
[0.8.0]: https://github.com/rubyists/linear-cli/compare/v0.7.7...v0.8.0
[0.7.7]: https://github.com/rubyists/linear-cli/compare/v0.7.5...v0.7.7
[0.7.5]: https://github.com/rubyists/linear-cli/compare/v0.7.3...v0.7.5
[0.7.3]: https://github.com/rubyists/linear-cli/compare/v0.7.2...v0.7.3
[0.7.2]: https://github.com/rubyists/linear-cli/compare/v0.7.1...v0.7.2
[0.7.1]: https://github.com/rubyists/linear-cli/compare/v0.7.0...v0.7.1
[0.7.0]: https://github.com/rubyists/linear-cli/compare/v0.6.1...v0.7.0
[0.6.1]: https://github.com/rubyists/linear-cli/compare/v0.6.0...v0.6.1
[0.6.0]: https://github.com/rubyists/linear-cli/compare/v0.5.5...v0.6.0
[0.5.5]: https://github.com/rubyists/linear-cli/compare/v0.5.4...v0.5.5
[0.5.4]: https://github.com/rubyists/linear-cli/compare/v0.5.3...v0.5.4
[0.5.3]: https://github.com/rubyists/linear-cli/compare/v0.5.2...v0.5.3
