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
- Build number (`CURRENT_PROJECT_VERSION`) must always increase — never reuse or go backwards.
- The `release-tb.yml` workflow only triggers on tags matching `v*-tb*`. The upstream `release.yml` triggers on all `v*` tags but will fail (requires Depot runner).
- Always create releases as **draft** first, then publish after CI attaches the DMG. This prevents the README download link from 404-ing during the build.
- Release notes should link to the upstream cmux version: `[cmux vX.Y.Z](https://github.com/manaflow-ai/cmux/releases/tag/vX.Y.Z)`.
- The `tb` number is global and continues incrementing across upstream version bumps (e.g. tb12 on 0.62.2 → tb13 on 0.63.2).
