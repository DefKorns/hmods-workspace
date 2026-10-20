# hmods-workspace

Development environment for [Options Menu](https://github.com/DefKorns/OptionsMenu) and its add-ons, in one clone:

```text
core/OptionsMenu/      Options Menu (submodule)
tools/hmod-build/      shared packaging and release workflow (submodule)
addons/<id>/           your add-ons, one clone each (not tracked by the workspace)
scripts/               setup, new-addon, export, bump
template/              what new-addon.sh scaffolds from
```

`core/OptionsMenu` and `tools/hmod-build` are submodules and also working copies. Each add-on is a normal clone of its own repository under `addons/`, which the workspace ignores; the scripts work on whatever is there.

```sh
git clone --recursive https://github.com/DefKorns/hmods-workspace.git
cd hmods-workspace && scripts/setup.sh
```

To get your own repositories back on another machine, list them in `projects.local` (format in `projects.example`, one `path url [branch]` per line) and run `scripts/setup.sh`. Paths outside `addons/` work too, e.g. tools you keep next to the workspace's.

Run the scripts from Git Bash or WSL. They need git and Docker; `gh` (logged in) is needed to create GitHub repositories and to wait for releases.

Under WSL:

- install `gh` there too (`sudo apt install gh`, then `gh auth login`); the Windows one isn't used
- don't alternate shells when building the same add-on: files built from Git Bash show up as owned by root in WSL, which then can't replace them. Delete that add-on's `out/` from Windows (Explorer or Git Bash) and build again

## Setup

```sh
scripts/setup.sh
```

- fetches the submodules that aren't checked out yet, and clones what `projects.local` lists and is missing
- puts each one on its `.gitmodules` branch (a fresh submodule is a detached HEAD)
- sets `core.autocrlf=input` and `core.eol=lf` in every checkout: files are LF everywhere
- pulls the toolchain image pinned by `tools/hmod-build` (`toolchain-image.sh`)
- lists the add-ons with their branch and whether they have uncommitted changes

## New add-on

```sh
scripts/new-addon.sh                                   # asks for everything
scripts/new-addon.sh --name "My Addon" --repo new      # private github.com/<owner>/om-my-addon
scripts/new-addon.sh --name "My Addon" --repo https://github.com/<owner>/<repo>.git --cpp
```

`<owner>` is `$GITHUB_OWNER` (default `DefKorns`). Creates `addons/<id>` with the `vendor/OptionsMenu` (`master`) and `vendor/hmod-build` (latest release tag) submodules, a Makefile, `build.sh`, the CI workflow pinned to the same `hmod-build` tag, an uninstall script and a sample **Options Menu → _name_** screen with its own translations. `--cpp` adds a C++ program built against the Options Menu framework.

Nothing is committed: the scaffold is left staged. Commit it, then run the same command again to create/push the GitHub repository and add it to `projects.local`.

An existing add-on (already in `addons/<id>`, or a repository URL whose Makefile uses `hmod-build`) is adopted as is: `scripts/new-addon.sh --id <id>`.

## Bump a shared dependency

```sh
scripts/bump.sh hmod-build           # every repo to the latest hmod-build tag (submodule + workflow)
scripts/bump.sh hmod-build v1.1.0
scripts/bump.sh OptionsMenu          # every add-on's vendor/OptionsMenu to core/OptionsMenu's HEAD
```

Only stages; commit each repository. The toolchain image is pinned by `hmod-build`, so bumping `hmod-build` also moves the toolchain. `bump.sh OptionsMenu` accepts an unpushed core commit, to build the add-ons against local changes; push it before committing the bump, or undo with `git submodule update vendor/OptionsMenu`.

## Export

Every add-on is exported as its own `.hmod`, the same file `make hmod` builds.

Local build, from the `addons/<id>` working copies:

```sh
scripts/export.sh                    # every add-on in addons/
scripts/export.sh om-my-addon        # just these
scripts/export.sh --tagged           # each add-on's latest v* tag instead
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
