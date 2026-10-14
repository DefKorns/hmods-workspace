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
# Prepares the workspace: submodules, the toolchain Docker image, addon status.
#   setup.sh [--vendor DIR] [--rebuild-image]
#   --vendor DIR      console files for toolchain/vendor (default: ../optionsmenu-vendor, else cloned from GitHub)
#   --rebuild-image   rebuild the toolchain image even if it exists
set -euo pipefail
source "$(dirname "$0")/lib.sh"

vendor_dir=""
rebuild=false
while [ $# -gt 0 ]; do
  case "$1" in
    --vendor)
      vendor_dir="$2"
      shift 2
      ;;
    --rebuild-image)
      rebuild=true
      shift
      ;;
    -h | --help)
      sed -n '17,20p' "$0"
      exit 0
      ;;
    *) die "unknown option: $1" ;;
  esac
done

checkTools() {
  local tool
  for tool in git docker; do
    command -v "$tool" >/dev/null || die "$tool not found"
  done
  docker info >/dev/null 2>&1 || die "Docker is not running"
  if ! command -v gh >/dev/null; then
    warn "gh not found: new-addon.sh can't create GitHub repositories"
  elif ! gh auth status >/dev/null 2>&1; then
    warn "gh is not logged in (gh auth login): new-addon.sh can't create GitHub repositories"
  fi
}

initSubmodules() {
  local path
  git -C "$WORKSPACE" config -f .gitmodules --get-regexp '\.path$' | while read -r _ path; do
    [ -z "$(ls -A "$WORKSPACE/$path" 2>/dev/null)" ] || continue
    info "Fetching $path"
    git -C "$WORKSPACE" submodule update --init "$path" || warn "couldn't fetch $path (private repository?)"
  done
}

fetchVendor() {
  local dest="$1"
  if [ -z "$vendor_dir" ] && [ -d "$HMODS_ROOT/optionsmenu-vendor/sdl2-headers" ]; then
    vendor_dir="$HMODS_ROOT/optionsmenu-vendor"
  fi
  if [ -n "$vendor_dir" ]; then
    [ -d "$vendor_dir/sdl2-headers" ] || die "$vendor_dir has no sdl2-headers/"
    info "Copying toolchain vendor files from $vendor_dir"
    mkdir -p "$dest"
    (cd "$vendor_dir" && tar -cf - --exclude=.git .) | (cd "$dest" && tar -xf -)
  else
    command -v gh >/dev/null || die "no vendor files: pass --vendor DIR or install gh"
    info "Cloning $VENDOR_REPO"
    gh repo clone "$VENDOR_REPO" "$dest" -- --depth 1
  fi
}

buildImage() {
  if ! $rebuild && docker image inspect "$IMAGE" >/dev/null 2>&1; then
    info "Toolchain image $IMAGE already built"
    return
  fi
  local toolchain="$WORKSPACE/.cache/toolchain"
  if [ ! -f "$toolchain/Dockerfile.jessie-armhf" ]; then
    info "Cloning the toolchain"
    rm -rf "$toolchain"
    git clone --depth 1 "$TOOLCHAIN_URL" "$toolchain"
  fi
  [ -d "$toolchain/vendor/sdl2-headers" ] || fetchVendor "$toolchain/vendor"
  info "Building $IMAGE (takes a few minutes the first time)"
  docker build -f "$toolchain/Dockerfile.jessie-armhf" -t "$IMAGE" "$toolchain"
}

ignoreLocalDirs() {
  local ignore="$WORKSPACE/.gitignore" entry
  for entry in .cache/ export/; do
    grep -qxF "$entry" "$ignore" 2>/dev/null || printf '%s\n' "$entry" >>"$ignore"
  done
}

addonStatus() {
  local id dir
  info "Addons"
  for id in $(registeredAddons); do
    dir="$(addonDir "$id")"
    if [ -z "$dir" ]; then
      printf '  %-36s not checked out\n' "$id"
    elif [ "$dir" = "$HMODS_ROOT/$id" ]; then
      printf '  %-36s ../%s\n' "$id" "$id"
    else
      printf '  %-36s addons/%s (pinned copy)\n' "$id" "$id"
    fi
  done
}

checkTools
ignoreLocalDirs
initSubmodules
buildImage
addonStatus
info "Done. New addon: scripts/new-addon.sh   Export: scripts/export.sh"
