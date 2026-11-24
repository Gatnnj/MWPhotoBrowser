//
//  MWPhotoImageLoader.m
//  MWPhotoBrowser
//
#if __has_include(<SDWebImage/SDWebImage.h>)
#import <SDWebImage/SDWebImage.h>
#else
#import "SDWebImage.h"
#endif
#import "MWPhotoImageLoader.h"

@interface MWPhotoSDWebImageOperation : NSObject <MWPhotoImageLoadingOperation>
@property (nonatomic, strong) id<SDWebImageOperation> operation;
@end

@implementation MWPhotoSDWebImageOperation
- (void)cancel {
    [self.operation cancel];
}
@end

@implementation MWPhotoSDWebImageLoader

- (id<MWPhotoImageLoadingOperation>)loadImageAtURL:(NSURL *)url
                                  thumbnailPixelSize:(CGSize)pixelSize
                                            progress:(MWPhotoImageLoadingProgressBlock)progress
                                          completion:(MWPhotoImageLoadingCompletionBlock)completion {
    SDWebImageContext *context = nil;
    if (!CGSizeEqualToSize(pixelSize, CGSizeZero)) {
        context = @{
            SDWebImageContextImageThumbnailPixelSize: [NSValue valueWithCGSize:pixelSize],
            // Keep decoded thumbnail variants out of memory while preserving disk reuse.
            SDWebImageContextStoreCacheType: @(SDImageCacheTypeDisk)
        };
    }

    MWPhotoSDWebImageOperation *token = [MWPhotoSDWebImageOperation new];
    token.operation = [[SDWebImageManager sharedManager] loadImageWithURL:url
                                                                    options:0
                                                                    context:context
                                                                   progress:^(NSInteger receivedSize, NSInteger expectedSize, NSURL * _Nullable targetURL) {
        if (progress && expectedSize > 0) progress(receivedSize / (CGFloat)expectedSize);
    } completed:^(UIImage * _Nullable image, NSData * _Nullable data, NSError * _Nullable error, SDImageCacheType cacheType, BOOL finished, NSURL * _Nullable imageURL) {
        if (finished) completion(image, error);
    }];
    return token;
}

- (void)removeMemoryCacheForURL:(NSURL *)url thumbnailPixelSize:(CGSize)pixelSize {
    SDWebImageManager *manager = [SDWebImageManager sharedManager];
    id<SDImageCache> imageCache = manager.imageCache;
    NSString *originalKey = [manager cacheKeyForURL:url context:nil];
    if (originalKey.length) {
        [imageCache removeImageForKey:originalKey cacheType:SDImageCacheTypeMemory completion:nil];
    }
    if (!CGSizeEqualToSize(pixelSize, CGSizeZero)) {
        SDWebImageContext *context = @{SDWebImageContextImageThumbnailPixelSize: [NSValue valueWithCGSize:pixelSize]};
        NSString *thumbnailKey = [manager cacheKeyForURL:url context:context];
        if (thumbnailKey.length) {
            [imageCache removeImageForKey:thumbnailKey cacheType:SDImageCacheTypeMemory completion:nil];
        }
    }
}

@end
