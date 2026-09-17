// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "HealthLens", platforms: [.macOS(.v13), .iOS(.v17)], products: [.library(name: "TrainingCore", targets: ["TrainingCore"])], targets: [.target(name: "TrainingCore"), .testTarget(name: "TrainingCoreTests", dependencies: ["TrainingCore"])])
