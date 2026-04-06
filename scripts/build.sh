#!/bin/bash
# Build script for HyperRealistic Shaders
# Usage: ./scripts/build.sh [version] [subpack_variant]
# Examples:
#   ./scripts/build.sh 1.21.11
#   ./scripts/build.sh 1.21.9

set -euo pipefail

VERSION="${1:-1.21.11}"
PACK_NAME="HyperRealistic-Shaders"
BUILD_DIR="build"
OUTPUT_NAME="${PACK_NAME}-v${VERSION}"

echo "=== Building ${PACK_NAME} for Minecraft Bedrock ${VERSION} ==="

# Clean previous builds
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}/pack"

# Copy core files
cp manifest.json "${BUILD_DIR}/pack/"
cp -r shaders "${BUILD_DIR}/pack/"
cp -r texts "${BUILD_DIR}/pack/"

# Copy subpacks if they exist
if [ -d "subpacks" ]; then
    cp -r subpacks "${BUILD_DIR}/pack/"
fi

# Copy pack icon if it exists
if [ -f "pack_icon.png" ]; then
    cp pack_icon.png "${BUILD_DIR}/pack/"
fi

# Update manifest version based on target
case "${VERSION}" in
    1.21.11)
        # min_engine_version for 1.21.11
        sed -i 's/"min_engine_version": \[1, 21, 0\]/"min_engine_version": [1, 21, 10]/' "${BUILD_DIR}/pack/manifest.json"
        ;;
    1.21.10)
        sed -i 's/"min_engine_version": \[1, 21, 0\]/"min_engine_version": [1, 21, 10]/' "${BUILD_DIR}/pack/manifest.json"
        ;;
    1.21.9)
        sed -i 's/"min_engine_version": \[1, 21, 0\]/"min_engine_version": [1, 21, 0]/' "${BUILD_DIR}/pack/manifest.json"
        ;;
    *)
        echo "Warning: Unknown version ${VERSION}, using default min_engine_version"
        ;;
esac

# Build default variant (all features including ray tracing)
echo "Building default variant (Full features)..."
cd "${BUILD_DIR}/pack"
zip -r "../${OUTPUT_NAME}-Full.zip" . -x "*.DS_Store" -x "__MACOSX/*"
cd ../..

# Build No-Raytracing variant
echo "Building No-Raytracing variant..."
rm -rf "${BUILD_DIR}/pack-nort"
cp -r "${BUILD_DIR}/pack" "${BUILD_DIR}/pack-nort"
if [ -d "${BUILD_DIR}/pack-nort/subpacks/no_raytracing/shaders" ]; then
    cp -r "${BUILD_DIR}/pack-nort/subpacks/no_raytracing/shaders/"* "${BUILD_DIR}/pack-nort/shaders/"
fi
cd "${BUILD_DIR}/pack-nort"
zip -r "../${OUTPUT_NAME}-Standard.zip" . -x "*.DS_Store" -x "__MACOSX/*"
cd ../..

# Build True Dark variant
echo "Building True Dark variant..."
rm -rf "${BUILD_DIR}/pack-td"
cp -r "${BUILD_DIR}/pack" "${BUILD_DIR}/pack-td"
if [ -d "${BUILD_DIR}/pack-td/subpacks/true_dark/shaders" ]; then
    cp -r "${BUILD_DIR}/pack-td/subpacks/true_dark/shaders/"* "${BUILD_DIR}/pack-td/shaders/"
fi
cd "${BUILD_DIR}/pack-td"
zip -r "../${OUTPUT_NAME}-TrueDark.zip" . -x "*.DS_Store" -x "__MACOSX/*"
cd ../..

# Build Lite variant
echo "Building Lite variant..."
rm -rf "${BUILD_DIR}/pack-lite"
cp -r "${BUILD_DIR}/pack" "${BUILD_DIR}/pack-lite"
if [ -d "${BUILD_DIR}/pack-lite/subpacks/lite/shaders" ]; then
    cp -r "${BUILD_DIR}/pack-lite/subpacks/lite/shaders/"* "${BUILD_DIR}/pack-lite/shaders/"
fi
cd "${BUILD_DIR}/pack-lite"
zip -r "../${OUTPUT_NAME}-Lite.zip" . -x "*.DS_Store" -x "__MACOSX/*"
cd ../..

# Build Ultra variant (Ray Tracing + True Dark)
echo "Building Ultra variant..."
rm -rf "${BUILD_DIR}/pack-ultra"
cp -r "${BUILD_DIR}/pack" "${BUILD_DIR}/pack-ultra"
if [ -d "${BUILD_DIR}/pack-ultra/subpacks/raytracing_truedark/shaders" ]; then
    cp -r "${BUILD_DIR}/pack-ultra/subpacks/raytracing_truedark/shaders/"* "${BUILD_DIR}/pack-ultra/shaders/"
fi
cd "${BUILD_DIR}/pack-ultra"
zip -r "../${OUTPUT_NAME}-Ultra.zip" . -x "*.DS_Store" -x "__MACOSX/*"
cd ../..

echo ""
echo "=== Build Complete ==="
echo "Output files:"
ls -lh "${BUILD_DIR}"/*.zip
echo ""
echo "Total variants built: $(ls ${BUILD_DIR}/*.zip | wc -l)"
