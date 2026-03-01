# wuhu-app

Native Wuhu apps for macOS and iOS.

## Setup

Requires [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen
```

Fetch Sparkle framework and generate the Xcode project:

```bash
./scripts/fetch-sparkle.sh
cd WuhuApp && xcodegen generate
```

Then open `WuhuApp/WuhuApp.xcodeproj` in Xcode.

## Targets

| Target | Platform | Bundle ID | Product Name |
|--------|----------|-----------|--------------|
| WuhuApp | iOS | `ms.liu.wuhu.ios` | Wuhu |
| WuhuAppMac | macOS | `ms.liu.wuhu.macos` | Wuhu |

## Build (CLI)

```bash
# macOS
xcodebuild build -project WuhuApp/WuhuApp.xcodeproj -scheme WuhuAppMac -destination 'platform=macOS' -quiet

# iOS
xcodebuild build -project WuhuApp/WuhuApp.xcodeproj -scheme WuhuApp -destination 'generic/platform=iOS' -quiet
```

## Releasing a New Version

Both macOS and iOS share version numbers in `WuhuApp/project.yml`:

```yaml
MARKETING_VERSION: "1.0.0"     # User-facing version (semver)
CURRENT_PROJECT_VERSION: "26"  # Monotonically increasing build number
```

These defaults are only used for **local dev builds** (⌘R in Xcode). CI
derives the version entirely from the git tag.

### How to release

Just tag and push:

```bash
git tag v1.0.0-27
git push origin v1.0.0-27
```

Tag format: **`v{MARKETING_VERSION}-{BUILD_NUMBER}`**

- Marketing version is standard semver: `1.0.0`, `1.0.1`, `1.1.0`, `2.0.0`
- Build number is monotonically increasing (required by TestFlight)
- The hyphen separates version from build — e.g. `v1.0.1-28`, `v1.1.0-29`

The `release.yml` workflow parses the tag and passes the version to both
build scripts as xcodebuild overrides:
- **macOS**: build → notarize → staple → sign with EdDSA → upload to R2 → update appcast
- **iOS**: build → upload to TestFlight

That's it. The individual scripts (`build-notarized-mac.sh`,
`publish-release.sh`, `build-testflight.sh`) exist as building blocks called
by CI — don't run them directly unless debugging.

### Tag history

| Tag | Marketing Version | Build | Notes |
|-----|-------------------|-------|-------|
| `v1.0-24` | — | — | Failed (old format) |
| `v1.0.25` | 1.0 | 25 | Old dot-based format |
| `v1.0.26` | 1.0 | 26 | Old dot-based format |
| `v1.0.0-27` | 1.0.0 | 27 | ← next release (new hyphen format) |

### What gets published

| Platform | Destination | URL |
|----------|-------------|-----|
| macOS | Cloudflare R2 | `https://wuhu.ai/releases/macos/Wuhu-latest.zip` |
| macOS | Sparkle appcast | `https://wuhu.ai/releases/appcast.xml` |
| iOS | TestFlight | Via App Store Connect |

Existing macOS users get a native Sparkle update dialog automatically.

## Auto-Update (macOS)

The macOS app uses [Sparkle](https://sparkle-project.org/) for self-update:

- Sparkle xcframework is downloaded at build time by `scripts/fetch-sparkle.sh`
  (not committed to git — binary frameworks don't survive git round-trips)
- Updates are signed with EdDSA (key at `~/.wuhu/keys/sparkle_eddsa_key.priv`)
- Appcast served from `https://wuhu.ai/releases/appcast.xml`
- Public key embedded in the macOS Info.plist (`SUPublicEDKey`)

## CI

CI runs on a self-hosted GitHub Actions runner (`mac-mini`) for both PRs and
releases. The runner is installed at `~/actions-runner/` and runs as a launchd
service that survives reboots.

## Dependencies

- [wuhu-core](https://github.com/wuhu-labs/wuhu-core) — WuhuAPI, WuhuClient, WuhuCoreClient
- [swift-composable-architecture](https://github.com/pointfreeco/swift-composable-architecture) — TCA
- [swift-markdown-ui](https://github.com/gonzalezreal/swift-markdown-ui) — Markdown rendering
- [Sparkle](https://sparkle-project.org/) 2.7.0 — macOS auto-update (fetched at build time)

## License

MIT
