// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "WuhuAppDependencies",
  dependencies: [
    .package(url: "https://github.com/wuhu-labs/wuhu-core.git", exact: "0.8.0"),
    .package(url: "https://github.com/pointfreeco/swift-composable-architecture.git", from: "1.23.1"),
    .package(url: "https://github.com/pointfreeco/swift-identified-collections.git", from: "1.1.1"),
    .package(url: "https://github.com/pointfreeco/swift-dependencies.git", from: "1.11.0"),
    .package(url: "https://github.com/pointfreeco/swift-case-paths.git", from: "1.7.2"),
    .package(url: "https://github.com/gonzalezreal/swift-markdown-ui.git", from: "2.4.0"),
    .package(url: "https://github.com/apple/swift-collections", from: "1.4.0"),
    .package(url: "https://github.com/gonzalezreal/NetworkImage", from: "6.0.1"),
    .package(url: "https://github.com/pointfreeco/combine-schedulers", from: "1.1.0"),
    .package(url: "https://github.com/pointfreeco/swift-clocks", from: "1.0.6"),
    .package(url: "https://github.com/pointfreeco/swift-concurrency-extras", from: "1.3.2"),
    .package(url: "https://github.com/pointfreeco/swift-custom-dump", from: "1.5.0"),
    .package(url: "https://github.com/pointfreeco/swift-navigation", from: "2.7.0"),
    .package(url: "https://github.com/pointfreeco/swift-perception", from: "2.0.9"),
    .package(url: "https://github.com/pointfreeco/swift-sharing", from: "2.7.4"),
    .package(url: "https://github.com/pointfreeco/xctest-dynamic-overlay", from: "1.9.0"),
    .package(url: "https://github.com/swiftlang/swift-syntax", from: "602.0.0"),
    .package(url: "https://github.com/swiftlang/swift-cmark", from: "0.7.1"),
  ]
)
