#!/usr/bin/env bash
#  Copyright (C) 2026 DefKorns (https://defkorns.github.io/LICENSE)
#
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <https://www.gnu.org/licenses/>.
#
# Moves a shared dependency to a new version in core/OptionsMenu and every addon.
# Only stages: commit each repository yourself.
#   bump.sh hmod-build [TAG]      vendor/hmod-build + the workflow's hmod.yml@TAG
#                                 (default: latest v* tag of tools/hmod-build)
#   bump.sh OptionsMenu [COMMIT]  the addons' vendor/OptionsMenu
#                                 (default: core/OptionsMenu HEAD, even unpushed, to
#                                 build addons against local changes; undo with
#                                 git submodule update vendor/OptionsMenu)
set -euo pipefail
source "$(dirname "$0")/lib.sh"

dep="${1:-}"
ref="${2:-}"
case "$dep" in
  hmod-build | OptionsMenu) ;;
  -h | --help)
    sed -n '17,24p' "$0"
    exit 0
    ;;
  *) die "usage: bump.sh hmod-build [TAG] | OptionsMenu [COMMIT]" ;;
esac

repos() {
  printf '%s\n' "$CORE_DIR"
  local id
  for id in $(registeredAddons); do addonDir "$id"; done
}

bumpHmodBuild() {
  local dir="$1" wf
  [ -e "$dir/vendor/hmod-build/.git" ] || return 0
  git -C "$dir/vendor/hmod-build" fetch -q --tags origin
  git -C "$dir/vendor/hmod-build" checkout -q "$ref"
  git -C "$dir" add vendor/hmod-build
  for wf in "$dir"/.github/workflows/*.yml; do
    [ -f "$wf" ] && grep -q 'hmod-build/.github/workflows/hmod.yml@' "$wf" || continue
    sed -i "s#\(hmod-build/.github/workflows/hmod.yml@\)[^[:space:]]*#\1$ref#" "$wf"
    git -C "$dir" add "${wf#"$dir"/}"
  done
  echo yes
}

bumpOptionsMenu() {
  local dir="$1"
  [ -e "$dir/vendor/OptionsMenu/.git" ] || return 0
  git -C "$dir/vendor/OptionsMenu" fetch -q "$CORE_DIR" "$ref"
  git -C "$dir/vendor/OptionsMenu" checkout -q "$ref"
  git -C "$dir/vendor/OptionsMenu" submodule update -q --init --recursive
  git -C "$dir" add vendor/OptionsMenu
  echo yes
}

if [ "$dep" = hmod-build ]; then
  git -C "$HMOD_BUILD_DIR" fetch -q --tags origin
  [ -n "$ref" ] || ref="$(hmodBuildTag)"
  [ -n "$ref" ] || die "tools/hmod-build has no v* tag"
  git -C "$HMOD_BUILD_DIR" rev-parse -q --verify "refs/tags/$ref" >/dev/null || die "hmod-build has no tag $ref"
  msg="Update hmod-build to $ref"
else
  [ -n "$ref" ] || ref="$(git -C "$CORE_DIR" rev-parse HEAD)"
  ref="$(git -C "$CORE_DIR" rev-parse --verify "$ref^{commit}")" || die "core/OptionsMenu has no commit $ref"
  git -C "$CORE_DIR" branch -r --contains "$ref" | grep -q . ||
    warn "$(git -C "$CORE_DIR" rev-parse --short "$ref") isn't pushed: fine for a local build, push it before committing the bump"
  msg="Update the Options Menu submodule"
fi

info "Bumping $dep to $ref"
for dir in $(repos); do
  name="${dir#"$WORKSPACE"/}"
  if [ "$dep" = hmod-build ]; then changed="$(bumpHmodBuild "$dir")"; else changed="$(bumpOptionsMenu "$dir")"; fi
  [ -n "$changed" ] || continue
  if git -C "$dir" diff --cached --quiet; then
    printf '  %-44s already there\n' "$name"
  else
    printf '  %-44s staged\n' "$name"
  fi
done
info "Nothing committed. Suggested message: $msg"
