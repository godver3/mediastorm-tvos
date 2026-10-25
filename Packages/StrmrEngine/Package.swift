// swift-tools-version: 6.1

import PackageDescription

// AetherEngine with the optional components the app uses. XcodeGen drops a package's `traits:`
// (and the generated .pbxproj is not checked in), so the traits are set here and the app depends
// on this package instead (AetherEngine README › Optional components).
//   TrueHDObjectAudio / DTSXObjectAudio: Atmos and DTS:X heights (Settings › Playback › Atmos).
//   DolbyVisionStillReshaping: DV Profile 5 scrub thumbnails, built in by default before 7.39.
let package = Package(
    name: "StrmrEngine",
    platforms: [.tvOS(.v18)],
    products: [
        .library(name: "StrmrEngine", targets: ["StrmrEngine"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/superuser404notfound/AetherEngine",
            exact: "7.47.0",
            traits: ["TrueHDObjectAudio", "DTSXObjectAudio", "DolbyVisionStillReshaping"]
        ),
    ],
    targets: [
        .target(
            name: "StrmrEngine",
            dependencies: [.product(name: "AetherEngine", package: "AetherEngine")]
        ),
    ]
)
