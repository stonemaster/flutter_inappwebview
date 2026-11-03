// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "flutter_inappwebview_macos",
    platforms: [
        .macOS("10.14"),
    ],
    products: [
        .library(name: "flutter-inappwebview-macos", targets: ["flutter_inappwebview_macos"])
    ],
    dependencies: [
      // Upper-bounded to exclude swift-collections 1.3+: 1.7.x uses the new
      // noncopyable `Iterable` protocol (and `Failure` associated type) that
      // the prebuilt stdlib modules shipped in current xcross Darwin SDKs
      // (built by Apple Swift 6.3.x) do not expose, breaking cross builds
      // from Linux. Real Xcode toolchains also compile 1.2.x fine.
      .package(url: "https://github.com/apple/swift-collections.git", "1.2.1"..<"1.3.0")
    ],
    targets: [
        .target(
            name: "flutter_inappwebview_macos",
            dependencies: [
                .product(name: "Collections", package: "swift-collections")
            ],
            resources: [
                .process("Resources")
            ]
        )
    ]
)
