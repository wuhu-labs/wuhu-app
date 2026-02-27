# wuhu-app

Native Wuhu apps for macOS and iOS.

## Setup

Requires [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen
```

Generate the Xcode project:

```bash
cd WuhuApp && xcodegen generate
```

Then open `WuhuApp/WuhuApp.xcodeproj` in Xcode.

## Targets

| Target | Platform | Bundle ID |
|--------|----------|-----------|
| WuhuApp | iOS | `ms.liu.wuhu.ios` |
| WuhuAppMac | macOS | `ms.liu.wuhu.macos` |

## Build (CLI)

```bash
# macOS
xcodebuild build -project WuhuApp/WuhuApp.xcodeproj -scheme WuhuAppMac -destination 'platform=macOS' -quiet

# iOS
xcodebuild build -project WuhuApp/WuhuApp.xcodeproj -scheme WuhuApp -destination 'generic/platform=iOS' -quiet
```

## Dependencies

- [wuhu-core](https://github.com/wuhu-labs/wuhu-core) — WuhuAPI, WuhuClient, WuhuCoreClient
- [swift-composable-architecture](https://github.com/pointfreeco/swift-composable-architecture) — TCA
- [swift-markdown-ui](https://github.com/gonzalezreal/swift-markdown-ui) — Markdown rendering

## License

MIT
