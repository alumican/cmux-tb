# Fork release guide

## Versioning

Format: `{upstream-version}-tb{n}`

- `0.62.2-tb1` = first TextBox release based on upstream 0.62.2
- `0.62.2-tb12` = twelfth release on the same upstream base
- `0.63.2-tb13` = first release after merging upstream 0.63.2 (tb number continues across upstream bumps)

The `-tb` suffix distinguishes fork releases from upstream. The number after `tb` increments for each release on the same upstream base.

## Prerequisites

- `gh` CLI authenticated with access to `alumican/cmux-tb`
- GitHub Secrets configured: `APPLE_CERTIFICATE_BASE64`, `APPLE_CERTIFICATE_PASSWORD`, `APPLE_SIGNING_IDENTITY`, `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD`, `APPLE_TEAM_ID`

## Steps

### 1. Merge upstream (if applicable)

See [upstream-sync.md](upstream-sync.md) for the full merge procedure.

### 2. Set version

The `scripts/bump-version.sh` only supports `x.y.z` format, so set the version manually:

```bash
# In GhosttyTabs.xcodeproj/project.pbxproj, update both occurrences:
MARKETING_VERSION = 0.63.2-tb14;

# Bump CURRENT_PROJECT_VERSION (must be monotonically increasing).
# Current: 80 (v0.63.2-tb13)
CURRENT_PROJECT_VERSION = 81;
```

### 3. Local build & verify

```bash
xcodebuild -project GhosttyTabs.xcodeproj -scheme cmux -configuration Release -destination 'platform=macOS' build
```

Verify the app launches and TextBox works correctly.

### 4. Update changelog

Update `CHANGELOG.md` with user-facing changes for this release.

### 5. Commit, tag, and push

Commit directly to main — do **not** create a PR. Keeping the version bump
and changelog in the same commit stream as the feature/fix commits makes it
easy to trace release contents from `git log`.

```bash
git add CHANGELOG.md GhosttyTabs.xcodeproj/project.pbxproj
git commit -m "Bump version to 0.63.2-tb14"
git tag v0.63.2-tb14
git push origin main
git push origin v0.63.2-tb14
```

Pushing a `v*-tb*` tag triggers the `release-tb.yml` workflow, which automatically:
1. Downloads pre-built GhosttyKit.xcframework
2. Installs Zig (required for Ghostty CLI helper)
3. Builds the Release app (`cmux.app` — PRODUCT_NAME is "cmux" in Release config)
4. Codesigns with Apple Developer certificate
5. Notarizes with Apple
6. Creates a styled DMG (`cmux-tb-macos.dmg`)
7. Generates Sparkle `appcast.xml` for auto-update
8. Uploads the DMG and appcast as GitHub Release assets

**Important notes about the workflow (`release-tb.yml`):**
- The built app is `cmux.app` (not `cmux-tb.app`) because `PRODUCT_NAME = cmux` in the Release build configuration. The workflow references `build/Build/Products/Release/cmux.app` for codesign and notarize steps.
- Zig must be installed on the runner — it is not pre-installed on GitHub Actions macOS runners. The workflow installs it from the official tarball.
- The `create-dmg` tool generates a DMG named after the app (`cmux *.dmg`), which is then renamed to `cmux-tb-macos.dmg`.

### 6. Create a draft release

**Important:** Create the release as a **draft** so the README download link (`releases/latest/download/cmux-tb-macos.dmg`) keeps pointing to the previous release until the DMG is ready.

```bash
gh release create v0.63.2-tb14 --repo alumican/cmux-tb --draft --title "v0.63.2-tb14" --notes "$(cat <<'EOF'
## cmux + TextBox v0.63.2-tb14

Based on [cmux v0.63.2](https://github.com/manaflow-ai/cmux/releases/tag/v0.63.2).

### Changes
- ...

### Install
Download `cmux-tb-macos.dmg`, open it, and drag cmux-tb to Applications.
EOF
)"
```

### 7. Monitor the workflow

```bash
gh run list --repo alumican/cmux-tb --limit 3
gh run view <run-id> --repo alumican/cmux-tb
```

### 8. Clean up duplicate releases

CI (`softprops/action-gh-release`) may create a **separate** published release alongside your draft. Check for duplicates:

```bash
gh release list --repo alumican/cmux-tb --limit 5
```

If a duplicate draft remains, delete it:

```bash
# Find the draft release ID
gh api repos/alumican/cmux-tb/releases --jq '.[] | select(.draft==true and .tag_name=="v0.63.2-tb14") | .id'
# Delete it
gh api -X DELETE repos/alumican/cmux-tb/releases/<id>
```

### 9. Publish the release

Once the CI workflow completes, the DMG is attached, and duplicates are cleaned up:

```bash
gh release edit v0.63.2-tb14 --repo alumican/cmux-tb --draft=false
```

The signed DMG will then be available at:
`https://github.com/alumican/cmux-tb/releases/latest/download/cmux-tb-macos.dmg`

## Re-releasing a tag

If a release needs to be redone (e.g. workflow failed and you fixed the issue):

```bash
gh release delete v0.63.2-tb13 --repo alumican/cmux-tb --yes
git push origin --delete v0.63.2-tb13
git tag -d v0.63.2-tb13
git tag v0.63.2-tb13
git push origin v0.63.2-tb13
```

## Local DMG (unsigned, for testing only)

For quick local testing without codesigning:

```bash
BG="$(npm root -g)/create-dmg/assets/dmg-background@2x.png"

create-dmg \
  --volname "cmux-tb" \
  --background "$BG" \
  --window-size 660 400 \
  --icon-size 128 \
  --icon "cmux.app" 180 180 \
  --app-drop-link 480 180 \
  /tmp/cmux-tb-macos.dmg \
  "/path/to/DerivedData/.../Build/Products/Release/cmux.app"
```

Requires `brew install create-dmg` and npm `create-dmg` for the background image.

## Notes

- The DMG asset must be named `cmux-tb-macos.dmg` to match the README download link.
- Build number (`CURRENT_PROJECT_VERSION`) must always increase — never reuse or go backwards. **After an upstream merge, the build number in `project.pbxproj` will be reset to the upstream value, which is almost certainly lower than the fork's.** Always check the previous fork release's appcast to find the last published build number and set the new one higher:
  ```bash
  curl -fsSL https://github.com/alumican/cmux-tb/releases/download/v<previous-tag>/appcast.xml | grep 'sparkle:version'
  ```
  For example, v0.62.2-tb12 had build 91 but upstream v0.63.2 had 79. Setting tb13 to 80 broke the Sparkle upgrade path because 80 < 91. The fix was to set it to 92.
- The `release-tb.yml` workflow only triggers on tags matching `v*-tb*`. The upstream `release.yml` triggers on all `v*` tags but will fail (requires Depot runner).
- Always create releases as **draft** first, then publish after CI attaches the DMG. This prevents the README download link from 404-ing during the build.
- Release notes should link to the upstream cmux version: `[cmux vX.Y.Z](https://github.com/manaflow-ai/cmux/releases/tag/vX.Y.Z)`.
- The `tb` number is global and continues incrementing across upstream version bumps (e.g. tb12 on 0.62.2 → tb13 on 0.63.2).

## Troubleshooting: past CI failures

### `error: zig is required to build the Ghostty CLI helper`

Zig is not pre-installed on GitHub Actions macOS runners. The `Install Zig` step is required.

### `cmux-tb.app: No such file or directory` (Codesign failure)

The Release build's `PRODUCT_NAME` is `cmux` (not `cmux-tb`). The build artifact is at `build/Build/Products/Release/cmux.app`. All paths in the workflow must reference `cmux.app`.

### `create-dmg` output DMG name

`create-dmg` generates a DMG named after the app (`cmux *.dmg`). Use `mv ./cmux*.dmg "$DMG_RELEASE"` to rename it to `cmux-tb-macos.dmg`. The glob `cmux-tb*.dmg` will not match — use `cmux*.dmg` instead.

### Sparkle appcast parse error: `Attribute length redefined`

The `sparkle_generate_appcast.sh` fallback signing path (`sign_update`) injects `sparkle:edSignature` and `length` into the `<enclosure>` element. If `generate_appcast` already wrote a `length` attribute, the injection creates a duplicate, producing invalid XML that Sparkle rejects with `SUAppcastParseError (1000)`.

This happens when `generate_appcast` adds `length` but skips the EdDSA signature (e.g. because the public key in the built app doesn't match the private key). The script then falls through to the `sign_update` fallback and naively injects another `length`.

**Fix (applied in v0.63.2-tb13):** The fallback now uses `re.sub(r'length="[^"]*"', ...)` to update the existing `length` attribute instead of adding a new one. If this error recurs after modifying the appcast script, check for duplicate XML attributes in the generated `appcast.xml`:

```bash
curl -fsSL https://github.com/alumican/cmux-tb/releases/latest/download/appcast.xml | grep -o 'length=' | wc -l
# Should be exactly 1
```

## Reference: release-tb.yml (as of v0.63.2-tb13)

```yaml
name: Release cmux-tb

on:
  push:
    tags:
      - "v*-tb*"
  workflow_dispatch:

permissions:
  contents: write

jobs:
  build-sign-notarize:
    runs-on: macos-26
    steps:
      - name: Checkout
        uses: actions/checkout@v4
        with:
          submodules: recursive

      - name: Select Xcode
        run: |
          set -euo pipefail
          if [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
            XCODE_DIR="/Applications/Xcode.app/Contents/Developer"
          else
            XCODE_APP="$(ls -d /Applications/Xcode*.app 2>/dev/null | head -n 1 || true)"
            if [ -n "$XCODE_APP" ]; then
              XCODE_DIR="$XCODE_APP/Contents/Developer"
            else
              echo "No Xcode.app found under /Applications" >&2
              exit 1
            fi
          fi
          echo "DEVELOPER_DIR=$XCODE_DIR" >> "$GITHUB_ENV"
          export DEVELOPER_DIR="$XCODE_DIR"
          xcodebuild -version
          xcrun --sdk macosx --show-sdk-path

      - name: Download pre-built GhosttyKit.xcframework
        run: |
          ./scripts/download-prebuilt-ghosttykit.sh

      - name: Cache Swift packages
        uses: actions/cache@v4
        with:
          path: .spm-cache
          key: spm-${{ hashFiles('GhosttyTabs.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved') }}
          restore-keys: spm-

      - name: Install Zig
        run: |
          ZIG_REQUIRED="0.15.2"
          if command -v zig >/dev/null 2>&1 && zig version 2>/dev/null | grep -q "^${ZIG_REQUIRED}"; then
            echo "zig ${ZIG_REQUIRED} already installed"
          else
            echo "Installing zig ${ZIG_REQUIRED} from tarball"
            curl -fSL "https://ziglang.org/download/${ZIG_REQUIRED}/zig-aarch64-macos-${ZIG_REQUIRED}.tar.xz" -o /tmp/zig.tar.xz
            tar xf /tmp/zig.tar.xz -C /tmp
            sudo mkdir -p /usr/local/bin /usr/local/lib
            sudo cp -f /tmp/zig-aarch64-macos-${ZIG_REQUIRED}/zig /usr/local/bin/zig
            sudo cp -rf /tmp/zig-aarch64-macos-${ZIG_REQUIRED}/lib /usr/local/lib/zig
            export PATH="/usr/local/bin:$PATH"
            zig version
          fi

      - name: Build app (Release)
        run: |
          export PATH="/usr/local/bin:$PATH"
          xcodebuild -scheme cmux -configuration Release -derivedDataPath build \
            -clonedSourcePackagesDirPath .spm-cache \
            CODE_SIGNING_ALLOWED=NO build

      - name: Verify Sparkle keys in Info.plist
        run: |
          APP_PLIST="build/Build/Products/Release/cmux.app/Contents/Info.plist"
          PLIST_KEY=$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$APP_PLIST" 2>/dev/null || echo "")
          PLIST_FEED=$(/usr/libexec/PlistBuddy -c "Print :SUFeedURL" "$APP_PLIST" 2>/dev/null || echo "")
          echo "SUPublicEDKey: $PLIST_KEY"
          echo "SUFeedURL: $PLIST_FEED"
          if [ -z "$PLIST_KEY" ]; then
            echo "ERROR: SUPublicEDKey missing from Info.plist" >&2
            exit 1
          fi

      - name: Import signing cert
        env:
          APPLE_CERTIFICATE_BASE64: ${{ secrets.APPLE_CERTIFICATE_BASE64 }}
          APPLE_CERTIFICATE_PASSWORD: ${{ secrets.APPLE_CERTIFICATE_PASSWORD }}
        run: |
          if [ -z "$APPLE_CERTIFICATE_BASE64" ]; then
            echo "Missing APPLE_CERTIFICATE_BASE64 secret" >&2
            exit 1
          fi
          if [ -z "$APPLE_CERTIFICATE_PASSWORD" ]; then
            echo "Missing APPLE_CERTIFICATE_PASSWORD secret" >&2
            exit 1
          fi
          KEYCHAIN_PASSWORD="$(uuidgen)"
          echo "$APPLE_CERTIFICATE_BASE64" | base64 --decode > /tmp/cert.p12
          security delete-keychain build.keychain >/dev/null 2>&1 || true
          security create-keychain -p "$KEYCHAIN_PASSWORD" build.keychain
          security set-keychain-settings -lut 21600 build.keychain
          security unlock-keychain -p "$KEYCHAIN_PASSWORD" build.keychain
          security import /tmp/cert.p12 -k build.keychain -P "$APPLE_CERTIFICATE_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security
          security set-key-partition-list -S apple-tool:,apple: -s -k "$KEYCHAIN_PASSWORD" build.keychain
          security list-keychains -d user -s build.keychain

      - name: Codesign app
        env:
          APPLE_SIGNING_IDENTITY: ${{ secrets.APPLE_SIGNING_IDENTITY }}
        run: |
          if [ -z "$APPLE_SIGNING_IDENTITY" ]; then
            echo "Missing APPLE_SIGNING_IDENTITY secret" >&2
            exit 1
          fi
          APP_PATH="build/Build/Products/Release/cmux.app"
          ENTITLEMENTS="cmux.entitlements"
          for CLI_BIN in "$APP_PATH"/Contents/Resources/bin/*; do
            [ -f "$CLI_BIN" ] || continue
            /usr/bin/codesign --force --options runtime --timestamp --sign "$APPLE_SIGNING_IDENTITY" --entitlements "$ENTITLEMENTS" "$CLI_BIN"
          done
          /usr/bin/codesign --force --options runtime --timestamp --sign "$APPLE_SIGNING_IDENTITY" --entitlements "$ENTITLEMENTS" --deep "$APP_PATH"
          /usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH"

      - name: Notarize app
        env:
          APPLE_ID: ${{ secrets.APPLE_ID }}
          APPLE_APP_SPECIFIC_PASSWORD: ${{ secrets.APPLE_APP_SPECIFIC_PASSWORD }}
          APPLE_TEAM_ID: ${{ secrets.APPLE_TEAM_ID }}
          APPLE_SIGNING_IDENTITY: ${{ secrets.APPLE_SIGNING_IDENTITY }}
        run: |
          if [ -z "$APPLE_ID" ] || [ -z "$APPLE_APP_SPECIFIC_PASSWORD" ] || [ -z "$APPLE_TEAM_ID" ]; then
            echo "Missing notarization secrets" >&2
            exit 1
          fi
          APP_PATH="build/Build/Products/Release/cmux.app"
          ZIP_SUBMIT="cmux-tb-notary.zip"
          DMG_RELEASE="cmux-tb-macos.dmg"
          ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_SUBMIT"
          APP_SUBMIT_JSON="$(xcrun notarytool submit "$ZIP_SUBMIT" --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD" --wait --output-format json)"
          APP_STATUS="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])' <<<"$APP_SUBMIT_JSON")"
          if [ "$APP_STATUS" != "Accepted" ]; then
            echo "App notarization failed: $APP_STATUS" >&2
            exit 1
          fi
          xcrun stapler staple "$APP_PATH"
          spctl -a -vv --type execute "$APP_PATH"
          rm -f "$ZIP_SUBMIT"
          npm install --global create-dmg@8.0.0
          create-dmg --identity="$APPLE_SIGNING_IDENTITY" "$APP_PATH" ./
          mv ./cmux*.dmg "$DMG_RELEASE"
          DMG_SUBMIT_JSON="$(xcrun notarytool submit "$DMG_RELEASE" --apple-id "$APPLE_ID" --team-id "$APPLE_TEAM_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD" --wait --output-format json)"
          DMG_STATUS="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["status"])' <<<"$DMG_SUBMIT_JSON")"
          if [ "$DMG_STATUS" != "Accepted" ]; then
            echo "DMG notarization failed: $DMG_STATUS" >&2
            exit 1
          fi
          xcrun stapler staple "$DMG_RELEASE"

      - name: Generate appcast.xml
        env:
          SPARKLE_PRIVATE_KEY: ${{ secrets.SPARKLE_PRIVATE_KEY }}
        run: |
          TAG="${GITHUB_REF#refs/tags/}"
          ./scripts/sparkle_generate_appcast.sh cmux-tb-macos.dmg "$TAG" appcast.xml

      - name: Upload release assets
        uses: softprops/action-gh-release@v2
        with:
          files: |
            cmux-tb-macos.dmg
            appcast.xml

      - name: Cleanup keychain
        if: always()
        run: |
          security delete-keychain build.keychain >/dev/null 2>&1 || true
          rm -f /tmp/cert.p12
```
