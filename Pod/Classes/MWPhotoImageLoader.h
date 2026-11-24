//
//  MWPhotoImageLoader.h
//  MWPhotoBrowser
//
//  Network image loading abstraction used by MWPhoto.
//
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// Cancellable handle returned by an image loader.
@protocol MWPhotoImageLoadingOperation <NSObject>
- (void)cancel;
@end

/// Progress is a value from 0.0 to 1.0. Completion may arrive on any queue.
typedef void (^MWPhotoImageLoadingProgressBlock)(CGFloat progress);
typedef void (^MWPhotoImageLoadingCompletionBlock)(UIImage * _Nullable image, NSError * _Nullable error);

/// Implement this protocol to use a networking and image caching library of your choice.
/// Each request must call completion once, may call progress any number of times, and return a cancellable handle.
@protocol MWPhotoImageLoader <NSObject>
/// CGSizeZero requests the full image; a nonzero size requests a downsampled thumbnail.
- (nullable id<MWPhotoImageLoadingOperation>)loadImageAtURL:(NSURL *)url
                                          thumbnailPixelSize:(CGSize)pixelSize
                                                    progress:(nullable MWPhotoImageLoadingProgressBlock)progress
                                                  completion:(MWPhotoImageLoadingCompletionBlock)completion;
@optional
/// Called when MWPhoto unloads a URL based image to release the loader's in-memory entries.
- (void)removeMemoryCacheForURL:(NSURL *)url thumbnailPixelSize:(CGSize)pixelSize;
@end

/// Default loader backed by SDWebImage. MWPhoto uses this when imageLoader is not overridden.
@interface MWPhotoSDWebImageLoader : NSObject <MWPhotoImageLoader>
@end

NS_ASSUME_NONNULL_END
