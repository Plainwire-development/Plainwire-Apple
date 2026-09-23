// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "PlainwireCore",
  platforms: [
    .iOS(.v18),
    .macOS(.v15),
  ],
  products: [
    .library(name: "PlainwireCore", targets: ["PlainwireCore"])
  ],
  targets: [
    .target(
      name: "PlainwireCore",
      path: "Sources/PlainwireCore",
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
    .testTarget(
      name: "PlainwireCoreTests",
      dependencies: ["PlainwireCore"],
      path: "Tests/PlainwireCoreTests",
      swiftSettings: [.swiftLanguageMode(.v6)]
    ),
  ]
)
