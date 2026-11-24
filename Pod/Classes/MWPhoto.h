//
//  MWPhoto.h
//  MWPhotoBrowser
//
//  Created by Michael Waterfall on 17/10/2010.
//  Copyright 2010 d3i. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Photos/Photos.h>
#import "MWPhotoProtocol.h"


NS_ASSUME_NONNULL_BEGIN

@interface MWPhoto : NSObject <MWPhoto>

/// 空图片标记：为 YES 时不显示加载失败图标
@property (nonatomic) BOOL emptyImage;
/// 切换后会在已加载图片上异步重新处理，并通知浏览器刷新当前页。
@property (nonatomic) BOOL isBlur;
/// 高斯模糊半径，默认 30；图片已加载时修改也会重新处理。
@property (nonatomic) CGFloat radius;

/// 工厂：从 UIImage 创建
+ (MWPhoto *)photoWithImage:(UIImage *)image;
/// 工厂：从网络/本地 URL 创建
+ (MWPhoto *)photoWithURL:(NSURL *)url;
/// 工厂：从 URL 创建并指定是否高斯模糊
+ (MWPhoto *)photoWithURL:(NSURL *)url isBlur:(BOOL)isBlur;
/// 工厂：从 PHAsset 创建，指定目标尺寸
+ (MWPhoto *)photoWithAsset:(PHAsset *)asset targetSize:(CGSize)targetSize;

/// 异步清空缓存目录下所有已生成的高斯模糊文件
+ (void)clearBlurCache;
/// 异步清空模糊缓存，完成后在主线程回调
+ (void)clearBlurCacheWithCompletion:(nullable void (^)(void))completion;
/// 异步清空某个 URL 在所有半径下生成的模糊文件
+ (void)clearBlurCacheForURL:(NSURL *)url;
/// 异步清空某个 URL 的模糊文件，完成后在主线程回调
+ (void)clearBlurCacheForURL:(NSURL *)url completion:(nullable void (^)(void))completion;

/// 初始化（无图片，供子类使用）
- (instancetype)init;
/// 以 UIImage 初始化
- (instancetype)initWithImage:(UIImage *)image;
/// 以 URL 初始化
- (instancetype)initWithURL:(NSURL *)url;
/// 以 URL 初始化并指定是否高斯模糊
- (instancetype)initWithURL:(NSURL *)url isBlur:(BOOL)isBlur;
/// 以 PHAsset 初始化，指定目标尺寸
- (instancetype)initWithAsset:(PHAsset *)asset targetSize:(CGSize)targetSize;

@end

NS_ASSUME_NONNULL_END

