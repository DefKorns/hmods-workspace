#!/usr/bin/env bash
set -euo pipefail

# stops Git Bash from mangling the /src path below into a Windows path
export MSYS_NO_PATHCONV=1

IMAGE="classicmini-cross-toolchain:jessie-armhf"

for sub in hmod-build toolchain vendor/OptionsMenu; do
  [ -n "$(ls -A "$sub" 2>/dev/null)" ] || git submodule update --init --recursive "$sub"
done

if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
  if [ ! -d toolchain/vendor ]; then
    echo "toolchain/vendor is missing: copy the console files there (see toolchain/README.md) or run hmods-workspace/scripts/setup.sh" >&2
    exit 1
  fi
  echo "==> Building Docker image..."
  docker build -f toolchain/Dockerfile.jessie-armhf -t "$IMAGE" toolchain
fi

src="$PWD"
command -v cygpath >/dev/null && src="$(cygpath -m "$PWD")"

echo "==> Running make inside the container..."
docker run --rm -v "$src:/src" -w /src "$IMAGE" \
  sh -c "git config --global --add safe.directory '*' 2>/dev/null; make CROSS_PREFIX=arm-linux-gnueabihf- $*"

# framework objects would leave the vendor submodule dirty
find vendor -name '*.o' -type f -delete

ls -la out/*.hmod 2>/dev/null
