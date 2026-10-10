// swift-tools-version: 6.0
import PackageDescription

// Winrate - узкий счётчик побед и поражений поверх экрана (для трейдинга).
// Собирается без Xcode, только Command Line Tools: ./build.sh
let package = Package(
    name: "Winrate",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Winrate",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
