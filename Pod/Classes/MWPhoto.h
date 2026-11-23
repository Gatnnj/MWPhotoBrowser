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

@property (nonatomic) BOOL emptyImage;
/// 切换后会在已加载图片上异步重新处理，并通知浏览器刷新当前页。
@property (nonatomic) BOOL isBlur;
/// 高斯模糊半径，默认 30；图片已加载时修改也会重新处理。
@property (nonatomic) CGFloat radius;

+ (MWPhoto *)photoWithImage:(UIImage *)image;
+ (MWPhoto *)photoWithURL:(NSURL *)url;
+ (MWPhoto *)photoWithURL:(NSURL *)url isBlur:(BOOL)isBlur;
+ (MWPhoto *)photoWithAsset:(PHAsset *)asset targetSize:(CGSize)targetSize;

/// Asynchronously remove all generated Gaussian blur files from the caches directory.
+ (void)clearBlurCache;
/// Completion is called on the main queue after cache files are removed.
+ (void)clearBlurCacheWithCompletion:(nullable void (^)(void))completion;
/// Asynchronously remove generated blur files for a URL, at every radius.
+ (void)clearBlurCacheForURL:(NSURL *)url;
+ (void)clearBlurCacheForURL:(NSURL *)url completion:(nullable void (^)(void))completion;
- (instancetype)init;
- (instancetype)initWithImage:(UIImage *)image;
- (instancetype)initWithURL:(NSURL *)url;
- (instancetype)initWithURL:(NSURL *)url isBlur:(BOOL)isBlur;
- (instancetype)initWithAsset:(PHAsset *)asset targetSize:(CGSize)targetSize;

@end

NS_ASSUME_NONNULL_END

