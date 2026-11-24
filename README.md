# MWPhotoBrowser

forked from [mwaterfall/MWPhotoBrowser](https://github.com/mwaterfall/MWPhotoBrowser)。

优化适配iOS26.0，适配自己项目，增加手势拖拽关闭的图片浏览器



### 提交**记录**

### Version 3.1.0

> 2026年11月23日

- 提交v3.1.0版本
- 优化转场动画，增加MWToolBar



### Version 3.0.0

> 2026年11月11日

- 提交v3.0.0版本





## Installation

MWPhotoBrowser 同时支持 **CocoaPods** 与 **Swift Package Manager**，两种方式共用同一份源码，任选其一即可。

### CocoaPods

```ruby
pod 'MWPhotoBrowser', :git => 'https://github.com/Gatnnj/MWPhotoBrowser.git', :branch => 'develop'
```

版本 tag 发布后也可写 `pod 'MWPhotoBrowser', '~> 3.1.0'`。

### Swift Package Manager

Xcode 中 `File → Add Package Dependencies…` 粘贴仓库地址：

```
https://github.com/Gatnnj/MWPhotoBrowser.git
```

或在 `Package.swift` 中声明依赖：

```swift
dependencies: [
    .package(url: "https://github.com/Gatnnj/MWPhotoBrowser.git", branch: "develop")
    // 版本 tag 发布后可改为 from: "3.1.0"
]
```

最低支持 **iOS 15.0**，SDWebImage 依赖（≥ 5.21.7）自动解析。SPM 侧资源包名为 `MWPhotoBrowser_MWPhotoBrowser.bundle`，库内已自动识别，无需额外配置。


## Usage

To run the example project, clone the repo, and run `pod install` from the Example directory first.

Then import the photo browser into your source files (or into your bridging header if you're using with Swift and not using frameworks with Cocoapods):

```obj-c
#import "MWPhotoBrowser.h"
```

If you are using Swift and frameworks, then you can just import the browser into your Swift source file:

```swift
import MWPhotoBrowser
```


## Author

Michael Waterfall, michael@d3i.com

Gatnnj, gatnnj880@gmail.com


## License

MWPhotoBrowser is available under the MIT license. See the LICENSE file for more info.


## Notes

Demo photos kindly provided by [Oliver Waters](<http://twitter.com/oliverwaters>).
