# Changelog

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
