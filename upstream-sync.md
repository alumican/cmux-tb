# Upstream sync guide

This fork tracks [manaflow-ai/cmux](https://github.com/manaflow-ai/cmux). This document describes the full procedure for merging upstream changes into both the upstream PR branch (`pr/textbox-input`) and the fork's `main` branch.

## Overview: two branches to maintain

| Branch | Purpose | Base |
|--------|---------|------|
| `pr/textbox-input` | Upstream PR (TextBox feature only, no fork branding) | upstream `main` |
| `main` | cmux-tb fork (TextBox + fork branding/customizations) | `pr/textbox-input` + `[cmux-tb]` patches |

Upstream merges flow through `pr/textbox-input` first, then fork customizations are layered on top for `main`.

## Remote setup

```bash
git remote add upstream git@github.com:manaflow-ai/cmux.git
# origin = alumican/cmux-tb
git fetch upstream
git fetch origin
```

## Step 1: Merge upstream into a test branch

Create a branch from `pr/textbox-input` to test the upstream merge:

```bash
git checkout pr/textbox-input
git pull origin pr/textbox-input
git checkout -b merge/upstream-vX.Y.Z
git merge upstream/main   # or a specific tag: git merge v0.63.2
```

Resolve any conflicts. The `pr/textbox-input` branch contains only the TextBox feature (no fork branding), so conflicts are limited to TextBox code vs upstream changes.

Build and test:

```bash
./scripts/reload.sh --tag merge-test --launch
```

## Step 2: Update pr/textbox-input (upstream PR)

Once the merge branch is verified, fast-forward `pr/textbox-input`:

```bash
git checkout pr/textbox-input
git merge --ff-only merge/upstream-vX.Y.Z
git push origin pr/textbox-input
```

This updates the upstream PR at [manaflow-ai/cmux#2051](https://github.com/manaflow-ai/cmux/pull/2051).

## Step 3: Apply fork customizations to main

### Strategy: extract → rebase on pr/textbox-input → re-apply

`main` has `[cmux-tb]` marked customizations on top of an older `pr/textbox-input`. Instead of merging (which causes massive conflicts), we:

1. **Extract** cmux-tb customizations as patches
2. **Create** a new branch from the updated `pr/textbox-input`
3. **Apply** the patches, fixing any that don't apply cleanly
4. **Merge** the result into `main`

### 3a. Extract cmux-tb customizations

```bash
# Full diff of cmux-tb customizations vs pr/textbox-input
git diff pr/textbox-input...main > /tmp/cmux-tb-customizations/full-diff.patch

# Per-file patches for easier review
git diff pr/textbox-input...main -- Resources/Info.plist > /tmp/cmux-tb-customizations/info-plist.patch
git diff pr/textbox-input...main -- Sources/cmuxApp.swift > /tmp/cmux-tb-customizations/cmuxApp.patch
git diff pr/textbox-input...main -- Sources/KeyboardShortcutSettings.swift > /tmp/cmux-tb-customizations/shortcut-settings.patch
git diff pr/textbox-input...main -- Sources/ContentView.swift > /tmp/cmux-tb-customizations/contentview.patch
git diff pr/textbox-input...main -- Sources/TextBoxInput.swift > /tmp/cmux-tb-customizations/textbox-input.patch
git diff pr/textbox-input...main -- Resources/Localizable.xcstrings > /tmp/cmux-tb-customizations/localizable.patch
git diff pr/textbox-input...main -- README.md README.ja.md > /tmp/cmux-tb-customizations/readmes.patch
git diff pr/textbox-input...main -- .github/workflows/release-tb.yml scripts/sparkle_generate_appcast.sh > /tmp/cmux-tb-customizations/release-infra.patch
git diff pr/textbox-input...main -- fork-release.md upstream-sync.md > /tmp/cmux-tb-customizations/fork-docs.patch
```

### 3b. Create new branch and apply patches

```bash
git checkout pr/textbox-input
git checkout -b merge/tb-main-upstream-vX.Y.Z

# Try applying each patch; some will apply clean, others need manual work
for patch in /tmp/cmux-tb-customizations/*.patch; do
  echo "=== $patch ==="
  git apply --check "$patch" 2>&1 && echo "OK" || echo "NEEDS MANUAL"
done
```

**Patches that typically apply cleanly** (new files or isolated changes):
- `release-infra.patch` — fork workflow and sparkle script
- `fork-docs.patch` — fork-release.md, upstream-sync.md
- `InfoPlist.xcstrings` patches

**Patches that typically need manual work** (upstream changed the same files):
- `info-plist.patch` — bundle name, Sparkle URL (2 edits)
- `cmuxApp.patch` — About URLs (2 edits)
- `shortcut-settings.patch` — default key `t` vs `b` (1 edit)
- `contentview.patch` — Help menu fork links
- `localizable.patch` — about.appName, about.description
- `readmes.patch` — full file replacement from `main`

### 3c. Manual application guide

For patches that don't apply, use the patch content as a reference and edit manually. Key customizations to apply:

| Customization | File | What to change |
|---------------|------|----------------|
| Bundle name `cmux-tb` | `Info.plist` | `CFBundleDisplayName` |
| Sparkle URL → fork | `Info.plist` | `SUFeedURL` |
| About URLs → fork | `cmuxApp.swift` | `githubURL`, commit URL |
| Default shortcut `Cmd+Opt+T` | `KeyboardShortcutSettings.swift` | `key: "t"` |
| TextBox enabled by default | `TextBoxInput.swift` | `defaultEnabled = true` |
| Help menu fork links | `ContentView.swift` | Enum cases, URLs, button items |
| Hide Send Feedback / Discord | `ContentView.swift` | Comment out items |
| about.appName / description | `Localizable.xcstrings` | "cmux + TextBox", fork description |
| README / README.ja | Full file | Copy from `main` |

**All fork-specific code must be marked with `[cmux-tb]` comments** (in addition to any existing `[TextBox]` markers).

### 3d. Build, test, commit

```bash
./scripts/reload.sh --tag tb-merge-test --launch
```

Test TextBox, shortcuts, Help menu, About dialog.

```bash
git add -A
git commit -m "Apply cmux-tb fork customizations on top of upstream vX.Y.Z merge"
```

### 3e. Merge into main

```bash
git checkout main
git merge merge/tb-main-upstream-vX.Y.Z --no-ff
```

If conflicts occur (old cmux-tb code vs new), resolve by taking the merge branch (theirs):

```bash
git checkout --theirs <conflicted-files>
git add <conflicted-files>
git commit --no-edit
```

Push:

```bash
git push origin main
```

## cmux-tb customization inventory

All fork-specific changes are marked with `// [cmux-tb]` or `<!-- [cmux-tb] -->` comments.

### Branding & identity
- `Resources/Info.plist` — `CFBundleDisplayName = cmux-tb`, `SUFeedURL` → fork
- `Sources/cmuxApp.swift` — About dialog GitHub/commit URLs → fork
- `Resources/Localizable.xcstrings` — `about.appName = "cmux + TextBox"`, fork description

### Default settings (differ from upstream)
- `Sources/KeyboardShortcutSettings.swift` — TextBox shortcut default `Cmd+Opt+T` (upstream: `Cmd+Opt+B`)
- `Sources/TextBoxInput.swift` — `defaultEnabled = true` (upstream: `false`)

### UI customizations
- `Sources/ContentView.swift` — Help menu: fork Changelog/GitHub/Issues links, hide Send Feedback & Discord

### Release infrastructure
- `.github/workflows/release-tb.yml` — Fork release workflow
- `scripts/sparkle_generate_appcast.sh` — Fork download/release note URLs

### Documentation
- `README.md`, `README.ja.md` — Fork-specific content
- `fork-release.md` — Release procedure
- `upstream-sync.md` — This file

### Fork-only files (no conflict expected)
- `Sources/TextBoxInput.swift` (content differs from upstream PR but file is new in both)
- `.github/workflows/release-tb.yml`
- `fork-release.md`, `upstream-sync.md`

## After merge checklist

1. Build succeeds: `./scripts/reload.sh --tag merge-test --launch`
2. TextBox toggle works (`Cmd+Opt+T`)
3. TextBox enabled by default on fresh install
4. About dialog shows fork GitHub URL
5. Help menu shows fork links (Changelog/GitHub/Issues for both cmux and cmux-tb)
6. Send Feedback and Discord are hidden
7. Sparkle update check points to fork appcast
8. Version number is correct in About dialog
9. If upstream added new localized strings, consider adding Japanese translations
