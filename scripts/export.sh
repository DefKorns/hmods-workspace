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
# Exports each addon as its own .hmod, locally or as a GitHub release.
#
# Local: builds into export/<id>.hmod and records it in export/manifest.tsv
#   export.sh [--pinned] [--zip] [ID...]
#   ID...     addons to export (default: every addon registered in addons/)
#   --pinned  build the commits the workspace pins instead of the addons/<id> working copies
#   --zip     also pack the exported .hmods into export/options-menu-addons-<date>.zip#
# Release: tags the working copy's HEAD and pushes the tag to GitHub, where the
# addon's hmod-build workflow builds the .hmod and publishes the release
#   export.sh --release LEVEL [--bump B] [--remote NAME] [--wait] [--yes] [--dry-run] ID...|--all
#   LEVEL      patch|minor|major  next version: v1.2.3 -> v1.2.4, v2.0.0-rc1 -> v2.0.1
#              alpha|beta|rc      pre-release: v1.2.3 -> v1.2.4-alpha1, v2.0.0-alpha11 -> v2.0.0-alpha12,
#                                 v2.0.0-alpha11 -> v2.0.0-beta1; never back from beta to alpha
#              final              finishes a pre-release: v2.0.0-rc1 -> v2.0.0
#              vX.Y.Z[-rcN]       exactly that tag
#   --bump     patch|minor|major  version a new pre-release cycle starts from (default patch)
#   --remote   remote to push the tag to (default: the first one on github.com)
#   --wait     wait for the release and download its .hmods into export/ (needs gh)
#   --yes      don't ask for confirmation
#   --dry-run  only show what would be tagged
#
#   export.sh --list   show the addons and the folder each one builds from
set -euo pipefail
source "$(dirname "$0")/lib.sh"

pinned=false
zip=false
list=false
all=false
release=""
bump=""
remote=""
wait=false
yes=false
dry=false
ids=()
while [ $# -gt 0 ]; do
  case "$1" in
    --pinned)
      pinned=true
      shift
      ;;
    --zip)
      zip=true
      shift
      ;;
    --list)
      list=true
      shift
      ;;
    --all)
      all=true
      shift
      ;;
    --release)
      release="$2"
      shift 2
      ;;
    --bump)
      bump="$2"
      shift 2
      ;;
    --remote)
      remote="$2"
      shift 2
      ;;
    --wait)
      wait=true
      shift
      ;;
    --yes | -y)
      yes=true
      shift
      ;;
    --dry-run)
      dry=true
      shift
      ;;
    -h | --help)
      sed -n '/^# Exports/,/^set -euo/{/^set -euo/d;p;}' "$0"
      exit 0
      ;;
    -*) die "unknown option: $1" ;;
    *)
      ids+=("$1")
      shift
      ;;
  esac
done

case "$release" in
  "" | patch | minor | major | alpha | beta | rc | final) ;;
  *) printf '%s' "$release" | grep -qE '^v?[0-9]+\.[0-9]+\.[0-9]+(-(alpha|beta|rc)[0-9]+)?$' ||
    die "--release takes patch, minor, major, alpha, beta, rc, final or vX.Y.Z[-alphaN|-betaN|-rcN], not $release" ;;
esac
case "$bump" in
  "" | patch | minor | major) ;;
  *) die "--bump takes patch, minor or major, not $bump" ;;
esac
case "$release" in
  alpha | beta | rc | "") ;;
  *) [ -z "$bump" ] || die "--bump only goes with --release alpha, beta or rc" ;;
esac

exportDir="$WORKSPACE/export"
manifest="$exportDir/manifest.tsv"

# --pinned: a throwaway worktree at the commit the workspace index pins, under .cache/
sourceDir() {
  local dir sha wt
  dir="$(addonDir "$1")"
  if ! $pinned || [ -z "$dir" ]; then
    printf '%s\n' "$dir"
    return 0
  fi
  sha="$(git -C "$WORKSPACE" ls-files -s "addons/$1" | awk '{print $2}')"
  wt="$WORKSPACE/.cache/pinned/$1"
  if [ "$(git -C "$wt" rev-parse HEAD 2>/dev/null)" != "$sha" ]; then
    git -C "$dir" worktree remove --force "$wt" >/dev/null 2>&1 || true
    git -C "$dir" worktree prune
    git -C "$dir" worktree add -q --detach "$wt" "$sha" >&2 || return 0
  fi
  printf '%s\n' "$wt"
}

if [ ${#ids[@]} -eq 0 ]; then
  [ -z "$release" ] || $all || die "--release needs the addon ids, or --all"
  mapfile -t ids < <(registeredAddons)
  [ ${#ids[@]} -gt 0 ] || die "no addons registered in addons/; add one with scripts/new-addon.sh"
fi

if $list; then
  for id in "${ids[@]}"; do
    dir="$(sourceDir "$id")"
    printf '%-36s %s\n' "$id" "${dir:-not checked out}"
  done
  exit 0
fi

addManifestRow() {
  local id="$1" version="$2" commit="$3" hmod="$4" file
  file="$(basename "$hmod")"
  mkdir -p "$exportDir"
  [ -f "$manifest" ] || printf 'id\tversion\tcommit\tfile\tsha256\texported\n' >"$manifest"
  # one row per file: a re-export replaces the previous one
  awk -F'\t' -v f="$file" '$4 != f' "$manifest" >"$manifest.tmp" && mv "$manifest.tmp" "$manifest"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$id" "$version" "$commit" "$file" \
    "$(sha256sum "$hmod" | cut -d' ' -f1)" "$(date -u +'%Y-%m-%d %H:%M UTC')" >>"$manifest"
}

# ---------------------------------------------------------------- release

githubRemote() {
  local dir="$1" name
  if [ -n "$remote" ]; then
    printf '%s\n' "$remote"
    return
  fi
  for name in $(git -C "$dir" remote); do
    if [ -n "$(githubRepo "$(git -C "$dir" remote get-url "$name")")" ]; then
      printf '%s\n' "$name"
      return
    fi
  done
}

preRank() {
  case "$1" in
    alpha) echo 1 ;;
    beta) echo 2 ;;
    rc) echo 3 ;;
    *) echo 0 ;;
  esac
}

# prints the tag after $1, or the reason it can't and fails
nextVersion() {
  local latest="$1" core pre="" channel number major minor patch
  case "$release" in
    v[0-9]* | [0-9]*)
      printf 'v%s\n' "${release#v}"
      return
      ;;
  esac
  core="${latest#v}"
  case "$core" in
    *-*)
      pre="${core#*-}"
      core="${core%%-*}"
      ;;
  esac
  IFS=. read -r major minor patch <<<"$core"
  # alpha14, rc.2 or older forms such as b23
  channel="$(printf '%s' "$pre" | sed -E 's/^([a-z]*).*/\1/')"
  number="$(printf '%s' "$pre" | sed -E 's/^[a-z]*\.?([0-9]*).*/\1/')"

  bumped() {
    case "$1" in
      patch) printf '%s.%s.%s' "$major" "$minor" "$((patch + 1))" ;;
      minor) printf '%s.%s.0' "$major" "$((minor + 1))" ;;
      major) printf '%s.0.0' "$((major + 1))" ;;
    esac
  }

  case "$release" in
    patch | minor | major) printf 'v%s\n' "$(bumped "$release")" ;;
    final)
      [ -n "$pre" ] || {
        echo "$latest is not a pre-release"
        return 1
      }
      printf 'v%s\n' "$core"
      ;;
    alpha | beta | rc)
      if [ -z "$pre" ] || [ -n "$bump" ]; then
        printf 'v%s-%s1\n' "$(bumped "${bump:-patch}")" "$release"
      elif [ "$channel" = "$release" ]; then
        printf 'v%s-%s%s\n' "$core" "$release" "$((${number:-0} + 1))"
      elif [ "$(preRank "$release")" -gt "$(preRank "$channel")" ]; then
        printf 'v%s-%s1\n' "$core" "$release"
      else
        echo "$latest is already past $release (use --bump to start a new cycle)"
        return 1
      fi
      ;;
  esac
}

# fills plan_* for one addon, or prints why it can't be released and fails
planRelease() {
  local id="$1" dir="$2" rname url latest tag current
  git -C "$dir" rev-parse -q --verify HEAD >/dev/null || {
    warn "$id: no commit yet"
    return 1
  }
  # submodule content is ignored: CI builds the pinned commits, and a Git for Windows
  # checkout read from WSL shows line-ending noise there
  [ -z "$(git -C "$dir" status --porcelain --untracked-files=no --ignore-submodules=dirty)" ] || {
    warn "$id: uncommitted changes"
    return 1
  }
  grep -qs 'hmod-build/.github/workflows/hmod.yml' "$dir"/.github/workflows/*.yml ||
    {
      warn "$id: no hmod-build release workflow in .github/workflows"
      return 1
    }
  rname="$(githubRemote "$dir")"
  [ -n "$rname" ] || {
    warn "$id: no github.com remote (use --remote)"
    return 1
  }
  url="$(git -C "$dir" remote get-url "$rname")"
  git -C "$dir" fetch -q --tags "$rname" || {
    warn "$id: couldn't fetch $rname"
    return 1
  }
  git -C "$dir" branch -r --contains HEAD | grep -q "^ *$rname/" ||
    {
      warn "$id: HEAD isn't on $rname yet, push the branch first"
      return 1
    }
  current="$(git -C "$dir" tag --points-at HEAD --list 'v[0-9]*' | head -n 1)"
  [ -z "$current" ] || {
    warn "$id: HEAD is already released as $current"
    return 1
  }
  latest="$(git -C "$dir" describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || echo v0.0.0)"
  tag="$(nextVersion "$latest")" || {
    warn "$id: $tag"
    return 1
  }
  git -C "$dir" rev-parse -q --verify "refs/tags/$tag" >/dev/null && {
    warn "$id: tag $tag already exists"
    return 1
  }
  plan_ids+=("$id")
  plan_dirs+=("$dir")
  plan_remotes+=("$rname")
  plan_repos+=("$(githubRepo "$url")")
  plan_tags+=("$tag")
  printf '  %-34s %-15s -> %-15s %s (%s)\n' "$id" "$latest" "$tag" "$rname" "$url"
}

waitForRelease() {
  local id="$1" repo="$2" tag="$3" deadline hmod
  [ -n "$repo" ] || {
    warn "$id: can't tell the GitHub repository, not waiting"
    return 1
  }
  info "$id: waiting for the $tag release (Ctrl+C stops waiting, the release still happens)"
  deadline=$((SECONDS + 1200))
  until gh release view "$tag" -R "$repo" --json assets -q '.assets[].name' 2>/dev/null | grep -q '\.hmod$'; do
    [ $SECONDS -lt $deadline ] || {
      warn "$id: no release after 20 minutes, see https://github.com/$repo/actions"
      return 1
    }
    sleep 20
  done
  mkdir -p "$exportDir"
  gh release download "$tag" -R "$repo" -p '*.hmod' -D "$exportDir" --clobber
  for hmod in $(gh release view "$tag" -R "$repo" --json assets -q '.assets[].name' | grep '\.hmod$'); do
    addManifestRow "$id" "${tag#v}" "$tag" "$exportDir/$hmod"
    exported+=("$hmod")
  done
}

doRelease() {
  $pinned && die "--release tags the working copies, it can't be combined with --pinned"
  plan_ids=() plan_dirs=() plan_remotes=() plan_repos=() plan_tags=()
  failed=()
  info "Release plan"
  for id in "${ids[@]}"; do
    dir="$(addonDir "$id")"
    if [ -z "$dir" ]; then
      warn "$id: addons/$id is not checked out"
      failed+=("$id")
      continue
    fi
    planRelease "$id" "$dir" || failed+=("$id")
  done
  [ ${#plan_ids[@]} -gt 0 ] || die "nothing to release"
  $dry && exit 0
  if ! $yes; then
    [ -t 0 ] || die "not a terminal: pass --yes to tag and push without asking"
    read -r -p "Tag and push these? Each pushed tag publishes a GitHub release. [y/N] " answer
    case "$answer" in y* | Y*) ;; *) die "cancelled, nothing tagged" ;; esac
  fi
  if $wait && ! command -v gh >/dev/null; then
    warn "gh not found, not waiting for the releases"
    wait=false
  fi
  exported=()
  local i
  for i in "${!plan_ids[@]}"; do
    info "${plan_ids[$i]}: ${plan_tags[$i]}"
    git -C "${plan_dirs[$i]}" tag -a "${plan_tags[$i]}" -m "${plan_tags[$i]}"
    if ! git -C "${plan_dirs[$i]}" push "${plan_remotes[$i]}" "refs/tags/${plan_tags[$i]}"; then
      git -C "${plan_dirs[$i]}" tag -d "${plan_tags[$i]}" >/dev/null
      warn "${plan_ids[$i]}: push failed, local tag removed"
      failed+=("${plan_ids[$i]}")
      continue
    fi
    [ -z "${plan_repos[$i]}" ] || printf '  https://github.com/%s/releases/tag/%s\n' "${plan_repos[$i]}" "${plan_tags[$i]}"
  done
  if $wait; then
    for i in "${!plan_ids[@]}"; do
      waitForRelease "${plan_ids[$i]}" "${plan_repos[$i]}" "${plan_tags[$i]}" || failed+=("${plan_ids[$i]}")
    done
    info "Downloaded to export/: ${exported[*]:-nothing}"
  fi
  if [ ${#failed[@]} -gt 0 ]; then
    warn "not released: ${failed[*]}"
    exit 1
  fi
}

[ -z "$release" ] || {
  doRelease
  exit 0
}

# ---------------------------------------------------------------- local

requireDocker

# fetches only missing submodules, so a submodule moved on purpose isn't reset
initSubmodules() {
  local dir="$1" path
  [ -f "$dir/.gitmodules" ] || return 0
  while read -r _ path; do
    [ -n "$(ls -A "$dir/$path" 2>/dev/null)" ] || git -C "$dir" submodule update --init --recursive "$path" || return 1
  done < <(git -C "$dir" config -f .gitmodules --get-regexp '\.path$')
}

usesHmodBuild() {
  grep -q 'hmod-build/hmod.mk' "$1/Makefile"
}

failed=()
exported=()
for id in "${ids[@]}"; do
  dir="$(sourceDir "$id")"
  if [ -z "$dir" ]; then
    warn "$id: not checked out, skipped"
    failed+=("$id")
    continue
  fi
  info "$id ($dir)"
  if ! initSubmodules "$dir"; then
    warn "$id: couldn't fetch its submodules"
    failed+=("$id")
    continue
  fi
  if ! rm -f "$dir"/out/*.hmod; then
    warn "$id: can't remove the previous out/*.hmod (made by a root container? delete out/ by hand)"
    failed+=("$id")
    continue
  fi
  # older addons predate hmod-build: their default target makes the .hmod
  target=""
  usesHmodBuild "$dir" && target=hmod
  built=true
  dockerMake "$dir" $target || built=false
  # framework objects would leave the vendor submodule dirty
  find "$dir/vendor" -name '*.o' -type f -delete 2>/dev/null || true
  if ! $built || ! ls "$dir"/out/*.hmod >/dev/null 2>&1; then
    warn "$id: build failed"
    failed+=("$id")
    continue
  fi
  if usesHmodBuild "$dir"; then
    version="$(dockerMake "$dir" -s hmod-version | tail -n 1)"
  else
    version="$(git -C "$dir" describe --tags --match 'v[0-9]*' 2>/dev/null | sed 's/^v//' || true)"
  fi
  commit="$(git -C "$dir" describe --always --dirty=.dirty 2>/dev/null || echo uncommitted)"
  for hmod in "$dir"/out/*.hmod; do
    cp "$hmod" "$exportDir/" 2>/dev/null || {
      mkdir -p "$exportDir"
      cp "$hmod" "$exportDir/"
    }
    addManifestRow "$id" "${version:-unknown}" "$commit" "$hmod"
    exported+=("$(basename "$hmod")")
  done
done

if $zip && [ ${#exported[@]} -gt 0 ]; then
  bundle="options-menu-addons-$(date +%Y%m%d).zip"
  rm -f "$exportDir/$bundle"
  if command -v zip >/dev/null; then
    (cd "$exportDir" && zip -q "$bundle" "${exported[@]}" manifest.tsv)
  elif command -v powershell.exe >/dev/null; then
    (cd "$exportDir" && powershell.exe -NoProfile -Command \
      "Compress-Archive -Path $(printf "'%s'," "${exported[@]}")'manifest.tsv' -DestinationPath '$bundle'")
  else
    warn "neither zip nor PowerShell found, no zip made"
  fi
  [ -f "$exportDir/$bundle" ] && info "Bundle: export/$bundle"
fi

info "Exported to export/: ${exported[*]:-nothing}"
if [ ${#failed[@]} -gt 0 ]; then
  warn "failed: ${failed[*]}"
  exit 1
fi
