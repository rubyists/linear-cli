# Changelog

## [1.3.1](https://github.com/rubyists/linear-cli/compare/v1.3.0...v1.3.1) (2026-08-12)


### Bug Fixes

* retry install.sh's curl downloads on transient connection failures ([#94](https://github.com/rubyists/linear-cli/issues/94)) ([c4633a2](https://github.com/rubyists/linear-cli/commit/c4633a2dfbc11f9484a5f5462c7f8888425b4749))

## [1.3.0](https://github.com/rubyists/linear-cli/compare/v1.2.0...v1.3.0) (2026-08-12)


### Features

* add mix setup/git_hooks, activate a pre-push conventional-commit hook ([#90](https://github.com/rubyists/linear-cli/issues/90)) ([a81ffe1](https://github.com/rubyists/linear-cli/commit/a81ffe133a8be1e8c608778d18669e4bd77b9de9))

## [1.2.0](https://github.com/rubyists/linear-cli/compare/v1.1.1...v1.2.0) (2026-08-12)


### Features

* add a root-level repo-management Mix project (mix container.build/publish) ([#84](https://github.com/rubyists/linear-cli/issues/84)) ([9d0b730](https://github.com/rubyists/linear-cli/commit/9d0b73017e3193a5254e0fcc291a48880440f168))


### Bug Fixes

* give a clear message and exit 78 when LINEAR_API_KEY is missing ([#86](https://github.com/rubyists/linear-cli/issues/86)) ([c5b9ec1](https://github.com/rubyists/linear-cli/commit/c5b9ec1facb11c6b4557414f24dadaea42ad96ab))

## [1.1.1](https://github.com/rubyists/linear-cli/compare/v1.1.0...v1.1.1) (2026-08-12)


### Bug Fixes

* update references after the linear-cli-ex -&gt; linear-cli / linear-cli -&gt; linear-cli-rb repo renames ([#81](https://github.com/rubyists/linear-cli/issues/81)) ([8328782](https://github.com/rubyists/linear-cli/commit/8328782d5c083ee3cfbfe09c3b2432cfe88f06b2))

## [1.1.0](https://github.com/rubyists/linear-cli-ex/compare/v1.0.0...v1.1.0) (2026-08-12)


### Features

* **cli:** vendor rubyists/homebrew-tap, make install.sh curl-pipeable ([#75](https://github.com/rubyists/linear-cli-ex/issues/75)) ([e836ab1](https://github.com/rubyists/linear-cli-ex/commit/e836ab1b9e1fd49b6b5a7ce94c15ac137e705c2d))

## [1.0.0](https://github.com/rubyists/linear-cli-ex/compare/v1.0.0...v1.0.0) (2026-08-11)


### ⚠ BREAKING CHANGES

* graduate to 1.0.0 - disable pre-major version bumping ([#70](https://github.com/rubyists/linear-cli-ex/issues/70))
* **cd:** parallelize Burrito target builds and fix Trivy/Podman image scanning ([#68](https://github.com/rubyists/linear-cli-ex/issues/68))
* **ci:** rename release.yaml to main.yaml, workflow name to "main" ([#38](https://github.com/rubyists/linear-cli-ex/issues/38))
* add Readme/LICENSE, feat: wire up the issue list --project picker ([#12](https://github.com/rubyists/linear-cli-ex/issues/12))

### Features

* add mix githooks.install to activate the repo's git hooks ([#51](https://github.com/rubyists/linear-cli-ex/issues/51)) ([9b35472](https://github.com/rubyists/linear-cli-ex/commit/9b354722239ee81bbc3cf9ccd832ab4f79ea6ced))
* **api:** add LinearCli.Api GraphQL client (Phase 1) ([723f3f6](https://github.com/rubyists/linear-cli-ex/commit/723f3f60e3d137b69e7919c0ffc28099598086e5))
* **ci:** add a full SBOM - app deps, OTP/Elixir runtime, container OS packages ([#54](https://github.com/rubyists/linear-cli-ex/issues/54)) ([e296fdd](https://github.com/rubyists/linear-cli-ex/commit/e296fdde2c141f2098905ae0b5c444db357a073b))
* **cli:** add favorite teams/projects, filtering list views by them ([#61](https://github.com/rubyists/linear-cli-ex/issues/61)) ([6c858d9](https://github.com/rubyists/linear-cli-ex/commit/6c858d9295a860b1415f1761c90ddf7e449dec12))
* **cli:** add issue create/develop/pr/take/update write commands (Phase 6) ([1649618](https://github.com/rubyists/linear-cli-ex/commit/1649618fec1b43da32f8975471dc1905540c21c9))
* **cli:** add profiles - default team/project stored in local SQLite ([#57](https://github.com/rubyists/linear-cli-ex/issues/57)) ([554e336](https://github.com/rubyists/linear-cli-ex/commit/554e336951127e33bd031c380ffb7c9a4eda6328))
* **cli:** add project update - post a status update to a project ([#43](https://github.com/rubyists/linear-cli-ex/issues/43)) ([30dc6dc](https://github.com/rubyists/linear-cli-ex/commit/30dc6dcd2f47fd698adfa74f4e439cc5f57eba5b))
* **cli:** make version respect --output json ([#33](https://github.com/rubyists/linear-cli-ex/issues/33)) ([b160aad](https://github.com/rubyists/linear-cli-ex/commit/b160aadf663c861ffab53f1fcc351d83a767f6ec))
* **cli:** resolve bare issue numbers via active profile, favorited teams, or a team prompt ([#65](https://github.com/rubyists/linear-cli-ex/issues/65)) ([8b183da](https://github.com/rubyists/linear-cli-ex/commit/8b183dafcae66456eb2008775887b1bb70be6b76))
* **cli:** support Ruby's short subcommand aliases ([#15](https://github.com/rubyists/linear-cli-ex/issues/15)) ([9fca6b5](https://github.com/rubyists/linear-cli-ex/commit/9fca6b5ea659c72e1766af2593e357f3b5383f0d))
* initial commit with ash submodule ([c2ceafb](https://github.com/rubyists/linear-cli-ex/commit/c2ceafb8007360eb1b6f05fed0512c49dbbcfc19))
* **linear:** add Ash domain resources for Issue/Project/Team/User/Label/WorkflowState/Comment (Phase 2) ([e2a27f3](https://github.com/rubyists/linear-cli-ex/commit/e2a27f3258e0951f83aa0b997f3912327442232a))
* **oban:** add scheduled monthly project rollover (Phase 7) ([11afb43](https://github.com/rubyists/linear-cli-ex/commit/11afb43e2b30f55db5dcceba72020fabb5978c52))
* phase 4 from initial plan -&gt; complete ([012866e](https://github.com/rubyists/linear-cli-ex/commit/012866edc7d61ee403d477221490fc493fda2bdf))
* phase 8 - packaging, releasing, and CI ([#1](https://github.com/rubyists/linear-cli-ex/issues/1)) ([905c238](https://github.com/rubyists/linear-cli-ex/commit/905c238967f29c59c1d02669138ca8998b414e38))
* scaffold Elixir port and enforce conventional commits ([a4d03a0](https://github.com/rubyists/linear-cli-ex/commit/a4d03a0e8f5fe94d2f699aecbc9a0e128dc02689))


### Bug Fixes

* **ci:** consolidate the release pipeline into one workflow/DAG ([ba821bb](https://github.com/rubyists/linear-cli-ex/commit/ba821bb4c172857af37058c689e5891ffdc93e5f))
* **ci:** create releases as drafts so assets survive Immutable Releases ([#19](https://github.com/rubyists/linear-cli-ex/issues/19)) ([8572623](https://github.com/rubyists/linear-cli-ex/commit/8572623eb515f2066aeade9b61d96929cee543fb))
* **ci:** package release binaries with the wrapper scripts ([#24](https://github.com/rubyists/linear-cli-ex/issues/24)) ([5fb24a4](https://github.com/rubyists/linear-cli-ex/commit/5fb24a473685ba20fdff0ee57b5fbfa572d2fc45))
* **ci:** rebuild the release pipeline to stop the version-bump runaway loop ([#30](https://github.com/rubyists/linear-cli-ex/issues/30)) ([c311fd4](https://github.com/rubyists/linear-cli-ex/commit/c311fd4dbc6a720b995c530daefa3bf1b6343452))
* **ci:** relabel the release PR as tagged after we tag it ourselves ([ab1408e](https://github.com/rubyists/linear-cli-ex/commit/ab1408e3df9137477bb535412763960e37e7fac1))
* **ci:** skip commit-subject validation in the post-merge pipeline ([#41](https://github.com/rubyists/linear-cli-ex/issues/41)) ([3d00a85](https://github.com/rubyists/linear-cli-ex/commit/3d00a85732254cdf5719e5d42d67174a028be24b))
* **cli:** reject unrecognized flags instead of treating them as issue ids ([#2](https://github.com/rubyists/linear-cli-ex/issues/2)) ([#4](https://github.com/rubyists/linear-cli-ex/issues/4)) ([e697ff6](https://github.com/rubyists/linear-cli-ex/commit/e697ff60d0d366efa70325acc9861012ca1aaffe))
* **deps:** update ash to a non-vulnerable version ([#63](https://github.com/rubyists/linear-cli-ex/issues/63)) ([b838e2a](https://github.com/rubyists/linear-cli-ex/commit/b838e2ad5147c6c38894be4e374621f55aa4bfeb))


### Performance Improvements

* **linear:** fan out find-by-ids and per-team project fetches (Phase 5) ([fb00153](https://github.com/rubyists/linear-cli-ex/commit/fb00153de3aae7490331e8b6413bb2bee18ee473))


### Documentation

* add Readme/LICENSE, feat: wire up the issue list --project picker ([#12](https://github.com/rubyists/linear-cli-ex/issues/12)) ([eb42c69](https://github.com/rubyists/linear-cli-ex/commit/eb42c69112fe39d855559c78cb79982e0b9e8307))


### Miscellaneous Chores

* **ci:** rename release.yaml to main.yaml, workflow name to "main" ([#38](https://github.com/rubyists/linear-cli-ex/issues/38)) ([2581a40](https://github.com/rubyists/linear-cli-ex/commit/2581a405fc7f5cdc0532cce54e2a26c34e2f9890))
* graduate to 1.0.0 - disable pre-major version bumping ([#70](https://github.com/rubyists/linear-cli-ex/issues/70)) ([87a65ae](https://github.com/rubyists/linear-cli-ex/commit/87a65ae9a48e98ac299aa1bbc8093808f1ac7ba3))


### Continuous Integration

* **cd:** parallelize Burrito target builds and fix Trivy/Podman image scanning ([#68](https://github.com/rubyists/linear-cli-ex/issues/68)) ([5cc829a](https://github.com/rubyists/linear-cli-ex/commit/5cc829aed802a0d10ce75f1c330628f60ca2b7f1))

## [0.9.0](https://github.com/rubyists/linear-cli-ex/compare/v0.8.5...v0.9.0) (2026-08-11)


### ⚠ BREAKING CHANGES

* **cd:** parallelize Burrito target builds and fix Trivy/Podman image scanning ([#68](https://github.com/rubyists/linear-cli-ex/issues/68))

### Continuous Integration

* **cd:** parallelize Burrito target builds and fix Trivy/Podman image scanning ([#68](https://github.com/rubyists/linear-cli-ex/issues/68)) ([5cc829a](https://github.com/rubyists/linear-cli-ex/commit/5cc829aed802a0d10ce75f1c330628f60ca2b7f1))

## [0.8.5](https://github.com/rubyists/linear-cli-ex/compare/v0.8.4...v0.8.5) (2026-08-11)


### Bug Fixes

* **deps:** update ash to a non-vulnerable version ([#63](https://github.com/rubyists/linear-cli-ex/issues/63)) ([b838e2a](https://github.com/rubyists/linear-cli-ex/commit/b838e2ad5147c6c38894be4e374621f55aa4bfeb))

## [0.8.4](https://github.com/rubyists/linear-cli-ex/compare/v0.8.3...v0.8.4) (2026-08-11)


### Features

* **cli:** add favorite teams/projects, filtering list views by them ([#61](https://github.com/rubyists/linear-cli-ex/issues/61)) ([6c858d9](https://github.com/rubyists/linear-cli-ex/commit/6c858d9295a860b1415f1761c90ddf7e449dec12))
* **cli:** add profiles - default team/project stored in local SQLite ([#57](https://github.com/rubyists/linear-cli-ex/issues/57)) ([554e336](https://github.com/rubyists/linear-cli-ex/commit/554e336951127e33bd031c380ffb7c9a4eda6328))

## [0.8.3](https://github.com/rubyists/linear-cli-ex/compare/v0.8.2...v0.8.3) (2026-08-10)


### Features

* **ci:** add a full SBOM - app deps, OTP/Elixir runtime, container OS packages ([#54](https://github.com/rubyists/linear-cli-ex/issues/54)) ([e296fdd](https://github.com/rubyists/linear-cli-ex/commit/e296fdde2c141f2098905ae0b5c444db357a073b))

## [0.8.2](https://github.com/rubyists/linear-cli-ex/compare/v0.8.1...v0.8.2) (2026-08-10)


### Features

* add mix githooks.install to activate the repo's git hooks ([#51](https://github.com/rubyists/linear-cli-ex/issues/51)) ([9b35472](https://github.com/rubyists/linear-cli-ex/commit/9b354722239ee81bbc3cf9ccd832ab4f79ea6ced))

## [0.8.1](https://github.com/rubyists/linear-cli-ex/compare/v0.8.0...v0.8.1) (2026-08-10)


### Features

* **cli:** add project update - post a status update to a project ([#43](https://github.com/rubyists/linear-cli-ex/issues/43)) ([30dc6dc](https://github.com/rubyists/linear-cli-ex/commit/30dc6dcd2f47fd698adfa74f4e439cc5f57eba5b))

## [0.8.0](https://github.com/rubyists/linear-cli-ex/compare/v0.7.2...v0.8.0) (2026-08-10)


### ⚠ BREAKING CHANGES

* **ci:** rename release.yaml to main.yaml, workflow name to "main" ([#38](https://github.com/rubyists/linear-cli-ex/issues/38))

### Miscellaneous Chores

* **ci:** rename release.yaml to main.yaml, workflow name to "main" ([#38](https://github.com/rubyists/linear-cli-ex/issues/38)) ([2581a40](https://github.com/rubyists/linear-cli-ex/commit/2581a405fc7f5cdc0532cce54e2a26c34e2f9890))

## [0.7.2](https://github.com/rubyists/linear-cli-ex/compare/v0.7.1...v0.7.2) (2026-08-09)


### Features

* **cli:** make version respect --output json ([#33](https://github.com/rubyists/linear-cli-ex/issues/33)) ([b160aad](https://github.com/rubyists/linear-cli-ex/commit/b160aadf663c861ffab53f1fcc351d83a767f6ec))


### Bug Fixes

* **ci:** relabel the release PR as tagged after we tag it ourselves ([ab1408e](https://github.com/rubyists/linear-cli-ex/commit/ab1408e3df9137477bb535412763960e37e7fac1))

## [0.7.1](https://github.com/rubyists/linear-cli-ex/compare/v0.7.0...v0.7.1) (2026-08-09)


### Bug Fixes

* **ci:** rebuild the release pipeline to stop the version-bump runaway loop ([#30](https://github.com/rubyists/linear-cli-ex/issues/30)) ([c311fd4](https://github.com/rubyists/linear-cli-ex/commit/c311fd4dbc6a720b995c530daefa3bf1b6343452))

## [0.7.0](https://github.com/rubyists/linear-cli-ex/compare/v0.6.0...v0.7.0) (2026-08-09)


### ⚠ BREAKING CHANGES

* add Readme/LICENSE, feat: wire up the issue list --project picker ([#12](https://github.com/rubyists/linear-cli-ex/issues/12))

### Features

* **api:** add LinearCli.Api GraphQL client (Phase 1) ([723f3f6](https://github.com/rubyists/linear-cli-ex/commit/723f3f60e3d137b69e7919c0ffc28099598086e5))
* **cli:** add issue create/develop/pr/take/update write commands (Phase 6) ([1649618](https://github.com/rubyists/linear-cli-ex/commit/1649618fec1b43da32f8975471dc1905540c21c9))
* **cli:** support Ruby's short subcommand aliases ([#15](https://github.com/rubyists/linear-cli-ex/issues/15)) ([9fca6b5](https://github.com/rubyists/linear-cli-ex/commit/9fca6b5ea659c72e1766af2593e357f3b5383f0d))
* initial commit with ash submodule ([c2ceafb](https://github.com/rubyists/linear-cli-ex/commit/c2ceafb8007360eb1b6f05fed0512c49dbbcfc19))
* **linear:** add Ash domain resources for Issue/Project/Team/User/Label/WorkflowState/Comment (Phase 2) ([e2a27f3](https://github.com/rubyists/linear-cli-ex/commit/e2a27f3258e0951f83aa0b997f3912327442232a))
* **oban:** add scheduled monthly project rollover (Phase 7) ([11afb43](https://github.com/rubyists/linear-cli-ex/commit/11afb43e2b30f55db5dcceba72020fabb5978c52))
* phase 4 from initial plan -&gt; complete ([012866e](https://github.com/rubyists/linear-cli-ex/commit/012866edc7d61ee403d477221490fc493fda2bdf))
* phase 8 - packaging, releasing, and CI ([#1](https://github.com/rubyists/linear-cli-ex/issues/1)) ([905c238](https://github.com/rubyists/linear-cli-ex/commit/905c238967f29c59c1d02669138ca8998b414e38))
* scaffold Elixir port and enforce conventional commits ([a4d03a0](https://github.com/rubyists/linear-cli-ex/commit/a4d03a0e8f5fe94d2f699aecbc9a0e128dc02689))


### Bug Fixes

* **ci:** create releases as drafts so assets survive Immutable Releases ([#19](https://github.com/rubyists/linear-cli-ex/issues/19)) ([8572623](https://github.com/rubyists/linear-cli-ex/commit/8572623eb515f2066aeade9b61d96929cee543fb))
* **ci:** package release binaries with the wrapper scripts ([#24](https://github.com/rubyists/linear-cli-ex/issues/24)) ([5fb24a4](https://github.com/rubyists/linear-cli-ex/commit/5fb24a473685ba20fdff0ee57b5fbfa572d2fc45))
* **cli:** reject unrecognized flags instead of treating them as issue ids ([#2](https://github.com/rubyists/linear-cli-ex/issues/2)) ([#4](https://github.com/rubyists/linear-cli-ex/issues/4)) ([e697ff6](https://github.com/rubyists/linear-cli-ex/commit/e697ff60d0d366efa70325acc9861012ca1aaffe))


### Performance Improvements

* **linear:** fan out find-by-ids and per-team project fetches (Phase 5) ([fb00153](https://github.com/rubyists/linear-cli-ex/commit/fb00153de3aae7490331e8b6413bb2bee18ee473))


### Documentation

* add Readme/LICENSE, feat: wire up the issue list --project picker ([#12](https://github.com/rubyists/linear-cli-ex/issues/12)) ([eb42c69](https://github.com/rubyists/linear-cli-ex/commit/eb42c69112fe39d855559c78cb79982e0b9e8307))

## [0.6.0](https://github.com/rubyists/linear-cli-ex/compare/v0.5.0...v0.6.0) (2026-08-09)


### ⚠ BREAKING CHANGES

* add Readme/LICENSE, feat: wire up the issue list --project picker ([#12](https://github.com/rubyists/linear-cli-ex/issues/12))

### Features

* **api:** add LinearCli.Api GraphQL client (Phase 1) ([723f3f6](https://github.com/rubyists/linear-cli-ex/commit/723f3f60e3d137b69e7919c0ffc28099598086e5))
* **cli:** add issue create/develop/pr/take/update write commands (Phase 6) ([1649618](https://github.com/rubyists/linear-cli-ex/commit/1649618fec1b43da32f8975471dc1905540c21c9))
* **cli:** support Ruby's short subcommand aliases ([#15](https://github.com/rubyists/linear-cli-ex/issues/15)) ([9fca6b5](https://github.com/rubyists/linear-cli-ex/commit/9fca6b5ea659c72e1766af2593e357f3b5383f0d))
* initial commit with ash submodule ([c2ceafb](https://github.com/rubyists/linear-cli-ex/commit/c2ceafb8007360eb1b6f05fed0512c49dbbcfc19))
* **linear:** add Ash domain resources for Issue/Project/Team/User/Label/WorkflowState/Comment (Phase 2) ([e2a27f3](https://github.com/rubyists/linear-cli-ex/commit/e2a27f3258e0951f83aa0b997f3912327442232a))
* **oban:** add scheduled monthly project rollover (Phase 7) ([11afb43](https://github.com/rubyists/linear-cli-ex/commit/11afb43e2b30f55db5dcceba72020fabb5978c52))
* phase 4 from initial plan -&gt; complete ([012866e](https://github.com/rubyists/linear-cli-ex/commit/012866edc7d61ee403d477221490fc493fda2bdf))
* phase 8 - packaging, releasing, and CI ([#1](https://github.com/rubyists/linear-cli-ex/issues/1)) ([905c238](https://github.com/rubyists/linear-cli-ex/commit/905c238967f29c59c1d02669138ca8998b414e38))
* scaffold Elixir port and enforce conventional commits ([a4d03a0](https://github.com/rubyists/linear-cli-ex/commit/a4d03a0e8f5fe94d2f699aecbc9a0e128dc02689))


### Bug Fixes

* **ci:** create releases as drafts so assets survive Immutable Releases ([#19](https://github.com/rubyists/linear-cli-ex/issues/19)) ([8572623](https://github.com/rubyists/linear-cli-ex/commit/8572623eb515f2066aeade9b61d96929cee543fb))
* **ci:** package release binaries with the wrapper scripts ([#24](https://github.com/rubyists/linear-cli-ex/issues/24)) ([5fb24a4](https://github.com/rubyists/linear-cli-ex/commit/5fb24a473685ba20fdff0ee57b5fbfa572d2fc45))
* **cli:** reject unrecognized flags instead of treating them as issue ids ([#2](https://github.com/rubyists/linear-cli-ex/issues/2)) ([#4](https://github.com/rubyists/linear-cli-ex/issues/4)) ([e697ff6](https://github.com/rubyists/linear-cli-ex/commit/e697ff60d0d366efa70325acc9861012ca1aaffe))


### Performance Improvements

* **linear:** fan out find-by-ids and per-team project fetches (Phase 5) ([fb00153](https://github.com/rubyists/linear-cli-ex/commit/fb00153de3aae7490331e8b6413bb2bee18ee473))


### Documentation

* add Readme/LICENSE, feat: wire up the issue list --project picker ([#12](https://github.com/rubyists/linear-cli-ex/issues/12)) ([eb42c69](https://github.com/rubyists/linear-cli-ex/commit/eb42c69112fe39d855559c78cb79982e0b9e8307))

## [0.5.0](https://github.com/rubyists/linear-cli-ex/compare/v0.4.0...v0.5.0) (2026-08-09)


### ⚠ BREAKING CHANGES

* add Readme/LICENSE, feat: wire up the issue list --project picker ([#12](https://github.com/rubyists/linear-cli-ex/issues/12))

### Features

* **api:** add LinearCli.Api GraphQL client (Phase 1) ([723f3f6](https://github.com/rubyists/linear-cli-ex/commit/723f3f60e3d137b69e7919c0ffc28099598086e5))
* **cli:** add issue create/develop/pr/take/update write commands (Phase 6) ([1649618](https://github.com/rubyists/linear-cli-ex/commit/1649618fec1b43da32f8975471dc1905540c21c9))
* **cli:** support Ruby's short subcommand aliases ([#15](https://github.com/rubyists/linear-cli-ex/issues/15)) ([9fca6b5](https://github.com/rubyists/linear-cli-ex/commit/9fca6b5ea659c72e1766af2593e357f3b5383f0d))
* initial commit with ash submodule ([c2ceafb](https://github.com/rubyists/linear-cli-ex/commit/c2ceafb8007360eb1b6f05fed0512c49dbbcfc19))
* **linear:** add Ash domain resources for Issue/Project/Team/User/Label/WorkflowState/Comment (Phase 2) ([e2a27f3](https://github.com/rubyists/linear-cli-ex/commit/e2a27f3258e0951f83aa0b997f3912327442232a))
* **oban:** add scheduled monthly project rollover (Phase 7) ([11afb43](https://github.com/rubyists/linear-cli-ex/commit/11afb43e2b30f55db5dcceba72020fabb5978c52))
* phase 4 from initial plan -&gt; complete ([012866e](https://github.com/rubyists/linear-cli-ex/commit/012866edc7d61ee403d477221490fc493fda2bdf))
* phase 8 - packaging, releasing, and CI ([#1](https://github.com/rubyists/linear-cli-ex/issues/1)) ([905c238](https://github.com/rubyists/linear-cli-ex/commit/905c238967f29c59c1d02669138ca8998b414e38))
* scaffold Elixir port and enforce conventional commits ([a4d03a0](https://github.com/rubyists/linear-cli-ex/commit/a4d03a0e8f5fe94d2f699aecbc9a0e128dc02689))


### Bug Fixes

* **ci:** create releases as drafts so assets survive Immutable Releases ([#19](https://github.com/rubyists/linear-cli-ex/issues/19)) ([8572623](https://github.com/rubyists/linear-cli-ex/commit/8572623eb515f2066aeade9b61d96929cee543fb))
* **ci:** package release binaries with the wrapper scripts ([#24](https://github.com/rubyists/linear-cli-ex/issues/24)) ([5fb24a4](https://github.com/rubyists/linear-cli-ex/commit/5fb24a473685ba20fdff0ee57b5fbfa572d2fc45))
* **cli:** reject unrecognized flags instead of treating them as issue ids ([#2](https://github.com/rubyists/linear-cli-ex/issues/2)) ([#4](https://github.com/rubyists/linear-cli-ex/issues/4)) ([e697ff6](https://github.com/rubyists/linear-cli-ex/commit/e697ff60d0d366efa70325acc9861012ca1aaffe))


### Performance Improvements

* **linear:** fan out find-by-ids and per-team project fetches (Phase 5) ([fb00153](https://github.com/rubyists/linear-cli-ex/commit/fb00153de3aae7490331e8b6413bb2bee18ee473))


### Documentation

* add Readme/LICENSE, feat: wire up the issue list --project picker ([#12](https://github.com/rubyists/linear-cli-ex/issues/12)) ([eb42c69](https://github.com/rubyists/linear-cli-ex/commit/eb42c69112fe39d855559c78cb79982e0b9e8307))

## [0.4.0](https://github.com/rubyists/linear-cli-ex/compare/v0.3.1...v0.4.0) (2026-08-09)


### ⚠ BREAKING CHANGES

* add Readme/LICENSE, feat: wire up the issue list --project picker ([#12](https://github.com/rubyists/linear-cli-ex/issues/12))

### Features

* **api:** add LinearCli.Api GraphQL client (Phase 1) ([723f3f6](https://github.com/rubyists/linear-cli-ex/commit/723f3f60e3d137b69e7919c0ffc28099598086e5))
* **cli:** add issue create/develop/pr/take/update write commands (Phase 6) ([1649618](https://github.com/rubyists/linear-cli-ex/commit/1649618fec1b43da32f8975471dc1905540c21c9))
* **cli:** support Ruby's short subcommand aliases ([#15](https://github.com/rubyists/linear-cli-ex/issues/15)) ([9fca6b5](https://github.com/rubyists/linear-cli-ex/commit/9fca6b5ea659c72e1766af2593e357f3b5383f0d))
* initial commit with ash submodule ([c2ceafb](https://github.com/rubyists/linear-cli-ex/commit/c2ceafb8007360eb1b6f05fed0512c49dbbcfc19))
* **linear:** add Ash domain resources for Issue/Project/Team/User/Label/WorkflowState/Comment (Phase 2) ([e2a27f3](https://github.com/rubyists/linear-cli-ex/commit/e2a27f3258e0951f83aa0b997f3912327442232a))
* **oban:** add scheduled monthly project rollover (Phase 7) ([11afb43](https://github.com/rubyists/linear-cli-ex/commit/11afb43e2b30f55db5dcceba72020fabb5978c52))
* phase 4 from initial plan -&gt; complete ([012866e](https://github.com/rubyists/linear-cli-ex/commit/012866edc7d61ee403d477221490fc493fda2bdf))
* phase 8 - packaging, releasing, and CI ([#1](https://github.com/rubyists/linear-cli-ex/issues/1)) ([905c238](https://github.com/rubyists/linear-cli-ex/commit/905c238967f29c59c1d02669138ca8998b414e38))
* scaffold Elixir port and enforce conventional commits ([a4d03a0](https://github.com/rubyists/linear-cli-ex/commit/a4d03a0e8f5fe94d2f699aecbc9a0e128dc02689))


### Bug Fixes

* **ci:** create releases as drafts so assets survive Immutable Releases ([#19](https://github.com/rubyists/linear-cli-ex/issues/19)) ([8572623](https://github.com/rubyists/linear-cli-ex/commit/8572623eb515f2066aeade9b61d96929cee543fb))
* **ci:** package release binaries with the wrapper scripts ([#24](https://github.com/rubyists/linear-cli-ex/issues/24)) ([5fb24a4](https://github.com/rubyists/linear-cli-ex/commit/5fb24a473685ba20fdff0ee57b5fbfa572d2fc45))
* **cli:** reject unrecognized flags instead of treating them as issue ids ([#2](https://github.com/rubyists/linear-cli-ex/issues/2)) ([#4](https://github.com/rubyists/linear-cli-ex/issues/4)) ([e697ff6](https://github.com/rubyists/linear-cli-ex/commit/e697ff60d0d366efa70325acc9861012ca1aaffe))


### Performance Improvements

* **linear:** fan out find-by-ids and per-team project fetches (Phase 5) ([fb00153](https://github.com/rubyists/linear-cli-ex/commit/fb00153de3aae7490331e8b6413bb2bee18ee473))


### Documentation

* add Readme/LICENSE, feat: wire up the issue list --project picker ([#12](https://github.com/rubyists/linear-cli-ex/issues/12)) ([eb42c69](https://github.com/rubyists/linear-cli-ex/commit/eb42c69112fe39d855559c78cb79982e0b9e8307))

## [0.3.1](https://github.com/rubyists/linear-cli-ex/compare/v0.3.0...v0.3.1) (2026-08-09)


### Bug Fixes

* **ci:** package release binaries with the wrapper scripts ([#24](https://github.com/rubyists/linear-cli-ex/issues/24)) ([5fb24a4](https://github.com/rubyists/linear-cli-ex/commit/5fb24a473685ba20fdff0ee57b5fbfa572d2fc45))

## [0.3.0](https://github.com/rubyists/linear-cli-ex/compare/v0.2.1...v0.3.0) (2026-08-09)


### ⚠ BREAKING CHANGES

* add Readme/LICENSE, feat: wire up the issue list --project picker ([#12](https://github.com/rubyists/linear-cli-ex/issues/12))

### Features

* **api:** add LinearCli.Api GraphQL client (Phase 1) ([723f3f6](https://github.com/rubyists/linear-cli-ex/commit/723f3f60e3d137b69e7919c0ffc28099598086e5))
* **cli:** add issue create/develop/pr/take/update write commands (Phase 6) ([1649618](https://github.com/rubyists/linear-cli-ex/commit/1649618fec1b43da32f8975471dc1905540c21c9))
* **cli:** support Ruby's short subcommand aliases ([#15](https://github.com/rubyists/linear-cli-ex/issues/15)) ([9fca6b5](https://github.com/rubyists/linear-cli-ex/commit/9fca6b5ea659c72e1766af2593e357f3b5383f0d))
* initial commit with ash submodule ([c2ceafb](https://github.com/rubyists/linear-cli-ex/commit/c2ceafb8007360eb1b6f05fed0512c49dbbcfc19))
* **linear:** add Ash domain resources for Issue/Project/Team/User/Label/WorkflowState/Comment (Phase 2) ([e2a27f3](https://github.com/rubyists/linear-cli-ex/commit/e2a27f3258e0951f83aa0b997f3912327442232a))
* **oban:** add scheduled monthly project rollover (Phase 7) ([11afb43](https://github.com/rubyists/linear-cli-ex/commit/11afb43e2b30f55db5dcceba72020fabb5978c52))
* phase 4 from initial plan -&gt; complete ([012866e](https://github.com/rubyists/linear-cli-ex/commit/012866edc7d61ee403d477221490fc493fda2bdf))
* phase 8 - packaging, releasing, and CI ([#1](https://github.com/rubyists/linear-cli-ex/issues/1)) ([905c238](https://github.com/rubyists/linear-cli-ex/commit/905c238967f29c59c1d02669138ca8998b414e38))
* scaffold Elixir port and enforce conventional commits ([a4d03a0](https://github.com/rubyists/linear-cli-ex/commit/a4d03a0e8f5fe94d2f699aecbc9a0e128dc02689))


### Bug Fixes

* **ci:** create releases as drafts so assets survive Immutable Releases ([#19](https://github.com/rubyists/linear-cli-ex/issues/19)) ([8572623](https://github.com/rubyists/linear-cli-ex/commit/8572623eb515f2066aeade9b61d96929cee543fb))
* **cli:** reject unrecognized flags instead of treating them as issue ids ([#2](https://github.com/rubyists/linear-cli-ex/issues/2)) ([#4](https://github.com/rubyists/linear-cli-ex/issues/4)) ([e697ff6](https://github.com/rubyists/linear-cli-ex/commit/e697ff60d0d366efa70325acc9861012ca1aaffe))


### Performance Improvements

* **linear:** fan out find-by-ids and per-team project fetches (Phase 5) ([fb00153](https://github.com/rubyists/linear-cli-ex/commit/fb00153de3aae7490331e8b6413bb2bee18ee473))


### Documentation

* add Readme/LICENSE, feat: wire up the issue list --project picker ([#12](https://github.com/rubyists/linear-cli-ex/issues/12)) ([eb42c69](https://github.com/rubyists/linear-cli-ex/commit/eb42c69112fe39d855559c78cb79982e0b9e8307))

## [0.2.1](https://github.com/rubyists/linear-cli-ex/compare/v0.2.0...v0.2.1) (2026-08-09)


### Bug Fixes

* **ci:** create releases as drafts so assets survive Immutable Releases ([#19](https://github.com/rubyists/linear-cli-ex/issues/19)) ([8572623](https://github.com/rubyists/linear-cli-ex/commit/8572623eb515f2066aeade9b61d96929cee543fb))

## [0.2.0](https://github.com/rubyists/linear-cli-ex/compare/v0.1.2...v0.2.0) (2026-08-09)


### ⚠ BREAKING CHANGES

* add Readme/LICENSE, feat: wire up the issue list --project picker ([#12](https://github.com/rubyists/linear-cli-ex/issues/12))

### Documentation

* add Readme/LICENSE, feat: wire up the issue list --project picker ([#12](https://github.com/rubyists/linear-cli-ex/issues/12)) ([eb42c69](https://github.com/rubyists/linear-cli-ex/commit/eb42c69112fe39d855559c78cb79982e0b9e8307))

## [0.1.2](https://github.com/rubyists/linear-cli-ex/compare/v0.1.1...v0.1.2) (2026-08-09)


### Features

* **api:** add LinearCli.Api GraphQL client (Phase 1) ([723f3f6](https://github.com/rubyists/linear-cli-ex/commit/723f3f60e3d137b69e7919c0ffc28099598086e5))
* **cli:** add issue create/develop/pr/take/update write commands (Phase 6) ([1649618](https://github.com/rubyists/linear-cli-ex/commit/1649618fec1b43da32f8975471dc1905540c21c9))
* initial commit with ash submodule ([c2ceafb](https://github.com/rubyists/linear-cli-ex/commit/c2ceafb8007360eb1b6f05fed0512c49dbbcfc19))
* **linear:** add Ash domain resources for Issue/Project/Team/User/Label/WorkflowState/Comment (Phase 2) ([e2a27f3](https://github.com/rubyists/linear-cli-ex/commit/e2a27f3258e0951f83aa0b997f3912327442232a))
* **oban:** add scheduled monthly project rollover (Phase 7) ([11afb43](https://github.com/rubyists/linear-cli-ex/commit/11afb43e2b30f55db5dcceba72020fabb5978c52))
* phase 4 from initial plan -&gt; complete ([012866e](https://github.com/rubyists/linear-cli-ex/commit/012866edc7d61ee403d477221490fc493fda2bdf))
* phase 8 - packaging, releasing, and CI ([#1](https://github.com/rubyists/linear-cli-ex/issues/1)) ([905c238](https://github.com/rubyists/linear-cli-ex/commit/905c238967f29c59c1d02669138ca8998b414e38))
* scaffold Elixir port and enforce conventional commits ([a4d03a0](https://github.com/rubyists/linear-cli-ex/commit/a4d03a0e8f5fe94d2f699aecbc9a0e128dc02689))


### Bug Fixes

* **cli:** reject unrecognized flags instead of treating them as issue ids ([#2](https://github.com/rubyists/linear-cli-ex/issues/2)) ([#4](https://github.com/rubyists/linear-cli-ex/issues/4)) ([e697ff6](https://github.com/rubyists/linear-cli-ex/commit/e697ff60d0d366efa70325acc9861012ca1aaffe))


### Performance Improvements

* **linear:** fan out find-by-ids and per-team project fetches (Phase 5) ([fb00153](https://github.com/rubyists/linear-cli-ex/commit/fb00153de3aae7490331e8b6413bb2bee18ee473))

## [0.1.1](https://github.com/rubyists/linear-cli-ex/compare/v0.1.0...v0.1.1) (2026-08-09)


### Features

* **api:** add LinearCli.Api GraphQL client (Phase 1) ([723f3f6](https://github.com/rubyists/linear-cli-ex/commit/723f3f60e3d137b69e7919c0ffc28099598086e5))
* **cli:** add issue create/develop/pr/take/update write commands (Phase 6) ([1649618](https://github.com/rubyists/linear-cli-ex/commit/1649618fec1b43da32f8975471dc1905540c21c9))
* initial commit with ash submodule ([c2ceafb](https://github.com/rubyists/linear-cli-ex/commit/c2ceafb8007360eb1b6f05fed0512c49dbbcfc19))
* **linear:** add Ash domain resources for Issue/Project/Team/User/Label/WorkflowState/Comment (Phase 2) ([e2a27f3](https://github.com/rubyists/linear-cli-ex/commit/e2a27f3258e0951f83aa0b997f3912327442232a))
* **oban:** add scheduled monthly project rollover (Phase 7) ([11afb43](https://github.com/rubyists/linear-cli-ex/commit/11afb43e2b30f55db5dcceba72020fabb5978c52))
* phase 4 from initial plan -&gt; complete ([012866e](https://github.com/rubyists/linear-cli-ex/commit/012866edc7d61ee403d477221490fc493fda2bdf))
* phase 8 - packaging, releasing, and CI ([#1](https://github.com/rubyists/linear-cli-ex/issues/1)) ([905c238](https://github.com/rubyists/linear-cli-ex/commit/905c238967f29c59c1d02669138ca8998b414e38))
* scaffold Elixir port and enforce conventional commits ([a4d03a0](https://github.com/rubyists/linear-cli-ex/commit/a4d03a0e8f5fe94d2f699aecbc9a0e128dc02689))


### Bug Fixes

* **cli:** reject unrecognized flags instead of treating them as issue ids ([#2](https://github.com/rubyists/linear-cli-ex/issues/2)) ([#4](https://github.com/rubyists/linear-cli-ex/issues/4)) ([e697ff6](https://github.com/rubyists/linear-cli-ex/commit/e697ff60d0d366efa70325acc9861012ca1aaffe))


### Performance Improvements

* **linear:** fan out find-by-ids and per-team project fetches (Phase 5) ([fb00153](https://github.com/rubyists/linear-cli-ex/commit/fb00153de3aae7490331e8b6413bb2bee18ee473))
