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

// This class models a photo/image and it's caption
// If you want to handle photos, caching, decompression
// yourself then you can simply ensure your custom data model
// conforms to MWPhotoProtocol
@interface MWPhoto : NSObject <MWPhoto>

@property (nonatomic, strong) NSString *caption;
@property (nonatomic, strong) NSURL *videoURL;
@property (nonatomic) BOOL emptyImage;
@property (nonatomic) BOOL isVideo;
/// 切换后会在已加载图片上异步重新处理，并通知浏览器刷新当前页。
@property (nonatomic) BOOL isBlur;
/// 高斯模糊半径，默认 30；图片已加载时修改也会重新处理。
@property (nonatomic) CGFloat radius;
/// 是否压缩图片
@property (nonatomic) BOOL isZoom;

+ (MWPhoto *)photoWithImage:(UIImage *)image;
+ (MWPhoto *)photoWithURL:(NSURL *)url;
+ (MWPhoto *)photoWithURL:(NSURL *)url isBlur:(BOOL)isBlur;
+ (MWPhoto *)photoWithAsset:(PHAsset *)asset targetSize:(CGSize)targetSize;
+ (MWPhoto *)videoWithURL:(NSURL *)url; // Initialise video with no poster image

/// Asynchronously remove all generated Gaussian blur files from the caches directory.
+ (void)clearBlurCache;
/// Completion is called on the main queue after cache files are removed.
+ (void)clearBlurCacheWithCompletion:(void (^)(void))completion;
/// Asynchronously remove generated blur files for a URL, at every radius.
+ (void)clearBlurCacheForURL:(NSURL *)url;
+ (void)clearBlurCacheForURL:(NSURL *)url completion:(void (^)(void))completion;
/// Remove generated grid thumbnail files from the caches directory, or for one URL.
+ (void)clearZoomCache;
+ (void)clearZoomCacheWithCompletion:(void (^)(void))completion;
+ (void)clearZoomCacheForURL:(NSURL *)url;
+ (void)clearZoomCacheForURL:(NSURL *)url completion:(void (^)(void))completion;
/// Asynchronously clear both generated blur and grid thumbnail caches.
+ (void)clearBlurAndZoomCache;
+ (void)clearBlurAndZoomCacheWithCompletion:(void (^)(void))completion;

- (id)init;
- (id)initWithImage:(UIImage *)image;
- (id)initWithURL:(NSURL *)url;
- (id)initWithURL:(NSURL *)url isBlur:(BOOL)isBlur;
- (id)initWithAsset:(PHAsset *)asset targetSize:(CGSize)targetSize;
- (id)initWithVideoURL:(NSURL *)url;

@end

