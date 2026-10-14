# hmods-workspace

Development environment for [Options Menu](https://github.com/DefKorns/OptionsMenu) and its add-ons.

Each project is worked on in its own folder next to this one (`../OptionsMenu`, `../om_theme-selector`, ...). The submodules in `core/` and `addons/` pin a set of versions known to work together, and `addons/` is the list of add-ons the scripts know about. Open `hmods-workspace.code-workspace` in VS Code to get every project in one window.

Run the scripts from Git Bash or WSL. They need git and Docker; `gh` (logged in) is needed to create GitHub repositories and to wait for releases.

Under WSL:

- install `gh` there too (`sudo apt install gh`, then `gh auth login`); the Windows one isn't used
- checkouts made by Git for Windows (`core.autocrlf=true`) can show submodules as modified because of line endings; `--release` ignores changes inside submodules
- don't alternate shells when building the same add-on: files built from Git Bash show up as owned by root in WSL, which then can't replace them. Delete that add-on's `out/` from Windows (Explorer or Git Bash) and build again

## Setup

```sh
scripts/setup.sh
```

- fetches the workspace submodules that aren't checked out yet
- builds the `classicmini-cross-toolchain:jessie-armhf` Docker image if it's missing. The console files it needs (`toolchain/vendor`) come from `../optionsmenu-vendor`, from `--vendor DIR`, or are cloned from the private `DefKorns/optionsmenu-vendor`
- lists the add-ons and the folder each one builds from

## New add-on

```sh
scripts/new-addon.sh                                   # asks for everything
scripts/new-addon.sh --name "My Addon" --repo new      # private github.com/<owner>/om-my-addon
scripts/new-addon.sh --name "My Addon" --repo https://github.com/<owner>/<repo>.git --cpp
```

`<owner>` is `$GITHUB_OWNER` (default `DefKorns`). Creates `../<id>` with the `vendor/OptionsMenu` (`modern-ui-ttf`), `toolchain` and `hmod-build` submodules, a Makefile, `build.sh`, the CI workflow pinned to the `hmod-build` commit, an uninstall script and a sample **Options Menu → _name_** screen with its own translations. `--cpp` adds a C++ program built against the Options Menu framework.

Nothing is committed: the scaffold is left staged. Commit it, then run the same command again to create/push the GitHub repository, register it in `addons/` (staged) and add it to the VS Code workspace.

An existing add-on (already in `../<id>`, or a repository URL whose Makefile uses `hmod-build`) is adopted as is: `scripts/new-addon.sh --id <id>`.

The CI of a C++ add-on builds the toolchain image from a private repository, so it fails until the repository has the secrets that `hmod-build`'s workflow expects. Set them by hand in the repository settings; shell-only add-ons don't need them.

## Export

Every add-on is exported as its own `.hmod`, the same file `make hmod` builds.

Local build, from the `../<id>` working copies:

```sh
scripts/export.sh                    # every add-on in addons/
scripts/export.sh om-my-addon        # just these
scripts/export.sh --pinned           # the commits pinned in addons/ instead
scripts/export.sh --zip              # also export/options-menu-addons-<date>.zip
scripts/export.sh --list             # what would be built, and from where
```

The files land in `export/`, with `export/manifest.tsv` listing the version, commit and SHA-256 of each.

GitHub release: tags the working copy's HEAD and pushes the tag; the add-on's `hmod-build` workflow then builds the `.hmod` and publishes the release.

```sh
scripts/export.sh --release patch om-my-addon               # v1.2.3 -> v1.2.4
scripts/export.sh --release minor --dry-run --all           # show the plan only
scripts/export.sh --release v2.0.0 --wait om-my-addon       # wait and download the released .hmod into export/
```

Pre-releases use the `-alphaN`, `-betaN` and `-rcN` suffixes, and GitHub marks them as pre-releases:

| `--release` | Latest tag | New tag |
| --- | --- | --- |
| `alpha` | `v1.2.3` | `v1.2.4-alpha1` (`--bump minor` → `v1.3.0-alpha1`) |
| `alpha` | `v2.0.0-alpha11` | `v2.0.0-alpha12` |
| `beta` / `rc` | `v2.0.0-alpha11` | `v2.0.0-beta1` / `v2.0.0-rc1` |
| `alpha` | `v2.0.0-beta2` | refused, it never goes back; `--bump` starts a new cycle |
| `final` | `v2.0.0-rc1` | `v2.0.0` |
| `patch` | `v2.0.0-rc1` | `v2.0.1` |
| `v2.0.0-rc2` | any | `v2.0.0-rc2` |

Push the branch first. Before tagging it checks that the tree is clean, the commit is already on the GitHub remote (the first `github.com` remote, or `--remote NAME`), it isn't tagged yet and the release workflow exists, then asks for confirmation (`--yes` skips it).
