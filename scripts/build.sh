#!/bin/bash
# Builds a universal (arm64 + x86_64) MacVitals.app and wraps it in an installer package.
#
#   scripts/build.sh                      unsigned, ad-hoc signed binary (local testing)
#
# Optional, for distribution (all read from the environment):
#   DEVELOPER_ID_APP="Developer ID Application: Name (TEAMID)"     sign the app with hardened runtime
#   DEVELOPER_ID_INSTALLER="Developer ID Installer: Name (TEAMID)"  sign the .pkg
#   NOTARY_PROFILE=macvitals   notarize + staple (create with: xcrun notarytool store-credentials)
#
# Output: build/MacVitals-<version>.pkg
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION=$(sed -n 's/.*static let version = "\(.*\)".*/\1/p' Sources/MacVitalsCore/Constants.swift)
PKG_ID="io.github.macvitals.pkg"
OUT="$ROOT/build"
STAGE="$OUT/stage"
APP="$STAGE/payload/Library/Application Support/MacVitals/MacVitals.app"
PKG="$OUT/MacVitals-$VERSION.pkg"

echo "==> MacVitals $VERSION"
rm -rf "$OUT"
mkdir -p "$APP/Contents/MacOS" "$STAGE/payload/Library/LaunchDaemons" "$STAGE/payload/Library/LaunchAgents"

echo "==> Building arm64 and x86_64"
# One scratch path per architecture: newer SwiftPM versions share a single output folder otherwise.
for arch in arm64 x86_64; do
    swift build -c release --arch "$arch" --product macvitals --scratch-path ".build/$arch"
done
lipo -create \
    "$(swift build -c release --arch arm64 --scratch-path .build/arm64 --show-bin-path)/macvitals" \
    "$(swift build -c release --arch x86_64 --scratch-path .build/x86_64 --show-bin-path)/macvitals" \
    -output "$APP/Contents/MacOS/macvitals"
lipo -info "$APP/Contents/MacOS/macvitals"

sed "s/__VERSION__/$VERSION/g" packaging/Info.plist > "$APP/Contents/Info.plist"
cp packaging/launchd/io.github.macvitals.daemon.plist "$STAGE/payload/Library/LaunchDaemons/"
cp packaging/launchd/io.github.macvitals.agent.plist "$STAGE/payload/Library/LaunchAgents/"
chmod 755 packaging/scripts/preinstall packaging/scripts/postinstall

echo "==> Signing app"
if [[ -n "${DEVELOPER_ID_APP:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$DEVELOPER_ID_APP" "$APP"
else
    echo "    DEVELOPER_ID_APP not set: ad-hoc signature (fine for testing, Gatekeeper will warn)"
    codesign --force --sign - "$APP"
fi
codesign --verify --strict "$APP"

echo "==> Building package"
# Explicit component plist: never let Installer "relocate" the app to another copy on disk.
pkgbuild --analyze --root "$STAGE/payload" "$STAGE/components.plist" >/dev/null
/usr/libexec/PlistBuddy -c "Add :0:BundleIsRelocatable bool false" "$STAGE/components.plist"
SIGN_ARGS=()
[[ -n "${DEVELOPER_ID_INSTALLER:-}" ]] && SIGN_ARGS=(--sign "$DEVELOPER_ID_INSTALLER" --timestamp)
pkgbuild \
    --root "$STAGE/payload" \
    --component-plist "$STAGE/components.plist" \
    --scripts packaging/scripts \
    --identifier "$PKG_ID" \
    --version "$VERSION" \
    --install-location / \
    ${SIGN_ARGS[@]+"${SIGN_ARGS[@]}"} \
    "$PKG"

if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    echo "==> Notarizing"
    xcrun notarytool submit "$PKG" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$PKG"
fi

# Guardrail: the package must never carry secrets or a config file.
if pkgutil --payload-files "$PKG" | grep -qiE 'config\.json|\.mobileconfig'; then
    echo "ERROR: package contains a configuration file" >&2
    exit 1
fi

shasum -a 256 "$PKG" | tee "$PKG.sha256"
echo "==> Done: $PKG"
