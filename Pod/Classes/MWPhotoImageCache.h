//
//  MWPhotoImageCache.h
//  MWPhotoBrowser
//
//  Private image-cache support shared by MWPhoto loading paths.
//
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

dispatch_queue_t MWPhotoBlurQueue(void);
NSString * _Nullable MWPhotoBlurCachePath(NSURL * _Nullable url, CGFloat radius);
UIImage * _Nullable MWPhotoReadBlurCache(NSString *path);
void MWPhotoWriteBlurCache(UIImage *image, NSString *path);
void MWPhotoClearBlurCache(void (^ _Nullable completion)(void));
void MWPhotoClearBlurCacheForURL(NSURL *url, void (^ _Nullable completion)(void));

NS_ASSUME_NONNULL_END
