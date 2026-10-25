// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "ClipNest", platforms: [.macOS(.v13)],
  dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
  targets: [
    .systemLibrary(name: "CSQLite"),
    .executableTarget(
      name: "ClipNest", dependencies: ["CSQLite", .product(name: "Sparkle", package: "Sparkle")],
      linkerSettings: [
        .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
      ]),
  ])
