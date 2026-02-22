// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "FinderWrapNavigator",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "FinderWrapNavigator", targets: ["FinderWrapNavigator"])
    ],
    targets: [
        .executableTarget(
            name: "FinderWrapNavigator",
            path: "FinderWrapNavigatorSources"
        )
    ]
)
