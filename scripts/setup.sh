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
# Prepares the workspace: submodules on their branches, the repositories
# listed in projects.local, LF line endings, pre-commit hooks, the toolchain
# Docker image, addon status.
#   setup.sh
set -euo pipefail
source "$(dirname "$0")/lib.sh"

case "${1:-}" in
  "") ;;
  -h | --help)
    sed -n '17,20p' "$0"
    exit 0
    ;;
  *) die "unknown option: $1" ;;
esac

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

# every checkout stores and writes LF, whatever the global/system autocrlf says
forceLf() {
  git -C "$WORKSPACE" config core.autocrlf input
  git -C "$WORKSPACE" config core.eol lf
  git -C "$WORKSPACE" submodule foreach -q --recursive 'git config core.autocrlf input; git config core.eol lf'
  local path
  while read -r path _; do
    [ -e "$WORKSPACE/$path/.git" ] || continue
    git -C "$WORKSPACE/$path" config core.autocrlf input
    git -C "$WORKSPACE/$path" config core.eol lf
    git -C "$WORKSPACE/$path" submodule foreach -q --recursive 'git config core.autocrlf input; git config core.eol lf'
  done < <(localProjects; for id in $(addonIds); do echo "addons/$id"; done)
}

initSubmodules() {
  local path
  git -C "$WORKSPACE" config -f .gitmodules --get-regexp '\.path$' | while read -r _ path; do
    [ -z "$(ls -A "$WORKSPACE/$path" 2>/dev/null)" ] || continue
    info "Fetching $path"
    git -C "$WORKSPACE" -c core.autocrlf=input submodule update --init --recursive "$path" ||
      warn "couldn't fetch $path (private repository?)"
  done
}

# clones what projects.local lists and isn't there yet; existing folders are left alone
cloneProjects() {
  local path url branch
  while read -r path url branch; do
    [ ! -e "$WORKSPACE/$path" ] || continue
    info "Cloning $path"
    if git -c core.autocrlf=input clone -q ${branch:+-b "$branch"} "$url" "$WORKSPACE/$path"; then
      git -C "$WORKSPACE/$path" -c core.autocrlf=input submodule update -q --init --recursive ||
        warn "$path: couldn't fetch its submodules"
    else
      warn "couldn't clone $path from $url"
    fi
  done < <(localProjects)
}

# a fresh submodule is a detached HEAD: put it on its .gitmodules branch to work on it
checkoutBranches() {
  local path branch dir
  git -C "$WORKSPACE" config -f .gitmodules --get-regexp '\.branch$' | while read -r key branch; do
    path="$(git -C "$WORKSPACE" config -f .gitmodules "${key%.branch}.path")"
    dir="$WORKSPACE/$path"
    [ -e "$dir/.git" ] || continue
    [ -z "$(git -C "$dir" branch --show-current)" ] || continue
    if git -C "$dir" rev-parse -q --verify "refs/heads/$branch" >/dev/null; then
      git -C "$dir" switch -q "$branch"
    elif git -C "$dir" rev-parse -q --verify "refs/remotes/origin/$branch" >/dev/null; then
      git -C "$dir" switch -q -c "$branch" --track "origin/$branch"
    else
      warn "$path: branch $branch not found, left detached"
      continue
    fi
    info "$path on $branch"
  done
}

setupHooks() {
  local -a dirs=("$WORKSPACE")
  local path
  while read -r _ path; do dirs+=("$WORKSPACE/$path"); done < <(git -C "$WORKSPACE" config -f .gitmodules --get-regexp '\.path$')
  while read -r path _; do dirs+=("$WORKSPACE/$path"); done < <(localProjects)
  installHooks "${dirs[@]}"
}

ignoreLocalDirs() {
  local ignore="$WORKSPACE/.gitignore" entry
  for entry in .cache/ export/; do
    grep -qxF "$entry" "$ignore" 2>/dev/null || printf '%s\n' "$entry" >>"$ignore"
  done
}

addonStatus() {
  local id dir branch dirty
  info "Addons"
  for id in $(addonIds); do
    dir="$(addonDir "$id")"
    if [ -z "$dir" ]; then
      printf '  %-36s not checked out\n' "$id"
      continue
    fi
    branch="$(git -C "$dir" branch --show-current)"
    dirty=""
    [ -z "$(git -C "$dir" status --porcelain --ignore-submodules=dirty)" ] || dirty=", uncommitted changes"
    printf '  %-36s %s%s\n' "$id" "${branch:-detached}" "$dirty"
  done
}

checkTools
ignoreLocalDirs
initSubmodules
cloneProjects
forceLf
checkoutBranches
setupHooks
requireDocker
info "Toolchain image: $IMAGE"
addonStatus
info "Done. New addon: scripts/new-addon.sh   Export: scripts/export.sh   Bump: scripts/bump.sh"
