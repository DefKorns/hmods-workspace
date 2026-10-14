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
# Creates an addon next to the workspace (../<id>) and registers it in addons/.
#   new-addon.sh [--name NAME] [--id ID] [--repo new|local|URL] [--public] [--cpp]
#   --name    shown name, e.g. "Favorites" (hmod name: "Options Menu - Favorites")
#   --id      repository and hmod id (default: om-<name>)
#   --repo    new: create github.com/<owner>/<id> with gh; URL: use that repository
#             (scaffolded if empty, adopted as is if it already has a Makefile);
#             local: no remote and no workspace registration
#   --public  public GitHub repository (default private)
#   --cpp     C++ addon built against the Options Menu framework (default: shell only)
# Missing values are asked for. Nothing is committed: a new scaffold is only staged.
# Commit it, then run the same command again to publish and register it.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

name=""
id=""
repo=""
visibility="--private"
cpp=""
while [ $# -gt 0 ]; do
  case "$1" in
    --name)
      name="$2"
      shift 2
      ;;
    --id)
      id="$2"
      shift 2
      ;;
    --repo)
      repo="$2"
      shift 2
      ;;
    --public)
      visibility="--public"
      shift
      ;;
    --cpp)
      cpp=true
      shift
      ;;
    -h | --help)
      sed -n '17,27p' "$0"
      exit 0
      ;;
    *) die "unknown option: $1" ;;
  esac
done

ask() {
  local prompt="$1" default="$2" answer
  [ -t 0 ] || {
    printf '%s\n' "$default"
    return
  }
  read -r -p "$prompt${default:+ [$default]}: " answer
  printf '%s\n' "${answer:-$default}"
}

slug() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+|-+$//g'
}

sedEscape() {
  printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'
}

# copies template dir $1 into $dest, filling the @PLACEHOLDERS@ in names and contents
fillTemplate() {
  local src="$1" rel target
  local -a subst=(
    -e "s|@ID@|$(sedEscape "$id")|g"
    -e "s|@DIR@|$(sedEscape "$id")|g"
    -e "s|@NAME@|$(sedEscape "$name")|g"
    -e "s|@KEY@|$key|g"
    -e "s|@CMD@|$cmd|g"
    -e "s|@BIN@|$short|g"
    -e "s|@YEAR@|$(date +%Y)|g"
    -e "s|@HMOD_BUILD_SHA@|$hmod_build_sha|g"
    -e "s|@DOCKER@|$cpp|g"
  )
  (cd "$src" && find . -type f) | while read -r rel; do
    target="$dest/$(printf '%s' "${rel#./}" | sed "${subst[@]}")"
    mkdir -p "$(dirname "$target")"
    sed "${subst[@]}" "$src/$rel" >"$target"
  done
}

scaffold() {
  [ -n "$name" ] || name="$(ask "Addon name" "")"
  [ -n "$name" ] || die "an addon name is required (--name)"
  [ -n "$cpp" ] || case "$(ask "C++ addon? (y/n)" "n")" in y* | Y*) cpp=true ;; *) cpp=false ;; esac
  short="${id#om-}"
  short="${short#om_}"
  key="$(printf '%s' "$short" | tr '[:lower:]' '[:upper:]' | sed -E 's/[^A-Z0-9]+/_/g')"
  cmd="$(printf '%s' "$name" | sed -E 's/[^A-Za-z0-9]+//g')"

  # first, so .gitmodules is already covered by eol=lf
  cp "$WORKSPACE/template/common/.gitattributes" "$dest/.gitattributes"

  info "Adding submodules"
  git -C "$dest" submodule add -q -b "$CORE_BRANCH" "$CORE_URL" vendor/OptionsMenu
  git -C "$dest" submodule add -q "$TOOLCHAIN_URL" toolchain
  git -C "$dest" submodule add -q "$HMOD_BUILD_URL" hmod-build
  hmod_build_sha="$(git -C "$dest/hmod-build" rev-parse HEAD)"

  info "Writing the $($cpp && echo C++ || echo shell) template"
  fillTemplate "$WORKSPACE/template/common"
  if $cpp; then
    fillTemplate "$WORKSPACE/template/cpp"
    rm -rf "$dest/mod/etc/options_menu/$id/scripts"
  fi
  cp "$dest/vendor/OptionsMenu/LICENSE" "$dest/LICENSE"

  git -C "$dest" add -A
  local exe
  for exe in build.sh mod/uninstall $(cd "$dest" && find mod -name '*.sh'); do
    git -C "$dest" update-index --chmod=+x "$exe"
  done

  info "Scaffold staged in $dest (nothing committed)"
  printf '  suggested commit message: Initial add-on scaffold\n'
  if [ "$repo" = local ]; then
    printf '  then: cd ../%s && ./build.sh\n' "$id"
  else
    printf '  after committing, publish and register it with: scripts/new-addon.sh --id %s --repo %s\n' "$id" "$repo"
  fi
}

isAddon() {
  [ -f "$1/Makefile" ] && grep -q 'hmod-build/hmod.mk' "$1/Makefile"
}

# pushes a committed addon, creating its GitHub repository first when asked
publish() {
  git -C "$dest" rev-parse -q --verify HEAD >/dev/null || die "$dest has no commit yet: commit the staged scaffold first"
  url="$(git -C "$dest" remote get-url origin 2>/dev/null || true)"
  if [ -z "$url" ]; then
    case "$repo" in
      local | "") return ;;
      new)
        command -v gh >/dev/null || die "gh not found: create the repository yourself and rerun with --repo URL"
        info "Creating github.com/$GITHUB_OWNER/$id ($visibility)"
        gh repo create "$GITHUB_OWNER/$id" "$visibility" --source "$dest" --remote origin --push
        url="https://github.com/$GITHUB_OWNER/$id.git"
        return
        ;;
      *)
        git -C "$dest" remote add origin "$repo"
        url="$repo"
        ;;
    esac
  fi
  if ! git -C "$dest" rev-parse -q --verify '@{upstream}' >/dev/null 2>&1; then
    info "Pushing to $url"
    git -C "$dest" push -u origin HEAD
  fi
}

registerSubmodule() {
  if [ -z "$url" ]; then
    warn "no remote, so not registered in the workspace; once it has one, rerun with --repo new or --repo URL"
    return
  fi
  if registeredAddons | grep -qxF "$id"; then
    info "addons/$id already registered"
    return
  fi
  # the workspace CI clones anonymously, so a github.com remote is registered by its https URL
  local name repoPath branch
  for name in $(git -C "$dest" remote); do
    repoPath="$(githubRepo "$(git -C "$dest" remote get-url "$name")")"
    [ -z "$repoPath" ] || {
      url="https://github.com/$repoPath.git"
      break
    }
  done
  branch="$(git -C "$dest" branch --show-current)"
  info "Registering addons/$id in the workspace ($url${branch:+, $branch})"
  if [ -n "$branch" ] && git ls-remote --exit-code --heads "$url" "$branch" >/dev/null 2>&1; then
    git -C "$WORKSPACE" submodule add -q -b "$branch" "$url" "addons/$id"
  else
    git -C "$WORKSPACE" submodule add -q "$url" "addons/$id"
  fi
}

# adds ../<id> to the VS Code workspace, before the hmods-workspace folder entry
addToCodeWorkspace() {
  local file="$WORKSPACE/hmods-workspace.code-workspace"
  [ -f "$file" ] || return 0
  grep -qF "\"path\": \"../$id\"" "$file" && return 0
  awk -v id="$id" '
    held != "" && /"name": "hmods-workspace"/ {
      indent = held; sub(/[^ ].*/, "", indent)
      printf "%s{\n%s    \"name\": \"%s\",\n%s    \"path\": \"../%s\"\n%s},\n", indent, indent, id, indent, id, indent
    }
    held != "" { print held }
    { held = $0 }
    END { print held }
  ' "$file" >"$file.tmp" && mv "$file.tmp" "$file"
}

[ -n "$id" ] || {
  [ -n "$name" ] || name="$(ask "Addon name" "")"
  [ -n "$name" ] || die "an addon name or --id is required"
  id="$(ask "Repository id" "om-$(slug "$name")")"
}
printf '%s' "$id" | grep -qE '^[A-Za-z0-9][A-Za-z0-9_.-]*$' || die "invalid id: $id"
dest="$HMODS_ROOT/$id"
url=""

if [ ! -e "$dest" ]; then
  [ -n "$repo" ] || repo="$(ask "GitHub repository: new, local or an existing URL" "new")"
  case "$repo" in
    new | local)
      info "Creating $dest"
      git init -q -b master "$dest"
      ;;
    *)
      info "Cloning $repo"
      git clone -q "$repo" "$dest"
      ;;
  esac
  if ! isAddon "$dest"; then
    scaffold
    addToCodeWorkspace
    exit 0
  fi
  info "$repo is already an addon, adopting it"
elif [ ! -d "$dest/.git" ]; then
  die "$dest exists and is not a git repository"
fi

publish
registerSubmodule
addToCodeWorkspace
info "Done: $dest"
[ -z "$url" ] || printf '  addons/%s is staged in the workspace; suggested commit message: Add %s addon\n' "$id" "$id"
