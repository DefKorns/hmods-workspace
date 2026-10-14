# shellcheck shell=bash disable=SC2034
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

# stops Git Bash from mangling container paths like /src into Windows paths
export MSYS_NO_PATHCONV=1

# E:/... form under Git Bash: with path conversion off, native tools can't read /e/...
WORKSPACE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && { pwd -W 2>/dev/null || pwd; })"
HMODS_ROOT="${HMODS_ROOT:-$(dirname "$WORKSPACE")}"
GITHUB_OWNER="${GITHUB_OWNER:-DefKorns}"
IMAGE="classicmini-cross-toolchain:jessie-armhf"
CORE_URL="https://github.com/DefKorns/OptionsMenu"
CORE_BRANCH="modern-ui-ttf"
TOOLCHAIN_URL="https://github.com/DefKorns/classicmini-cross-toolchain.git"
HMOD_BUILD_URL="https://github.com/DefKorns/hmod-build.git"
VENDOR_REPO="DefKorns/optionsmenu-vendor"

info() { printf '==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

hostPath() {
  if command -v cygpath >/dev/null; then cygpath -m "$1"; else printf '%s\n' "$1"; fi
}

# runs make in the toolchain image, with $1 mounted as the working directory
dockerMake() {
  local dir="$1"
  shift
  docker run --rm -v "$(hostPath "$dir"):/src" -w /src "$IMAGE" \
    sh -c "git config --global --add safe.directory '*' 2>/dev/null; make CROSS_PREFIX=arm-linux-gnueabihf- $*"
}

# owner/repo of a github.com remote URL, empty for any other host
githubRepo() {
  printf '%s\n' "$1" | sed -nE 's#^(https://|git@|ssh://git@)github\.com[:/]([^/]+/[^/]+)$#\2#p' | sed 's/\.git$//'
}

requireDocker() {
  command -v docker >/dev/null || die "docker not found"
  docker info >/dev/null 2>&1 || die "Docker is not running"
  docker image inspect "$IMAGE" >/dev/null 2>&1 || die "image $IMAGE missing, run scripts/setup.sh"
}

# addon ids registered as workspace submodules under addons/
registeredAddons() {
  git -C "$WORKSPACE" config -f .gitmodules --get-regexp '^submodule\.addons/.*\.path$' 2>/dev/null |
    awk '{ sub(/^addons\//, "", $2); print $2 }'
}

# working copy next to the workspace, else the workspace's own checkout
addonDir() {
  if [ -f "$HMODS_ROOT/$1/Makefile" ]; then
    printf '%s\n' "$HMODS_ROOT/$1"
  elif [ -f "$WORKSPACE/addons/$1/Makefile" ]; then
    printf '%s\n' "$WORKSPACE/addons/$1"
  fi
}
