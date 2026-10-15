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
GITHUB_OWNER="${GITHUB_OWNER:-DefKorns}"
CORE_DIR="$WORKSPACE/core/OptionsMenu"
CORE_URL="https://github.com/DefKorns/OptionsMenu"
CORE_BRANCH="modern-ui-ttf"
HMOD_BUILD_DIR="$WORKSPACE/tools/hmod-build"
HMOD_BUILD_URL="https://github.com/DefKorns/hmod-build.git"
IMAGE=""

info() { printf '==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

hostPath() {
  if command -v cygpath >/dev/null; then cygpath -m "$1"; else printf '%s\n' "$1"; fi
}

# on Linux/WSL, files a root container writes stay root-owned and can't be removed later
dockerUser() {
  [ "$(uname -s)" = Linux ] && printf '%s\n' --user "$(id -u):$(id -g)" -e HOME=/tmp
  return 0
}

# runs make in the toolchain image in $1, which must be inside the workspace;
# the whole workspace is mounted so a submodule's ../../.git/modules gitdir resolves
dockerMake() {
  local dir rel
  dir="$(cd "$1" && { pwd -W 2>/dev/null || pwd; })"
  shift
  rel="${dir#"$WORKSPACE"}"
  [ "$rel" != "$dir" ] || die "$dir is outside the workspace"
  # shellcheck disable=SC2046
  docker run --rm $(dockerUser) -v "$(hostPath "$WORKSPACE"):/ws" -w "/ws$rel" "$IMAGE" \
    sh -c "git config --global --add safe.directory '*' 2>/dev/null; make CROSS_PREFIX=arm-linux-gnueabihf- $*"
}

# owner/repo of a github.com remote URL, empty for any other host
githubRepo() {
  printf '%s\n' "$1" | sed -nE 's#^(https://|git@|ssh://git@)github\.com[:/]([^/]+/[^/]+)$#\2#p' | sed 's/\.git$//'
}

# sets IMAGE to the toolchain image pinned by tools/hmod-build, pulling it when missing
requireDocker() {
  command -v docker >/dev/null || die "docker not found"
  docker info >/dev/null 2>&1 || die "Docker is not running"
  [ -f "$HMOD_BUILD_DIR/toolchain-image.sh" ] || die "tools/hmod-build is missing, run scripts/setup.sh"
  IMAGE="$(sh "$HMOD_BUILD_DIR/toolchain-image.sh")" || die "couldn't get the toolchain image"
}

# addon ids registered as workspace submodules under addons/
registeredAddons() {
  git -C "$WORKSPACE" config -f .gitmodules --get-regexp '^submodule\.addons/.*\.path$' 2>/dev/null |
    awk '{ sub(/^addons\//, "", $2); print $2 }'
}

addonDir() {
  [ -f "$WORKSPACE/addons/$1/Makefile" ] && printf '%s\n' "$WORKSPACE/addons/$1"
  return 0
}

# latest v* tag of tools/hmod-build: the release new and bumped addons use
hmodBuildTag() {
  git -C "$HMOD_BUILD_DIR" describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null
}
