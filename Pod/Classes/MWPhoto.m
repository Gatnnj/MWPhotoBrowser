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

/// 模糊图与缩放缩略图共用同一个缓存目录，便于统一统计容量与淘汰。
/// 文件名前缀区分类型：blur_ 为模糊图（含配套 .plist 元数据），zoom_ 为缩放缩略图。
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

/// Cache by the URL path only; query parameters may contain rotating credentials.
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
    // blur_ 前缀用于与缩放缩略图区分（两者共用同一目录）
    return [[MWPhotoBlurCacheDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"blur_%@_%@.jpg", prefix, radiusKey]] copy];
}

static NSString *MWPhotoZoomCacheDirectory(void) {
    return MWPhotoImageCacheDirectory();
}

static NSString *MWPhotoZoomCachePath(NSURL *url) {
    NSString *prefix = MWPhotoBlurCachePrefix(url);
    return prefix ? [[MWPhotoZoomCacheDirectory() stringByAppendingPathComponent:[@"zoom_" stringByAppendingString:[prefix stringByAppendingString:@".jpg"]]] copy] : nil;
}

static UIImage *MWPhotoDecodeZoomData(NSData *data) {
    if (!data.length) return nil;
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)data, NULL);
    if (!source) return nil;
    NSDictionary *options = @{(id)kCGImageSourceShouldCache: @YES,
                              (id)kCGImageSourceShouldCacheImmediately: @YES};
    CGImageRef cgImage = CGImageSourceCreateImageAtIndex(source, 0, (__bridge CFDictionaryRef)options);
    CFRelease(source);
    if (!cgImage) return nil;
    UIImage *image = [UIImage imageWithCGImage:cgImage scale:1.0 orientation:UIImageOrientationUp];
    CGImageRelease(cgImage);
    return image;
}

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
    PHImageRequestID _assetRequestID;
    PHImageRequestID _assetVideoRequestID;
    NSUInteger _loadGeneration;
        
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
- (void)processGridThumbnailFromImage:(UIImage *)image generation:(NSUInteger)generation completion:(void (^)(void))completion;
- (void)finishLoadingSourceImage:(UIImage *)image generation:(NSUInteger)generation;

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
        // 与缩放缩略图共用同一目录，这里只清理模糊图相关文件（blur_ 前缀，
        // 含配套的 .plist），不能整目录删除
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

+ (void)clearZoomCache {
    [self clearZoomCacheWithCompletion:nil];
}

+ (void)clearZoomCacheWithCompletion:(void (^)(void))completion {
    dispatch_async(MWPhotoBlurQueue(), ^{
        // 与模糊图共用同一目录，这里只清理缩放缩略图（zoom_ 前缀）
        NSString *directory = MWPhotoImageCacheDirectory();
        NSFileManager *fileManager = [NSFileManager defaultManager];
        for (NSString *fileName in [fileManager contentsOfDirectoryAtPath:directory error:nil]) {
            if ([fileName hasPrefix:@"zoom_"]) {
                [fileManager removeItemAtPath:[directory stringByAppendingPathComponent:fileName] error:nil];
            }
        }
        if (completion) dispatch_async(dispatch_get_main_queue(), completion);
    });
}

+ (void)clearZoomCacheForURL:(NSURL *)url {
    [self clearZoomCacheForURL:url completion:nil];
}

+ (void)clearZoomCacheForURL:(NSURL *)url completion:(void (^)(void))completion {
    NSString *path = MWPhotoZoomCachePath(url);
    if (!path) {
        if (completion) dispatch_async(dispatch_get_main_queue(), completion);
        return;
    }
    dispatch_async(MWPhotoBlurQueue(), ^{
        [[NSFileManager defaultManager] removeItemAtPath:path error:nil];
        if (completion) dispatch_async(dispatch_get_main_queue(), completion);
    });
}

+ (void)clearBlurAndZoomCache {
    [self clearBlurAndZoomCacheWithCompletion:nil];
}

+ (void)clearBlurAndZoomCacheWithCompletion:(void (^)(void))completion {
    dispatch_async(MWPhotoBlurQueue(), ^{
        // 两类缓存现已共用一个目录，整目录删除即可
        NSFileManager *fileManager = [NSFileManager defaultManager];
        [fileManager removeItemAtPath:MWPhotoImageCacheDirectory() error:nil];
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

+ (MWPhoto *)videoWithURL:(NSURL *)url {
    return [[MWPhoto alloc] initWithVideoURL:url];
}

#pragma mark - Init

- (id)init {
    if ((self = [super init])) {
        self.emptyImage = YES;
        [self setup];
    }
    return self;
}

- (id)initWithImage:(UIImage *)image {
    if ((self = [super init])) {
        self.image = image;
        [self setup];
    }
    return self;
}

- (id)initWithURL:(NSURL *)url {
    if ((self = [super init])) {
        self.photoURL = url;
        [self setup];
    }
    return self;
}

- (id)initWithURL:(NSURL *)url isBlur:(BOOL)isBlur {
    if ((self = [super init])) {
        self.photoURL = url;
        self.isBlur = isBlur;
        self.radius = 30.0;
        [self setup];
    }
    return self;
}

- (id)initWithAsset:(PHAsset *)asset targetSize:(CGSize)targetSize {
    if ((self = [super init])) {
        self.asset = asset;
        self.assetTargetSize = targetSize;
        self.isVideo = asset.mediaType == PHAssetMediaTypeVideo;
        [self setup];
    }
    return self;
}

- (id)initWithVideoURL:(NSURL *)url {
    if ((self = [super init])) {
        self.videoURL = url;
        self.isVideo = YES;
        self.emptyImage = YES;
        [self setup];
    }
    return self;
}

- (void)setup {
    _assetRequestID = PHInvalidImageRequestID;
    _assetVideoRequestID = PHInvalidImageRequestID;
    if (_radius <= 0) _radius = 30.0;
}

- (void)dealloc {
    [self cancelAnyLoading];
}

#pragma mark - Video

- (void)setVideoURL:(NSURL *)videoURL {
    _videoURL = videoURL;
    self.isVideo = YES;
}

- (void)getVideoURL:(void (^)(NSURL *url))completion {
    if (_videoURL) {
        completion(_videoURL);
    } else if (_asset && _asset.mediaType == PHAssetMediaTypeVideo) {
        [self cancelVideoRequest]; // Cancel any existing
        PHVideoRequestOptions *options = [PHVideoRequestOptions new];
        options.networkAccessAllowed = YES;
        typeof(self) __weak weakSelf = self;
        _assetVideoRequestID = [[PHImageManager defaultManager] requestAVAssetForVideo:_asset options:options resultHandler:^(AVAsset *asset, AVAudioMix *audioMix, NSDictionary *info) {
            
            // dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{ // Testing
            typeof(self) strongSelf = weakSelf;
            if (!strongSelf) return;
            strongSelf->_assetVideoRequestID = PHInvalidImageRequestID;
            if ([asset isKindOfClass:[AVURLAsset class]]) {
                completion(((AVURLAsset *)asset).URL);
            } else {
                completion(nil);
            }
            
        }];
    }
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

    // A source image is retained while loaded, so entitlement changes can switch
    // between the original and blurred rendering without replacing the URL/model.
    UIImage *source = self.sourceImage ?: self.underlyingImage;
    if (!source) return; // An in-flight fetch will use the updated flag on completion.
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

- (void)setIsZoom:(BOOL)isZoom {
    if (![NSThread isMainThread]) {
        dispatch_async(dispatch_get_main_queue(), ^{ self.isZoom = isZoom; });
        return;
    }
    if (_isZoom == isZoom) return;
    _isZoom = isZoom;
    if (!isZoom) {
        self.gridThumbnailImage = nil;
        UIImage *source = self.sourceImage ?: self.underlyingImage;
        if (_loadingInProgress && source) {
            NSUInteger generation = ++_loadGeneration;
            [self finishLoadingSourceImage:source generation:generation];
        }
        return;
    }
    UIImage *source = self.sourceImage ?: self.underlyingImage;
    if (!source) return; // The active image request will create the thumbnail on completion.
    NSUInteger generation = ++_loadGeneration;
    _loadingInProgress = YES;
    [self processGridThumbnailFromImage:source generation:generation completion:^{
        [self finishLoadingSourceImage:source generation:generation];
    }];
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

// Set the underlyingImage
- (void)performLoadUnderlyingImageAndNotify {
    
    // Get underlying image
    if (_image) {
        
        // We have UIImage!
        [self completeLoadingWithImage:_image generation:_loadGeneration];
        
    } else if (_photoURL) {
        
        // Check what type of url it is
        if ([[[_photoURL scheme] lowercaseString] isEqualToString:@"assets-library"]) {
            
            // Load from assets library
            [self _performLoadUnderlyingImageAndNotifyWithAssetsLibraryURL: _photoURL];
            
        } else if ([_photoURL isFileURL]) {
            
            // Load from local file async
            [self _performLoadUnderlyingImageAndNotifyWithLocalFileURL: _photoURL];
            
        } else {
            
            // Load async from web (using SDWebImage)
            [self _performLoadUnderlyingImageAndNotifyWithWebURL: _photoURL];
            
        }
        
    } else if (_asset) {
        
        // Load from photos asset
        [self _performLoadUnderlyingImageAndNotifyWithAsset: _asset targetSize:_assetTargetSize];
        
    } else {
        
        // Image is empty
        [self imageLoadingComplete];
        
    }
}

// Load from local file
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

// Load from local file
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

// Load from asset library async
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

// Load from photos library
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
        if (image && self.isZoom) {
            [self processGridThumbnailFromImage:image generation:generation completion:^{
                [self finishLoadingSourceImage:image generation:generation];
            }];
        } else {
            [self finishLoadingSourceImage:image generation:generation];
        }
    });
}

- (void)finishLoadingSourceImage:(UIImage *)image generation:(NSUInteger)generation {
    if (generation != _loadGeneration) return;
    if (!image || !self.isBlur) {
        self.underlyingImage = image;
        [self imageLoadingComplete];
    } else {
        [self processSourceImage:image generation:generation];
    }
}

- (void)processGridThumbnailFromImage:(UIImage *)image generation:(NSUInteger)generation completion:(void (^)(void))completion {
    NSString *cachePath = MWPhotoZoomCachePath(self.photoURL);
    dispatch_async(MWPhotoBlurQueue(), ^{
        @autoreleasepool {
            UIImage *thumbnail = cachePath ? MWPhotoDecodeZoomData([NSData dataWithContentsOfFile:cachePath]) : nil;
            if (!thumbnail) {
                NSData *data = [UIImage mwCompressImageForThumbnail:image];
                if (data) {
                    thumbnail = MWPhotoDecodeZoomData(data);
                    if (cachePath && thumbnail) {
                        NSString *directory = [cachePath stringByDeletingLastPathComponent];
                        [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
                        [data writeToFile:cachePath options:NSDataWritingAtomic error:nil];
                        // 写入后检查总容量，超限时淘汰最旧的文件
                        MWPhotoEnforceImageCacheLimitIfNeeded();
                    }
                }
            }
            dispatch_async(dispatch_get_main_queue(), ^{
                if (generation != self->_loadGeneration || !self.isZoom) return;
                self.gridThumbnailImage = thumbnail;
                if (completion) completion();
            });
        }
    });
}

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

// Release if we can get it again from path or url
- (void)unloadUnderlyingImage {
	[self cancelAnyLoading];
	self.sourceImage = nil;
	self.gridThumbnailImage = nil;
	self.underlyingImage = nil;
}

- (void)imageLoadingComplete {
    NSAssert([[NSThread currentThread] isMainThread], @"This method must be called on the main thread.");
    // Complete so notify
    _loadingInProgress = NO;
    // Notify on next run loop
    // dispatch_after 延迟 0 等价于 performSelector:afterDelay:0，均在下一次 runloop 执行
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0), dispatch_get_main_queue(), ^{
        [self postCompleteNotification];
    });
}

- (void)postCompleteNotification {
    [[NSNotificationCenter defaultCenter] postNotificationName:MWPHOTO_LOADING_DID_END_NOTIFICATION
                                                        object:self];
}

- (void)cancelAnyLoading {
    _loadGeneration++;
    _loadingInProgress = NO;
    if (_webImageOperation != nil) {
        [_webImageOperation cancel];
        _loadingInProgress = NO;
    }
    [self cancelImageRequest];
    [self cancelVideoRequest];
}

- (void)cancelImageRequest {
    if (_assetRequestID != PHInvalidImageRequestID) {
        [[PHImageManager defaultManager] cancelImageRequest:_assetRequestID];
        _assetRequestID = PHInvalidImageRequestID;
    }
}

- (void)cancelVideoRequest {
    if (_assetVideoRequestID != PHInvalidImageRequestID) {
        [[PHImageManager defaultManager] cancelImageRequest:_assetVideoRequestID];
        _assetVideoRequestID = PHInvalidImageRequestID;
    }
}

@end
