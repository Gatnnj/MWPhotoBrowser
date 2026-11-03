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

static NSString *MWPhotoBlurCacheDirectory(void) {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    return [[paths.firstObject stringByAppendingPathComponent:@"MWPhotoBrowserBlurCache"] copy];
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
    return [[MWPhotoBlurCacheDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"%@_%@.jpg", prefix, radiusKey]] copy];
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

static void MWPhotoWriteBlurCache(UIImage *image, NSString *path) {
    if (!image || !path) return;
    NSString *directory = [path stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    NSData *data = UIImageJPEGRepresentation(image, 0.94);
    if (!data || ![data writeToFile:path options:NSDataWritingAtomic error:nil]) return;
    NSDictionary *metadata = @{@"scale": @(image.scale), @"orientation": @(image.imageOrientation)};
    [metadata writeToFile:[path stringByAppendingPathExtension:@"plist"] atomically:YES];
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
- (void)imageLoadingComplete;
- (void)completeLoadingWithImage:(UIImage *)image generation:(NSUInteger)generation;
- (void)processSourceImage:(UIImage *)image generation:(NSUInteger)generation;

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
        [[NSFileManager defaultManager] removeItemAtPath:MWPhotoBlurCacheDirectory() error:nil];
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
        NSString *filePrefix = [prefix stringByAppendingString:@"_"];
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
        if (!image || !self.isBlur) {
            self.underlyingImage = image;
            [self imageLoadingComplete];
        } else {
            [self processSourceImage:image generation:generation];
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
