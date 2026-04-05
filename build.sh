#!/bin/bash
# PhoenixBoot Package Builder
# Automatically generated build script for generating the Magisk module zip

# Get module version from module.prop
VERSION=$(grep '^version=' module.prop | cut -d'=' -f2)
ID=$(grep '^id=' module.prop | cut -d'=' -f2)

if [ -z "$VERSION" ] || [ -z "$ID" ]; then
    echo "Error: Could not read module.prop"
    exit 1
fi

# Clean up any existing zip files
rm -f *.zip

ZIP_NAME="${ID}_${VERSION}.zip"
echo "Packaging module to $ZIP_NAME..."

# Zip the required files
zip -r9 "$ZIP_NAME" . \
    -x ".*" \
    -x "*.zip" \
    -x "build.sh" \
    -x "update.json"

echo "Build complete: $ZIP_NAME"
