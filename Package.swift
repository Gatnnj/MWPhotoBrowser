// swift-tools-version:5.9
//
//  Package.swift
//  MWPhotoBrowser
//
//  Swift Package Manager 描述文件，与 MWPhotoBrowser.podspec 双轨并存：
//  · CocoaPods 用户走 podspec（source_files + resource_bundles，产物 MWPhotoBrowser.bundle）
//  · SPM 用户走本文件（target path = Pod，产物 MWPhotoBrowser_MWPhotoBrowser.bundle）
//
//  UIImage+MWPhotoBrowser.m 里的 mw_resourceBundle 已按候选名枚举上述两种 bundle，
//  因此两种集成方式共用同一份源码，不需要任何条件编译。
//

import PackageDescription

let package = Package(
    name: "MWPhotoBrowser",
    platforms: [
        .iOS(.v13)
    ],
    products: [
        .library(name: "MWPhotoBrowser", targets: ["MWPhotoBrowser"])
    ],
    dependencies: [
        .package(url: "https://github.com/SDWebImage/SDWebImage.git", from: "5.21.7")
    ],
    targets: [
        .target(
            name: "MWPhotoBrowser",
            dependencies: [
                .product(name: "SDWebImage", package: "SDWebImage")
            ],
            // 必须是 Pod（父目录）：SPM 不允许 resources 指向 target 目录之外，
            // 而 xcassets 在 Pod/Assets、源码在 Pod/Classes，只有把 Pod 当根才能同时覆盖。
            path: "Pod",
            sources: ["Classes"],
            resources: [
                // .process 才会走 actool 编成 Assets.car；用 .copy 会原样拷贝导致 imageNamed:inBundle: 取不到图
                .process("Assets/MWPhotoBrowser.xcassets")
            ],
            // 默认是 include/，本库 .h/.m 混排在 Classes 下，必须显式指定，否则头文件对外不可见
            publicHeadersPath: "Classes",
            linkerSettings: [
                .linkedFramework("Photos"),
                .linkedFramework("ImageIO"),
                .linkedFramework("QuartzCore")
            ]
        )
    ]
)
