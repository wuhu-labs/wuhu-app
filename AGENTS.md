# AGENTS.md

## What is this

`wuhu-app` contains the native Wuhu apps for macOS and iOS. The apps are built
with SwiftUI and [TCA](https://github.com/pointfreeco/swift-composable-architecture).

They consume [wuhu-core](https://github.com/wuhu-labs/wuhu-core) for
`WuhuAPI`, `WuhuClient`, and `WuhuCoreClient` — the client-safe types and
HTTP client library.

## Project Setup

Source of truth is `Project.swift` and `Tuist/Package.swift` (Tuist). The
generated `.xcodeproj` / `.xcworkspace` files are not committed.

```bash
tuist install
tuist generate
```

The macOS target (`WuhuAppMac`) depends on
[Sparkle](https://github.com/sparkle-project/Sparkle) for auto-updates. The
`Sparkle.xcframework` is **not committed** — fetch it before building:

```bash
./scripts/fetch-sparkle.sh
```

The script is idempotent; it skips the download if the framework is already
present.

## Build

```bash
# macOS
xcodebuild build -workspace WuhuApp.xcworkspace -scheme WuhuAppMac -destination 'platform=macOS' -quiet

# iOS
xcodebuild build -workspace WuhuApp.xcworkspace -scheme WuhuApp -destination 'generic/platform=iOS Simulator' -quiet
```

## Release

Releases are **tag-driven**. Push a tag matching `v{VERSION}-{BUILD}` (e.g.
`v1.0.1-31`) and the CI workflow (`.github/workflows/release.yml`) handles
both the notarized macOS build and the TestFlight upload automatically.

```bash
git tag v1.0.1-31
git push origin v1.0.1-31
```

The CI workflow **parses the version and build number exclusively from the
tag** and injects them into the build at compile time. You do **not** need to
update `marketingVersion` or `currentProjectVersion` in `Project.swift` —
just push the tag and CI handles the rest.

### Build numbering

The build number (`CURRENT_PROJECT_VERSION` / `CFBundleVersion`) is
**monotonically increasing across all versions**. This is required by
[Sparkle](https://github.com/sparkle-project/Sparkle) — it compares build
numbers numerically to decide whether an update is available, regardless of
the marketing version string. When bumping the marketing version, continue
the build number sequence from the previous release rather than resetting
to 1. Check existing tags (`git tag --sort=-v:refname`) to find the next
build number.

**Unless the user explicitly asks for a manual/local build**, "build",
"release", "publish", or "upload" means pushing a new tag and letting CI
handle it.

### Manual builds (rare)

Local build scripts exist for cases where CI is unavailable:

- `./scripts/build-notarized-mac.sh` — macOS notarized build
- `./scripts/build-testflight.sh` — iOS TestFlight upload
- `./scripts/check-testflight.sh` — monitor TestFlight processing

These are documented in the `macos-manual-build` and `testflight-manual-build`
workspace skills. Only use them when explicitly asked.

## Collaboration

When the user is interactively asking questions while reviewing code:

- Treat the user's questions/concerns as likely-valid signals, not as "user error".
- Take a neutral stance: verify by inspecting the repo before concluding who's right.
- Correct the user only when there's a clear factual mismatch, and cite the exact
  file/symbol you're relying on.
