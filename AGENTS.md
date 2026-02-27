# AGENTS.md

## What is this

`wuhu-app` contains the native Wuhu apps for macOS and iOS. The apps are built
with SwiftUI and [TCA](https://github.com/pointfreeco/swift-composable-architecture).

They consume [wuhu-core](https://github.com/wuhu-labs/wuhu-core) for
`WuhuAPI`, `WuhuClient`, and `WuhuCoreClient` — the client-safe types and
HTTP client library.

## Project Setup

Source of truth is `WuhuApp/project.yml` (XcodeGen). The `.xcodeproj` is
generated, not committed.

```bash
cd WuhuApp && xcodegen generate
```

## Build

```bash
# macOS
xcodebuild build -project WuhuApp/WuhuApp.xcodeproj -scheme WuhuAppMac -destination 'platform=macOS' -quiet

# iOS
xcodebuild build -project WuhuApp/WuhuApp.xcodeproj -scheme WuhuApp -destination 'generic/platform=iOS' -quiet
```

## TestFlight

```bash
./scripts/build-testflight.sh
./scripts/check-testflight.sh
```

## Collaboration

When the user is interactively asking questions while reviewing code:

- Treat the user's questions/concerns as likely-valid signals, not as "user error".
- Take a neutral stance: verify by inspecting the repo before concluding who's right.
- Correct the user only when there's a clear factual mismatch, and cite the exact
  file/symbol you're relying on.
