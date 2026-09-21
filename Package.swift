// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "otp",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "OTPCore", path: "Sources/OTPCore"),
        .executableTarget(name: "otp", dependencies: ["OTPCore"], path: "Sources/otp"),
    ]
)
