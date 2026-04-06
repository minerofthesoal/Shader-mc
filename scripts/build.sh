#!/bin/bash
# Build script for HyperRealistic Shaders (Java Edition)
# Usage: ./scripts/build.sh [version]
# Examples:
#   ./scripts/build.sh 1.21.11
#   ./scripts/build.sh 1.21.9

set -euo pipefail

VERSION="${1:-1.21.11}"
PACK_NAME="HyperRealistic-Shaders"
BUILD_DIR="build"
OUTPUT_NAME="${PACK_NAME}-v${VERSION}"

echo "=== Building ${PACK_NAME} for Minecraft Java ${VERSION} ==="

# Clean previous builds
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}/pack"

# Copy shader files (Java shader packs are just a shaders/ folder in a zip)
cp -r shaders "${BUILD_DIR}/pack/"

echo "Building shader pack..."
cd "${BUILD_DIR}/pack"
zip -r "../${OUTPUT_NAME}.zip" shaders/ -x "*.DS_Store" -x "__MACOSX/*"
cd ../..

echo ""
echo "=== Build Complete ==="
echo "Output files:"
ls -lh "${BUILD_DIR}"/*.zip
echo ""
echo "Install: Copy the .zip to .minecraft/shaderpacks/"
echo "Requires: OptiFine or Iris (Fabric/Quilt)"
