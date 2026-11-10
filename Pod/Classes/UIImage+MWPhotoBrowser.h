//
//  UIImage+MWPhotoBrowser.h
//  Pods
//
//  Created by Michael Waterfall on 05/07/2015.
//
//

#import <UIKit/UIKit.h>

@interface UIImage (MWPhotoBrowser)

/// 库自身资源所在 bundle。
/// 依次在「当前类所在 bundle（framework 内嵌）」「主 bundle（静态库 / XCFramework）」
/// 「带 pod 名前缀的 resource bundle」中查找 MWPhotoBrowser.bundle；
/// 都找不到时回退到 mainBundle（源码与资源被宿主 target 直接引用的场景）。
+ (nonnull NSBundle *)mw_resourceBundle;

/// 从库资源中取图。等价于 imageNamed:，但走库自己的资产命名空间，
/// 自动适配 @1x/@2x/@3x 与 Dark Mode；资源 bundle 缺失时回退到宿主 mainBundle。
+ (nullable UIImage *)mw_imageNamed:(nonnull NSString *)name;

/// 旧接口，保留以兼容外部调用；已改为按资源名解析，不再依赖 "XXX.bundle/YYY" 这类硬编码路径。
+ (UIImage *)imageForResourcePath:(NSString *)path ofType:(NSString *)type inBundle:(NSBundle *)bundle;
+ (UIImage *)clearImageWithSize:(CGSize)size;
+ (UIImage *)gaussianBlurWithImage:(UIImage *)originalImage ofRadius:(CGFloat)radius;


/// 压缩图片
+ (NSData *)mwCompressImage:(UIImage *)image;

/// 生成适合浏览展示的 JPEG 缩略图：最长边不超过 1280 像素，目标文件大小约 300 KB。
+ (nullable NSData *)mwCompressImageForThumbnail:(UIImage *)image;

/// @maskName 水印名
+ (NSData *)mwCompressImage:(UIImage *)image withMask:(NSString *)maskName;

/// @imageName 自定义图片水印 图片名
+ (NSData *)mwCompressImage:(UIImage *)image withCustomImage:(NSString *)imageName;

@end
