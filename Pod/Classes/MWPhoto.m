//
//  MWPhoto.m
//  MWPhotoBrowser
//
//  Created by Michael Waterfall on 17/10/2010.
//  Copyright 2010 d3i. All rights reserved.
//

#if __has_include(<SDWebImage/SDWebImage.h>)
#import <SDWebImage/SDWebImage.h>
#else
#import "SDWebImage.h"
#endif
// AssetsLibrary（iOS 9 废弃）替换为 Photos 框架
#import <Photos/Photos.h>
#import <CommonCrypto/CommonDigest.h>
#import <ImageIO/ImageIO.h>
#import <math.h>
#import "MWPhoto.h"
#import "MWPhotoBrowser.h"
#import "UIImage+MWPhotoBrowser.h"

static dispatch_queue_t MWPhotoBlurQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.mwphotobrowser.image-blur", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

/// 模糊图缓存目录。
static NSString *MWPhotoImageCacheDirectory(void) {
    static NSString *directory;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        NSString *caches = paths.firstObject;
        directory = [[caches stringByAppendingPathComponent:@"MWPhotoBrowserImageCache"] copy];

        // 旧实现分别使用 MWPhotoBrowserBlurCache / MWPhotoBrowserZoomCache 两个目录，
        // 这里一次性清理，避免遗留数据继续占用空间（两者都是可重建的缓存）
        NSFileManager *fileManager = [NSFileManager defaultManager];
        for (NSString *legacyName in @[@"MWPhotoBrowserBlurCache", @"MWPhotoBrowserZoomCache"]) {
            NSString *legacyPath = [caches stringByAppendingPathComponent:legacyName];
            if ([fileManager fileExistsAtPath:legacyPath]) {
                [fileManager removeItemAtPath:legacyPath error:nil];
            }
        }
    });
    return directory;
}

static NSString *MWPhotoBlurCacheDirectory(void) {
    return MWPhotoImageCacheDirectory();
}

/// 只取 URL 路径作为缓存键，忽略可能含轮换凭证的 query 参数
static NSString *MWPhotoCanonicalBlurCacheURL(NSURL *url) {
    if (!url) return nil;
    return [url.absoluteString componentsSeparatedByString:@"?"].firstObject;
}

static NSString *MWPhotoBlurCachePrefix(NSURL *url) {
    if (!url) return nil;
    NSData *data = [MWPhotoCanonicalBlurCacheURL(url) dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", digest[i]];
    return hex;
}

static NSString *MWPhotoBlurCachePath(NSURL *url, CGFloat radius) {
    NSString *prefix = MWPhotoBlurCachePrefix(url);
    if (!prefix) return nil;
    NSString *radiusKey = [NSString stringWithFormat:@"%.3f", radius];
    // blur_ 前缀用于标记生成的模糊图缓存。
    return [[MWPhotoBlurCacheDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"blur_%@_%@.jpg", prefix, radiusKey]] copy];
}

/// 读取模糊缓存图，并按配套 plist 恢复 scale 与方向
static UIImage *MWPhotoReadBlurCache(NSString *path) {
    UIImage *decoded = [UIImage imageWithContentsOfFile:path];
    if (!decoded.CGImage) return nil;
    NSDictionary *metadata = [NSDictionary dictionaryWithContentsOfFile:[path stringByAppendingPathExtension:@"plist"]];
    CGFloat scale = [metadata[@"scale"] doubleValue];
    UIImageOrientation orientation = metadata ? [metadata[@"orientation"] integerValue] : decoded.imageOrientation;
    if (scale <= 0) scale = decoded.scale;
    return [UIImage imageWithCGImage:decoded.CGImage scale:scale orientation:orientation];
}

#pragma mark - Cache Size Control

/// 缓存目录总容量上限
static const unsigned long long MWPhotoImageCacheLimitBytes = 400ULL * 1024ULL * 1024ULL;
/// 淘汰目标：删除到上限的 70%，避免每次写入都触发一轮删除
static const double MWPhotoImageCacheTrimRatio = 0.7;
/// 两次容量检查之间的最小间隔（秒）
static const CFTimeInterval MWPhotoImageCacheCheckInterval = 60.0;
/// 单次最多删除的文件数，避免长时间占用串行队列
static const NSUInteger MWPhotoImageCacheMaxDeletionsPerPass = 200;

static BOOL MWPhotoCacheFileIsBlurJPEG(NSString *fileName) {
    return [fileName hasPrefix:@"blur_"] && [fileName hasSuffix:@".jpg"];
}

/// 目录总大小超过上限时，按修改时间从旧到新删除，直到降到目标容量。
/// 内部派发到模糊缓存所用的串行队列，与写入、清理操作保持顺序一致。
static void MWPhotoEnforceImageCacheLimitIfNeeded(void) {
    dispatch_async(MWPhotoBlurQueue(), ^{
        // 节流：避免每写一张图都全量扫描一次目录
        static CFTimeInterval lastCheck = 0;
        CFTimeInterval now = CFAbsoluteTimeGetCurrent();
        if (lastCheck > 0 && (now - lastCheck) < MWPhotoImageCacheCheckInterval) {
            return;
        }
        lastCheck = now;

        NSString *directory = MWPhotoImageCacheDirectory();
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSArray<NSString *> *fileNames = [fileManager contentsOfDirectoryAtPath:directory error:nil];
        if (!fileNames.count) return;

        unsigned long long totalBytes = 0;
        NSMutableArray<NSDictionary *> *entries = [NSMutableArray arrayWithCapacity:fileNames.count];
        for (NSString *fileName in fileNames) {
            NSString *path = [directory stringByAppendingPathComponent:fileName];
            NSDictionary *attributes = [fileManager attributesOfItemAtPath:path error:nil];
            if (!attributes) continue;
            unsigned long long size = [attributes[NSFileSize] unsignedLongLongValue];
            totalBytes += size;
            [entries addObject:@{
                @"path": path,
                @"size": @(size),
                @"date": attributes[NSFileModificationDate] ?: [NSDate distantPast],
                @"name": fileName
            }];
        }
        if (totalBytes <= MWPhotoImageCacheLimitBytes) return;

        // 修改时间升序：最旧的排在前面，优先删除
        [entries sortUsingComparator:^NSComparisonResult(NSDictionary *lhs, NSDictionary *rhs) {
            return [lhs[@"date"] compare:rhs[@"date"]];
        }];

        unsigned long long targetBytes = (unsigned long long)(MWPhotoImageCacheLimitBytes * MWPhotoImageCacheTrimRatio);
        unsigned long long removedBytes = 0;
        NSUInteger removedCount = 0;
        for (NSDictionary *entry in entries) {
            if (totalBytes - removedBytes <= targetBytes) break;
            if (removedCount >= MWPhotoImageCacheMaxDeletionsPerPass) break;

            NSString *path = entry[@"path"];
            // 删除模糊图 JPEG 时同步清理配套的 .plist，避免产生孤儿文件
            if (MWPhotoCacheFileIsBlurJPEG(entry[@"name"])) {
                [fileManager removeItemAtPath:[path stringByAppendingPathExtension:@"plist"] error:nil];
            }
            if ([fileManager removeItemAtPath:path error:nil]) {
                removedBytes += [entry[@"size"] unsignedLongLongValue];
                removedCount++;
            }
        }
    });
}

/// 写入模糊图 JPEG 与配套元数据 plist，并触发容量淘汰
static void MWPhotoWriteBlurCache(UIImage *image, NSString *path) {
    if (!image || !path) return;
    NSString *directory = [path stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    NSData *data = UIImageJPEGRepresentation(image, 0.94);
    if (!data || ![data writeToFile:path options:NSDataWritingAtomic error:nil]) return;
    NSDictionary *metadata = @{@"scale": @(image.scale), @"orientation": @(image.imageOrientation)};
    [metadata writeToFile:[path stringByAppendingPathExtension:@"plist"] atomically:YES];
    MWPhotoEnforceImageCacheLimitIfNeeded();
}

@interface MWPhoto () {

    BOOL _loadingInProgress;
    id <SDWebImageOperation> _webImageOperation;
    id <SDWebImageOperation> _gridWebImageOperation;
    PHImageRequestID _assetRequestID;
    NSUInteger _loadGeneration;
    NSUInteger _gridLoadGeneration;
    CGSize _gridThumbnailPixelSize;
    BOOL _gridThumbnailLoading;
    BOOL _gridThumbnailDemanded;
        
}

@property (nonatomic, strong) UIImage *image;
@property (nonatomic, strong) NSURL *photoURL;
@property (nonatomic, strong) PHAsset *asset;
@property (nonatomic) CGSize assetTargetSize;
@property (nonatomic, strong) UIImage *sourceImage;
@property (nonatomic, strong) UIImage *gridThumbnailImage;
- (void)imageLoadingComplete;
- (void)completeLoadingWithImage:(UIImage *)image generation:(NSUInteger)generation;
- (void)processSourceImage:(UIImage *)image generation:(NSUInteger)generation;
- (void)finishLoadingSourceImage:(UIImage *)image generation:(NSUInteger)generation;
- (void)removeSDWebImageMemoryCacheEntries;

@end

@implementation MWPhoto

@synthesize underlyingImage = _underlyingImage; // synth property from protocol

#pragma mark - Class Methods

+ (void)clearBlurCache {
    [self clearBlurCacheWithCompletion:nil];
}

+ (void)clearBlurCacheForURL:(NSURL *)url {
    [self clearBlurCacheForURL:url completion:nil];
}

+ (void)clearBlurCacheWithCompletion:(void (^)(void))completion {
    dispatch_async(MWPhotoBlurQueue(), ^{
        // 只清理模糊图相关文件（blur_ 前缀，含配套的 .plist）。
        NSString *directory = MWPhotoImageCacheDirectory();
        NSFileManager *fileManager = [NSFileManager defaultManager];
        for (NSString *fileName in [fileManager contentsOfDirectoryAtPath:directory error:nil]) {
            if ([fileName hasPrefix:@"blur_"]) {
                [fileManager removeItemAtPath:[directory stringByAppendingPathComponent:fileName] error:nil];
            }
        }
        if (completion) dispatch_async(dispatch_get_main_queue(), completion);
    });
}

+ (void)clearBlurCacheForURL:(NSURL *)url completion:(void (^)(void))completion {
    NSString *prefix = MWPhotoBlurCachePrefix(url);
    if (!prefix) {
        if (completion) dispatch_async(dispatch_get_main_queue(), completion);
        return;
    }
    dispatch_async(MWPhotoBlurQueue(), ^{
        NSString *directory = MWPhotoBlurCacheDirectory();
        NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:directory error:nil];
        NSString *filePrefix = [NSString stringWithFormat:@"blur_%@_", prefix];
        for (NSString *file in files) {
            if ([file hasPrefix:filePrefix]) {
                [[NSFileManager defaultManager] removeItemAtPath:[directory stringByAppendingPathComponent:file] error:nil];
            }
        }
        if (completion) dispatch_async(dispatch_get_main_queue(), completion);
    });
}

+ (MWPhoto *)photoWithImage:(UIImage *)image {
	return [[MWPhoto alloc] initWithImage:image];
}

+ (MWPhoto *)photoWithURL:(NSURL *)url {
    return [[MWPhoto alloc] initWithURL:url];
}

+ (MWPhoto *)photoWithURL:(NSURL *)url isBlur:(BOOL)isBlur {
    return [[MWPhoto alloc] initWithURL:url isBlur:isBlur];
}

+ (MWPhoto *)photoWithAsset:(PHAsset *)asset targetSize:(CGSize)targetSize {
    return [[MWPhoto alloc] initWithAsset:asset targetSize:targetSize];
}


#pragma mark - Init

- (instancetype)init {
    if ((self = [super init])) {
        self.emptyImage = YES;
        [self setup];
    }
    return self;
}

- (instancetype)initWithImage:(UIImage *)image {
    if ((self = [super init])) {
        self.image = image;
        [self setup];
    }
    return self;
}

- (instancetype)initWithURL:(NSURL *)url {
    if ((self = [super init])) {
        self.photoURL = url;
        [self setup];
    }
    return self;
}

- (instancetype)initWithURL:(NSURL *)url isBlur:(BOOL)isBlur {
    if ((self = [super init])) {
        self.photoURL = url;
        self.isBlur = isBlur;
        self.radius = 30.0;
        [self setup];
    }
    return self;
}

- (instancetype)initWithAsset:(PHAsset *)asset targetSize:(CGSize)targetSize {
    if ((self = [super init])) {
        self.asset = asset;
        self.assetTargetSize = targetSize;
        [self setup];
    }
    return self;
}


- (void)setup {
    _assetRequestID = PHInvalidImageRequestID;
    if (_radius <= 0) _radius = 30.0;
}

- (void)dealloc {
    [self cancelAnyLoading];
}

#pragma mark - MWPhoto Protocol Methods

- (UIImage *)underlyingImage {
    return _underlyingImage;
}

- (void)setIsBlur:(BOOL)isBlur {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ self.isBlur = isBlur; });
        return;
    }
    if (_isBlur == isBlur) return;
    _isBlur = isBlur;
    self.gridThumbnailImage = nil;
    _gridThumbnailPixelSize = CGSizeZero;
    _gridLoadGeneration++;
    _gridThumbnailLoading = NO;
    [_gridWebImageOperation cancel];
    _gridWebImageOperation = nil;

    // 已加载的源图被保留，切换模糊开关无需更换 URL/模型即可在原图与模糊间切换
    UIImage *source = self.sourceImage ?: self.underlyingImage;
    if (!source) return; // 无现成源图则等待在途加载完成后按新标志处理
    self.sourceImage = source;
    NSUInteger generation = ++_loadGeneration;
    _loadingInProgress = YES;
    if (isBlur) {
        [self processSourceImage:source generation:generation];
    } else {
        self.underlyingImage = source;
        [self imageLoadingComplete];
    }
}

- (void)setRadius:(CGFloat)radius {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ self.radius = radius; });
        return;
    }
    CGFloat normalizedRadius = isfinite(radius) && radius > 0 ? radius : 30.0;
    if (fabs(_radius - normalizedRadius) < 0.001) return;
    _radius = normalizedRadius;
    if (_isBlur && self.sourceImage) {
        NSUInteger generation = ++_loadGeneration;
        _loadingInProgress = YES;
        [self processSourceImage:self.sourceImage generation:generation];
    }
}

- (void)loadUnderlyingImageAndNotify {
    NSAssert([[NSThread currentThread] isMainThread], @"This method must be called on the main thread.");
    if (_loadingInProgress) return;
    _loadingInProgress = YES;
    _loadGeneration++;
    @try {
        if (self.underlyingImage) {
            [self imageLoadingComplete];
        } else {
            [self performLoadUnderlyingImageAndNotify];
        }
    }
    @catch (NSException *exception) {
        self.underlyingImage = nil;
        _loadingInProgress = NO;
        [self imageLoadingComplete];
    }
    @finally {
    }
}

- (void)loadGridThumbnailAndNotifyWithPixelSize:(CGSize)pixelSize {
    NSAssert([[NSThread currentThread] isMainThread], @"This method must be called on the main thread.");
    pixelSize = CGSizeMake(MAX(1, ceil(pixelSize.width)), MAX(1, ceil(pixelSize.height)));
    _gridThumbnailDemanded = YES;

    if (self.gridThumbnailImage &&
        _gridThumbnailPixelSize.width >= pixelSize.width &&
        _gridThumbnailPixelSize.height >= pixelSize.height) {
        [self postCompleteNotification];
        return;
    }
    if (_gridThumbnailLoading) return;

    if (!_photoURL) {
        // 非 URL 来源走旧加载流程；大图单 URL 路径走下面的降采样请求
        [self loadUnderlyingImageAndNotify];
        return;
    }

    _gridThumbnailLoading = YES;
    NSUInteger generation = ++_gridLoadGeneration;
    _gridThumbnailPixelSize = pixelSize;
    SDWebImageContext *context = @{
        SDWebImageContextImageThumbnailPixelSize: [NSValue valueWithCGSize:pixelSize],
        // 解码缩略图不入 SDWebImage 内存缓存，压缩原图与缩略图变体留在磁盘复用
        SDWebImageContextStoreCacheType: @(SDImageCacheTypeDisk)
    };
    __weak typeof(self) weakSelf = self;
    _gridWebImageOperation = [[SDWebImageManager sharedManager] loadImageWithURL:_photoURL
                                                                           options:0
                                                                          context:context
                                                                         progress:^(NSInteger receivedSize, NSInteger expectedSize, NSURL * _Nullable targetURL) {
        MWPhoto *photo = weakSelf;
        if (!photo || expectedSize <= 0) return;
        float progress = receivedSize / (float)expectedSize;
        NSDictionary *info = @{@"progress": @(progress), @"photo": photo};
        [[NSNotificationCenter defaultCenter] postNotificationName:MWPHOTO_PROGRESS_NOTIFICATION object:info];
    } completed:^(UIImage * _Nullable image, NSData * _Nullable data, NSError * _Nullable error, SDImageCacheType cacheType, BOOL finished, NSURL * _Nullable imageURL) {
        if (!finished) return;
        MWPhoto *photo = weakSelf;
        if (!photo || generation != photo->_gridLoadGeneration) return;
        photo->_gridWebImageOperation = nil;

        void (^finish)(UIImage *) = ^(UIImage *gridImage) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (generation != photo->_gridLoadGeneration) return;
                photo->_gridThumbnailLoading = NO;
                if (photo->_gridThumbnailDemanded) {
                    photo.gridThumbnailImage = gridImage;
                    [photo postCompleteNotification];
                }
            });
        };
        if (image && photo.isBlur) {
            CGFloat blurRadius = MAX(2, MIN(photo.radius, MAX(pixelSize.width, pixelSize.height) / 16.0));
            dispatch_async(MWPhotoBlurQueue(), ^{
                @autoreleasepool {
                    finish([UIImage gaussianBlurWithImage:image ofRadius:blurRadius] ?: image);
                }
            });
        } else {
            finish(image);
        }
    }];
}

- (void)releaseGridThumbnailFromMemory {
    _gridThumbnailDemanded = NO;
    self.gridThumbnailImage = nil;
}

/// 按来源分发：已持有 UIImage 直接完成，否则按 URL/Asset 异步加载
- (void)performLoadUnderlyingImageAndNotify {

    if (_image) {
        // 已持有 UIImage，直接完成
        [self completeLoadingWithImage:_image generation:_loadGeneration];

    } else if (_photoURL) {

        // 按 URL 类型分发
        if ([[[_photoURL scheme] lowercaseString] isEqualToString:@"assets-library"]) {

            // 旧 assets-library URL：桥接 PHAsset 加载
            [self _performLoadUnderlyingImageAndNotifyWithAssetsLibraryURL: _photoURL];

        } else if ([_photoURL isFileURL]) {

            // 本地文件：异步读取
            [self _performLoadUnderlyingImageAndNotifyWithLocalFileURL: _photoURL];

        } else {

            // 网络 URL：SDWebImage 异步下载
            [self _performLoadUnderlyingImageAndNotifyWithWebURL: _photoURL];

        }

    } else if (_asset) {

        // Photos 资产加载
        [self _performLoadUnderlyingImageAndNotifyWithAsset: _asset targetSize:_assetTargetSize];

    } else {

        // 空图片，直接完成
        [self imageLoadingComplete];

    }
}

/// 网络 URL：走 SDWebImage 异步下载，进度与完成分别发通知
- (void)_performLoadUnderlyingImageAndNotifyWithWebURL:(NSURL *)url {
    NSUInteger generation = _loadGeneration;
    @try {
        SDWebImageManager *manager = [SDWebImageManager sharedManager];
        _webImageOperation = [manager loadImageWithURL:url options:0 progress:^(NSInteger receivedSize, NSInteger expectedSize, NSURL * _Nullable targetURL) {
            if (expectedSize > 0) {
                float progress = receivedSize / (float)expectedSize;
                NSDictionary* dict = [NSDictionary dictionaryWithObjectsAndKeys:
                                      [NSNumber numberWithFloat:progress], @"progress",
                                      self, @"photo", nil];
                [[NSNotificationCenter defaultCenter] postNotificationName:MWPHOTO_PROGRESS_NOTIFICATION object:dict];
            }
        } completed:^(UIImage * _Nullable image, NSData * _Nullable data, NSError * _Nullable error, SDImageCacheType cacheType, BOOL finished, NSURL * _Nullable imageURL) {
            if (error) {
                MWLog(@"SDWebImage failed to download image: %@", error);
            }
            if (!finished) return;
            // 显式 self 表明 block 有意引用，消除隐式 retain 警告（该 block 为一次性回调，无循环引用）
            self->_webImageOperation = nil;
            [self completeLoadingWithImage:image generation:generation];
        }];
    } @catch (NSException *e) {
        MWLog(@"Photo from web: %@", e);
        _webImageOperation = nil;
        [self imageLoadingComplete];
    }
}

/// 本地文件 URL：后台队列读取
- (void)_performLoadUnderlyingImageAndNotifyWithLocalFileURL:(NSURL *)url {
    NSUInteger generation = _loadGeneration;
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @autoreleasepool {
            @try {
                UIImage *image = [UIImage imageWithContentsOfFile:url.path];
                if (!image) {
                    MWLog(@"Error loading photo from path: %@", url.path);
                }
                [self completeLoadingWithImage:image generation:generation];
            } @catch (NSException *exception) {
                MWLog(@"Error loading photo from path: %@ (%@)", url.path, exception);
                [self completeLoadingWithImage:nil generation:generation];
            }
        }
    });
}

// 旧的 ALAssetsLibrary（iOS 9 废弃）替换为 Photos 框架：
// 先通过 Apple 官方的 ALAsset URL 桥接方法查出 PHAsset，再由 PHImageManager 加载全屏图
- (void)_performLoadUnderlyingImageAndNotifyWithAssetsLibraryURL:(NSURL *)url {
    NSUInteger generation = _loadGeneration;
    @try {
        // 根据旧 assets-library URL 查找对应的 PHAsset（官方桥接 API）
        // 该桥接方法自 iOS 11 被标记废弃，但它是消费旧 assets-library URL 的唯一途径，
        // 且当前系统仍可正常工作，因此局部抑制此废弃警告
        PHFetchResult<PHAsset *> *fetchResult;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        fetchResult = [PHAsset fetchAssetsWithALAssetURLs:@[url] options:nil];
#pragma clang diagnostic pop
        PHAsset *asset = fetchResult.firstObject;
        if (!asset) {
            // 未找到资源，等价旧 failureBlock 分支
            MWLog(@"Photo from asset library error: asset not found");
            [self completeLoadingWithImage:nil generation:generation];
            return;
        }

        // 请求全屏高质量图片，等价旧 ALAssetRepresentation.fullScreenImage
        PHImageRequestOptions *options = [PHImageRequestOptions new];
        options.networkAccessAllowed = YES;
        options.resizeMode = PHImageRequestOptionsResizeModeExact;
        options.deliveryMode = PHImageRequestOptionsDeliveryModeHighQualityFormat;

        [[PHImageManager defaultManager] requestImageForAsset:asset
                                                    targetSize:PHImageManagerMaximumSize
                                                   contentMode:PHImageContentModeDefault
                                                       options:options
                                                 resultHandler:^(UIImage *result, NSDictionary *info) {
            // 忽略中间的降级缩略图，只在最终结果时完成加载
            if ([info[PHImageResultIsDegradedKey] boolValue]) return;

            NSError *error = info[PHImageErrorKey];
            if (error) {
                MWLog(@"Photo from asset library error: %@", error);
            }
            [self completeLoadingWithImage:(error ? nil : result) generation:generation];
        }];
    } @catch (NSException *e) {
        MWLog(@"Photo from asset library error: %@", e);
        dispatch_async(dispatch_get_main_queue(), ^{
            if (generation == self->_loadGeneration) [self imageLoadingComplete];
        });
    }
}

/// PHAsset：通过 PHImageManager 按目标尺寸异步加载
- (void)_performLoadUnderlyingImageAndNotifyWithAsset:(PHAsset *)asset targetSize:(CGSize)targetSize {
    NSUInteger generation = _loadGeneration;
    
    PHImageManager *imageManager = [PHImageManager defaultManager];
    
    PHImageRequestOptions *options = [PHImageRequestOptions new];
    options.networkAccessAllowed = YES;
    options.resizeMode = PHImageRequestOptionsResizeModeFast;
    options.deliveryMode = PHImageRequestOptionsDeliveryModeHighQualityFormat;
    options.synchronous = false;
    options.progressHandler = ^(double progress, NSError *error, BOOL *stop, NSDictionary *info) {
        NSDictionary* dict = [NSDictionary dictionaryWithObjectsAndKeys:
                              [NSNumber numberWithDouble: progress], @"progress",
                              self, @"photo", nil];
        [[NSNotificationCenter defaultCenter] postNotificationName:MWPHOTO_PROGRESS_NOTIFICATION object:dict];
    };
    
    _assetRequestID = [imageManager requestImageForAsset:asset targetSize:targetSize contentMode:PHImageContentModeAspectFit options:options resultHandler:^(UIImage *result, NSDictionary *info) {
        if ([info[PHImageResultIsDegradedKey] boolValue]) return;
        [self completeLoadingWithImage:result generation:generation];
    }];

}

/// 统一处理全部来源的图片：模糊运算放到后台线程执行。
- (void)completeLoadingWithImage:(UIImage *)image generation:(NSUInteger)generation {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (generation != self->_loadGeneration) return;
        self.sourceImage = image;
        [self finishLoadingSourceImage:image generation:generation];
    });
}

/// 源图就绪：非模糊直接显示，否则进入模糊处理
- (void)finishLoadingSourceImage:(UIImage *)image generation:(NSUInteger)generation {
    if (generation != _loadGeneration) return;
    if (!image || !self.isBlur) {
        self.underlyingImage = image;
        [self imageLoadingComplete];
    } else {
        [self processSourceImage:image generation:generation];
    }
}

/// 后台做高斯模糊：先查磁盘缓存，未命中则计算并写缓存，主线程回调完成
- (void)processSourceImage:(UIImage *)image generation:(NSUInteger)generation {
    CGFloat radius = self.radius > 0 ? self.radius : 30.0;
    NSString *cachePath = MWPhotoBlurCachePath(self.photoURL, radius);
    dispatch_async(MWPhotoBlurQueue(), ^{
        @autoreleasepool {
            UIImage *blurredImage = cachePath ? MWPhotoReadBlurCache(cachePath) : nil;
            if (!blurredImage) {
                blurredImage = [UIImage gaussianBlurWithImage:image ofRadius:radius];
                if (cachePath && blurredImage && blurredImage != image) MWPhotoWriteBlurCache(blurredImage, cachePath);
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                if (generation != self->_loadGeneration || !self.isBlur) return;
                self.underlyingImage = blurredImage ?: image;
                [self imageLoadingComplete];
            });
        }
    });
}

/// 释放底层数据：取消加载并清内存，可从路径/URL 重新加载
- (void)unloadUnderlyingImage {
	[self cancelAnyLoading];
	[self removeSDWebImageMemoryCacheEntries];
	self.sourceImage = nil;
	self.gridThumbnailImage = nil;
	self.underlyingImage = nil;
}

/// 清掉 SDWebImage 内存缓存中的原图与缩略图条目，避免常驻占内存
- (void)removeSDWebImageMemoryCacheEntries {
    if (!_photoURL) return;

    SDWebImageManager *manager = [SDWebImageManager sharedManager];
    id<SDImageCache> imageCache = manager.imageCache;
    NSString *originalKey = [manager cacheKeyForURL:_photoURL context:nil];
    if (originalKey.length) {
        [imageCache removeImageForKey:originalKey cacheType:SDImageCacheTypeMemory completion:nil];
    }

    if (_gridThumbnailPixelSize.width > 0 && _gridThumbnailPixelSize.height > 0) {
        SDWebImageContext *context = @{
            SDWebImageContextImageThumbnailPixelSize: [NSValue valueWithCGSize:_gridThumbnailPixelSize]
        };
        NSString *thumbnailKey = [manager cacheKeyForURL:_photoURL context:context];
        if (thumbnailKey.length) {
            [imageCache removeImageForKey:thumbnailKey cacheType:SDImageCacheTypeMemory completion:nil];
        }
    }
}

/// 加载完成标记，在下一轮 runloop 发完成通知
- (void)imageLoadingComplete {
    NSAssert([[NSThread currentThread] isMainThread], @"This method must be called on the main thread.");
    _loadingInProgress = NO;
    // dispatch_after 延迟 0 等价于 performSelector:afterDelay:0，均在下一次 runloop 执行
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0), dispatch_get_main_queue(), ^{
        [self postCompleteNotification];
    });
}

- (void)postCompleteNotification {
    [[NSNotificationCenter defaultCenter] postNotificationName:MWPHOTO_LOADING_DID_END_NOTIFICATION
                                                        object:self];
}

/// 取消所有在途加载（网络/网格/Asset），并使旧 generation 失效
- (void)cancelAnyLoading {
    _loadGeneration++;
    _loadingInProgress = NO;
    if (_webImageOperation != nil) {
        [_webImageOperation cancel];
        _loadingInProgress = NO;
    }
    [self cancelImageRequest];
    _gridLoadGeneration++;
    _gridThumbnailLoading = NO;
    _gridThumbnailDemanded = NO;
    if (_gridWebImageOperation != nil) {
        [_gridWebImageOperation cancel];
        _gridWebImageOperation = nil;
    }
}

/// 取消 PHImageManager 的 Asset 请求
- (void)cancelImageRequest {
    if (_assetRequestID != PHInvalidImageRequestID) {
        [[PHImageManager defaultManager] cancelImageRequest:_assetRequestID];
        _assetRequestID = PHInvalidImageRequestID;
    }
}


@end
