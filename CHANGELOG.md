# Changelog

## [2.0.1](https://github.com/rubyists/linear-cli/compare/v2.0.0...v2.0.1) (2026-08-20)


### Bug Fixes

* bypass burrito proxy writer when output is to a terminal ([#166](https://github.com/rubyists/linear-cli/issues/166)) ([070a1d6](https://github.com/rubyists/linear-cli/commit/070a1d68ec6d8487a9bf5542b1beb891bcf42367))

## [2.0.0](https://github.com/rubyists/linear-cli/compare/v1.16.0...v2.0.0) (2026-08-20)


### ⚠ BREAKING CHANGES

* **linux:** bundle an mdex musl libgcc runtime ([#164](https://github.com/rubyists/linear-cli/issues/164))

### Bug Fixes

* **linux:** bundle an mdex musl libgcc runtime ([#164](https://github.com/rubyists/linear-cli/issues/164)) ([377c1d9](https://github.com/rubyists/linear-cli/commit/377c1d92da1303c9d258ceaad22d7d02e358ab11))

## [1.16.0](https://github.com/rubyists/linear-cli/compare/v1.15.2...v1.16.0) (2026-08-20)


### Features

* **EXT-5:** show workflow status in compact and full issue listings ([#162](https://github.com/rubyists/linear-cli/issues/162)) ([acf35e5](https://github.com/rubyists/linear-cli/commit/acf35e5483d5312ab1bd43db9cf6901e6c9d26d2))


### Bug Fixes

* **EXT-4:** handle GraphQL error and partial-data responses explicitly ([#160](https://github.com/rubyists/linear-cli/issues/160)) ([31359ef](https://github.com/rubyists/linear-cli/commit/31359effcc63b7e8472a3f1158a54bea77882d83))
* **EXT-7:** bundle musl NIF for Linux Burrito releases and container ([#163](https://github.com/rubyists/linear-cli/issues/163)) ([3172d4e](https://github.com/rubyists/linear-cli/commit/3172d4ef88f786be18eedbb334232bc8b805a575))

## [1.15.2](https://github.com/rubyists/linear-cli/compare/v1.15.1...v1.15.2) (2026-08-19)


### Bug Fixes

* ensure team scoping wraps sub filters ([#158](https://github.com/rubyists/linear-cli/issues/158)) ([bc19184](https://github.com/rubyists/linear-cli/commit/bc19184b527a40e0cf21c60d67c8056095fc375f))

## [1.15.1](https://github.com/rubyists/linear-cli/compare/v1.15.0...v1.15.1) (2026-08-19)


### Bug Fixes

* fix workflow for rebasing ([#155](https://github.com/rubyists/linear-cli/issues/155)) ([c44178c](https://github.com/rubyists/linear-cli/commit/c44178c4261de4b02371aaa919437ebf523d1072))
* **project:** scope all project prompts to team ([#154](https://github.com/rubyists/linear-cli/issues/154)) ([b884436](https://github.com/rubyists/linear-cli/commit/b884436414e94c45ecff0e9b73579b1f6fba6e14))

## [1.15.0](https://github.com/rubyists/linear-cli/compare/v1.14.0...v1.15.0) (2026-08-19)


### Features

* **issue:** add --status/-s to assign and take ([#151](https://github.com/rubyists/linear-cli/issues/151)) ([537f54b](https://github.com/rubyists/linear-cli/commit/537f54b073cdae3ce595e1b57426e6b1c0b645c9))


### Bug Fixes

* **api:** handle GraphQL partial-success responses cleanly (CRY-61) ([#150](https://github.com/rubyists/linear-cli/issues/150)) ([21d0363](https://github.com/rubyists/linear-cli/commit/21d03636b90a101c3eb8437da89d1370a516cb25))

## [1.14.0](https://github.com/rubyists/linear-cli/compare/v1.13.2...v1.14.0) (2026-08-18)


### Features

* **issue:** add --description option to lc issue update ([#141](https://github.com/rubyists/linear-cli/issues/141)) ([d762f32](https://github.com/rubyists/linear-cli/commit/d762f327ff6dd08768b4f476c1ea1b5a794ef402))
* **issue:** add interactive issue assign command ([#140](https://github.com/rubyists/linear-cli/issues/140)) ([33176bd](https://github.com/rubyists/linear-cli/commit/33176bdb5427b5e36146973d7b383304c394ad90))

## [1.13.2](https://github.com/rubyists/linear-cli/compare/v1.13.1...v1.13.2) (2026-08-16)


### Bug Fixes

* correct Linear API key settings URL ([#134](https://github.com/rubyists/linear-cli/issues/134)) ([382e5cf](https://github.com/rubyists/linear-cli/commit/382e5cf8dac856cf65394f38d11778e3db9e3215))
* removes tap ([#137](https://github.com/rubyists/linear-cli/issues/137)) ([9957242](https://github.com/rubyists/linear-cli/commit/995724290280a7f754a62c46ac79efebf2e430c0))

## [1.13.1](https://github.com/rubyists/linear-cli/compare/v1.13.0...v1.13.1) (2026-08-16)


### Bug Fixes

* **rules:** ensure we mix ci before we do anything else ([#135](https://github.com/rubyists/linear-cli/issues/135)) ([a7347d5](https://github.com/rubyists/linear-cli/commit/a7347d5b8b84ef93d9e2aa265a41a0d51bdbacd5))

## [1.13.0](https://github.com/rubyists/linear-cli/compare/v1.12.0...v1.13.0) (2026-08-16)


### Features

* **homebrew:** add Linux ARM64 to the tap formula and release automation ([#130](https://github.com/rubyists/linear-cli/issues/130)) ([62fe899](https://github.com/rubyists/linear-cli/commit/62fe899156331850736c7414c2e9163961385b46))

## [1.12.0](https://github.com/rubyists/linear-cli/compare/v1.11.0...v1.12.0) (2026-08-16)


### Features

* add st and stat aliases for issue status (CRY-50) ([#128](https://github.com/rubyists/linear-cli/issues/128)) ([988d978](https://github.com/rubyists/linear-cli/commit/988d978fcba8bdccc272f4591d3abfde60700118))

## [1.11.0](https://github.com/rubyists/linear-cli/compare/v1.10.0...v1.11.0) (2026-08-16)


### Features

* **ci:** add linux_aarch64 release build (CRY-48) ([#125](https://github.com/rubyists/linear-cli/issues/125)) ([da25532](https://github.com/rubyists/linear-cli/commit/da255325b0a0bfa14df23591e2d2d581fe6d4fc0))

## [1.10.0](https://github.com/rubyists/linear-cli/compare/v1.9.1...v1.10.0) (2026-08-16)


### Features

* **issue:** add lc issue status command ([#123](https://github.com/rubyists/linear-cli/issues/123)) ([20d0158](https://github.com/rubyists/linear-cli/commit/20d0158e2d103bb796c4d604d2e3a1b4b2ea04f5))

## [1.9.1](https://github.com/rubyists/linear-cli/compare/v1.9.0...v1.9.1) (2026-08-16)


### Bug Fixes

* **issue-list:** add --no-profile flag to bypass active profile defaults ([#119](https://github.com/rubyists/linear-cli/issues/119)) ([f19409c](https://github.com/rubyists/linear-cli/commit/f19409c1a083d9b6daacb4f972d4a5188da031f0))

## [1.9.0](https://github.com/rubyists/linear-cli/compare/v1.8.0...v1.9.0) (2026-08-16)


### Features

* **profile:** add profile clear command ([#120](https://github.com/rubyists/linear-cli/issues/120)) ([45cce6f](https://github.com/rubyists/linear-cli/commit/45cce6f154cc2c8068887a01958abe751aac36d1))

## [1.8.0](https://github.com/rubyists/linear-cli/compare/v1.7.0...v1.8.0) (2026-08-14)


### Features

* **issue:** add --all and --status filters to issue list ([#117](https://github.com/rubyists/linear-cli/issues/117)) ([4517e82](https://github.com/rubyists/linear-cli/commit/4517e826bf4bc52316e8c947adbe21c2ef9ca4bd))

## [1.7.0](https://github.com/rubyists/linear-cli/compare/v1.6.0...v1.7.0) (2026-08-14)


### Features

* add mix lc development proxy ([#115](https://github.com/rubyists/linear-cli/issues/115)) ([a7da443](https://github.com/rubyists/linear-cli/commit/a7da4432d722fa931967eb5d61ed49c6f4b1f533))

## [1.6.0](https://github.com/rubyists/linear-cli/compare/v1.5.1...v1.6.0) (2026-08-14)


### Features

* **build:** add mix burrito.dinein for local binary builds ([#112](https://github.com/rubyists/linear-cli/issues/112)) ([decf951](https://github.com/rubyists/linear-cli/commit/decf95122f8ebef4fa642c2969b35aef1d641592))


### Bug Fixes

* **ai:** adds CLAUDE.md symlink ([#110](https://github.com/rubyists/linear-cli/issues/110)) ([5165c4e](https://github.com/rubyists/linear-cli/commit/5165c4ecd67d521b0c55550b3089af424b255871))
* **close:** make issue close/cancel idempotent when already in terminal state ([#113](https://github.com/rubyists/linear-cli/issues/113)) ([0a71060](https://github.com/rubyists/linear-cli/commit/0a710604339e9fbf4db7917a09fcdfdedb2c716f))

## [1.5.1](https://github.com/rubyists/linear-cli/compare/v1.5.0...v1.5.1) (2026-08-14)


### Bug Fixes

* **ci:** build each Burrito target on its matching OS runner (CRY-40) ([#108](https://github.com/rubyists/linear-cli/issues/108)) ([c2d592d](https://github.com/rubyists/linear-cli/commit/c2d592d29fdb0f488a07afbaa7889ec53534443e))

## [1.5.0](https://github.com/rubyists/linear-cli/compare/v1.4.1...v1.5.0) (2026-08-13)


### Features

* launch stokowski sessions via mix stokowski ([#106](https://github.com/rubyists/linear-cli/issues/106)) ([550ed26](https://github.com/rubyists/linear-cli/commit/550ed26e4486af95d936f7b97baa1babed49dec9))
* vendor stokowski for Linear-driven agent orchestration ([#101](https://github.com/rubyists/linear-cli/issues/101)) ([b68fc57](https://github.com/rubyists/linear-cli/commit/b68fc57c0acab0903979d0ea8b36e15a403a0664))

## [1.4.1](https://github.com/rubyists/linear-cli/compare/v1.4.0...v1.4.1) (2026-08-12)


### Bug Fixes

* write .version directly instead of hardcoding the version in urls ([#98](https://github.com/rubyists/linear-cli/issues/98)) ([170ba1e](https://github.com/rubyists/linear-cli/commit/170ba1e4dad7eecdde34e9744269951da760b0e1))

## [1.4.0](https://github.com/rubyists/linear-cli/compare/v1.3.0...v1.4.0) (2026-08-12)


### Features

* bump the homebrew-tap formula automatically after each release ([#95](https://github.com/rubyists/linear-cli/issues/95)) ([d13ddf4](https://github.com/rubyists/linear-cli/commit/d13ddf46ea207947637a4a30c3c651e60c591bf6))


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
