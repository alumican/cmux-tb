# Fork release guide

## Versioning

Format: `{upstream-version}-tb{n}`

- `0.62.2-tb1` = first TextBox release based on upstream 0.62.2
- `0.62.2-tb2` = second release on the same upstream base (bug fixes, TextBox improvements)
- `0.63.0-tb1` = first release after merging upstream 0.63.0

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
MARKETING_VERSION = 0.62.2-tb2;

# Bump CURRENT_PROJECT_VERSION (must be monotonically increasing):
CURRENT_PROJECT_VERSION = 80;
```

### 3. Local build & verify

```bash
xcodebuild -project GhosttyTabs.xcodeproj -scheme cmux -configuration Release -destination 'platform=macOS' build
```

Verify the app launches and TextBox works correctly.

### 4. Commit, tag, and push

```bash
git add GhosttyTabs.xcodeproj/project.pbxproj
git commit -m "Bump version to 0.62.2-tb2 (build 80)"
git tag v0.62.2-tb2
git push origin main
git push origin v0.62.2-tb2
```

Pushing a `v*-tb*` tag triggers the `release-tb.yml` workflow, which automatically:
1. Builds the Release app
2. Codesigns with Apple Developer certificate
3. Notarizes with Apple
4. Creates a styled DMG (`cmux-tb-macos.dmg`)
5. Uploads the DMG as a GitHub Release asset

### 5. Create a draft release

**Important:** Create the release as a **draft** so the README download link (`releases/latest/download/cmux-tb-macos.dmg`) keeps pointing to the previous release until the DMG is ready.

```bash
gh release create v0.62.2-tb2 --repo alumican/cmux-tb --draft --title "v0.62.2-tb2" --notes "$(cat <<'EOF'
## cmux + TextBox v0.62.2-tb2

Based on [cmux v0.62.2](https://github.com/manaflow-ai/cmux/releases/tag/v0.62.2).

### Changes from tb1
- ...

### Install
Download `cmux-tb-macos.dmg`, open it, and drag cmux-tb to Applications.
EOF
)"
```

### 6. Monitor the workflow

```bash
gh run list --repo alumican/cmux-tb --limit 3
gh run view <run-id> --repo alumican/cmux-tb
```

### 7. Publish the release

Once the CI workflow completes and the DMG is attached to the draft release:

```bash
gh release edit v0.62.2-tb2 --repo alumican/cmux-tb --draft=false
```

The signed DMG will then be available at:
`https://github.com/alumican/cmux-tb/releases/latest/download/cmux-tb-macos.dmg`

## Re-releasing a tag

If a release needs to be redone (e.g. workflow failed and you fixed the issue):

```bash
gh release delete v0.62.2-tb1 --repo alumican/cmux-tb --yes
git push origin --delete v0.62.2-tb1
git tag -d v0.62.2-tb1
git tag v0.62.2-tb1
git push origin v0.62.2-tb1
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
  --icon "cmux-tb.app" 180 180 \
  --app-drop-link 480 180 \
  /tmp/cmux-tb-macos.dmg \
  "/path/to/DerivedData/.../Build/Products/Release/cmux-tb.app"
```

Requires `brew install create-dmg` and npm `create-dmg` for the background image.

## Notes

- The DMG asset must be named `cmux-tb-macos.dmg` to match the README download link.
- Build number (`CURRENT_PROJECT_VERSION`) must always increase — never reuse or go backwards.
- The `release-tb.yml` workflow only triggers on tags matching `v*-tb*`. The upstream `release.yml` triggers on all `v*` tags but will fail (requires Depot runner).
- Always create releases as **draft** first, then publish after CI attaches the DMG. This prevents the README download link from 404-ing during the build.
- Release notes should link to the upstream cmux version: `[cmux vX.Y.Z](https://github.com/manaflow-ai/cmux/releases/tag/vX.Y.Z)`.
