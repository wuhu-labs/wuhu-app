import ProjectDescription

let marketingVersion = "1.0.3"
let currentProjectVersion = "34"

let sharedSettings: SettingsDictionary = [
  "CODE_SIGN_STYLE": "Automatic",
  "DEVELOPMENT_TEAM": "97W7A3Y9GD",
  "MARKETING_VERSION": .string(marketingVersion),
  "CURRENT_PROJECT_VERSION": .string(currentProjectVersion),
]

let iOSSources: SourceFilesList = [
    .glob(
      "WuhuApp/Sources/**",
      excluding: [
        "WuhuApp/Sources/Updater.swift",
      ]
    ),
]

let macOSSources: SourceFilesList = [
  .glob("WuhuApp/Sources/**"),
]

let sharedResources: ResourceFileElements = [
  "WuhuApp/Sources/Assets.xcassets",
]

let iOSInfoPlist: [String: Plist.Value] = [
  "CFBundleDisplayName": "Wuhu",
  "CFBundleIconName": "AppIcon",
  "CFBundleShortVersionString": "$(MARKETING_VERSION)",
  "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
  "UILaunchScreen": [:],
  "ITSAppUsesNonExemptEncryption": false,
  "UISupportedInterfaceOrientations": [
    "UIInterfaceOrientationPortrait",
    "UIInterfaceOrientationPortraitUpsideDown",
    "UIInterfaceOrientationLandscapeLeft",
    "UIInterfaceOrientationLandscapeRight",
  ],
  "UISupportedInterfaceOrientations~ipad": [
    "UIInterfaceOrientationPortrait",
    "UIInterfaceOrientationPortraitUpsideDown",
    "UIInterfaceOrientationLandscapeLeft",
    "UIInterfaceOrientationLandscapeRight",
  ],
]

let macOSInfoPlist: [String: Plist.Value] = [
  "CFBundleDisplayName": "Wuhu",
  "CFBundleIconName": "AppIcon",
  "CFBundleShortVersionString": "$(MARKETING_VERSION)",
  "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
  "ITSAppUsesNonExemptEncryption": false,
  "NSMainStoryboardFile": "",
  "LSApplicationCategoryType": "public.app-category.developer-tools",
  "SUFeedURL": "https://wuhu.ai/releases/appcast.xml",
  "SUPublicEDKey": "cLD5wooImNT4Loh8TXGByHrSKnKtzU5T4As3L5L5BA4=",
  "SUEnableInstallerLauncherService": true,
  "NSAppTransportSecurity": [
    "NSAllowsArbitraryLoads": true,
  ],
]

let sharedDependencies: [TargetDependency] = [
  .external(name: "WuhuAPI"),
  .external(name: "WuhuClient"),
  .external(name: "WuhuCoreClient"),
  .external(name: "ComposableArchitecture"),
  .external(name: "IdentifiedCollections"),
  .external(name: "Dependencies"),
  .external(name: "CasePaths"),
  .external(name: "MarkdownUI"),
]

let project = Project(
  name: "WuhuApp",
  options: .options(
    automaticSchemesOptions: .disabled
  ),
  targets: [
    .target(
      name: "WuhuApp",
      destinations: .iOS,
      product: .app,
      bundleId: "ms.liu.wuhu.ios",
      deploymentTargets: .iOS("18.0"),
      infoPlist: .extendingDefault(with: iOSInfoPlist),
      sources: iOSSources,
      resources: sharedResources,
      entitlements: .file(path: "WuhuApp/Sources/WuhuApp.entitlements"),
      dependencies: sharedDependencies,
      settings: .settings(
        base: sharedSettings.merging([
          "SWIFT_VERSION": "6.0",
          "DISABLE_DIAMOND_PROBLEM_DIAGNOSTIC": "YES",
          "ENABLE_APP_SANDBOX": "YES",
          "CODE_SIGN_ALLOW_ENTITLEMENTS_MODIFICATION": "YES",
        ])
      )
    ),
    .target(
      name: "WuhuAppMac",
      destinations: .macOS,
      product: .app,
      productName: "Wuhu",
      bundleId: "ms.liu.wuhu.macos",
      deploymentTargets: .macOS("15.0"),
      infoPlist: .extendingDefault(with: macOSInfoPlist),
      sources: macOSSources,
      resources: sharedResources,
      entitlements: .file(path: "WuhuApp/Sources/WuhuAppMac.entitlements"),
      dependencies: sharedDependencies + [
        .xcframework(path: "WuhuApp/Frameworks/Sparkle.xcframework"),
      ],
      settings: .settings(
        base: sharedSettings.merging([
          "SWIFT_VERSION": "6.0",
          "DISABLE_DIAMOND_PROBLEM_DIAGNOSTIC": "YES",
          "ENABLE_APP_SANDBOX": "NO",
          "ENABLE_HARDENED_RUNTIME": "YES",
          "CODE_SIGN_ALLOW_ENTITLEMENTS_MODIFICATION": "YES",
        ])
      )
    ),
  ],
  schemes: [
    .scheme(
      name: "WuhuApp",
      shared: true,
      buildAction: .buildAction(targets: ["WuhuApp"])
    ),
    .scheme(
      name: "WuhuAppMac",
      shared: true,
      buildAction: .buildAction(targets: ["WuhuAppMac"])
    ),
  ]
)
