#!/usr/bin/env bash
#
# Build Syncthing .spk packages for the Synology devices in this household:
#   - silos     : DS213j (armada370, DSM 6.x max)
#   - twardziel : DS216j (armada38x, supports DSM 6 and 7)
#
# The actual compilation runs inside a Docker container built from ./Dockerfile,
# so nothing is installed on the host. Resulting .spk files land in ./output/.
#
# Usage: ./run.sh

set -euo pipefail

cd "$(dirname "$0")"

IMAGE="synology-syncthing-builder"
OUTPUT_DIR="$PWD/output"

echo "==> Building Docker image: $IMAGE"
docker build --platform=linux/amd64 -t "$IMAGE" .

mkdir -p "$OUTPUT_DIR"

echo "==> Compiling Syncthing .spk packages inside container"
docker run --rm \
  --platform=linux/amd64 \
  -v "$OUTPUT_DIR:/output" \
  "$IMAGE" \
  bash -eu -o pipefail -c '
    cd /spksrc/spk/syncthing

    # DS213j / armada370 — DSM 6.x is the highest this device supports.
    echo "---- arch-armada370-6.1 (DS213j) ----"
    make arch-armada370-6.1

    # DS216j / armada38x — DSM 7.0 build (preferred if device is on DSM 7).
    echo "---- arch-armada38x-7.0 (DS216j, DSM 7) ----"
    make arch-armada38x-7.0

    # DS216j / armada38x — DSM 6.1 fallback in case the device is still on DSM 6.
    echo "---- arch-armada38x-6.1 (DS216j, DSM 6) ----"
    make arch-armada38x-6.1

    cp -v /spksrc/packages/*.spk /output/
  '

echo
echo "==> Done. Built packages:"
ls -lh "$OUTPUT_DIR"
