#!/usr/bin/env bash
set -euo pipefail

# stops Git Bash from mangling the /src path below into a Windows path
export MSYS_NO_PATHCONV=1

for sub in vendor/hmod-build vendor/OptionsMenu; do
  [ -n "$(ls -A "$sub" 2>/dev/null)" ] || git submodule update --init --recursive "$sub"
done

echo "==> Getting the toolchain image..."
IMAGE=$(sh vendor/hmod-build/toolchain-image.sh)

src="$PWD"
command -v cygpath >/dev/null && src="$(cygpath -m "$PWD")"

# on Linux/WSL, files a root container writes stay root-owned and can't be removed later
user=()
[ "$(uname -s)" = Linux ] && user=(--user "$(id -u):$(id -g)" -e HOME=/tmp)

echo "==> Running make inside the container..."
docker run --rm "${user[@]}" -v "$src:/src" -w /src "$IMAGE" \
  sh -c "git config --global --add safe.directory '*' 2>/dev/null; make CROSS_PREFIX=arm-linux-gnueabihf- $*"

# framework objects would leave the vendor submodule dirty
find vendor -name '*.o' -type f -delete

ls -la out/*.hmod 2>/dev/null
