//
//  MWPhotoBrowser.h
//  MWPhotoBrowser
//
//  Created by Michael Waterfall on 14/10/2010.
//  Copyright 2010 d3i. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "MWPhoto.h"
#import "MWPhotoProtocol.h"
#import "MWToolBar.h"

// Debug Logging
#if 0 // Set to 1 to enable debug logging
#define MWLog(x, ...) NSLog(x, ## __VA_ARGS__);
#else
#define MWLog(x, ...)
#endif

NS_ASSUME_NONNULL_BEGIN

@class MWPhotoBrowser;

/// Optional progress hook for custom loading views. Views without this method can show an indeterminate animation.
@protocol MWPhotoBrowserLoadingView <NSObject>
@optional
- (void)setProgress:(CGFloat)progress;
@end

@protocol MWPhotoBrowserDelegate <NSObject>

- (NSUInteger)numberOfPhotosInPhotoBrowser:(MWPhotoBrowser *)photoBrowser;
- (nullable id <MWPhoto>)photoBrowser:(MWPhotoBrowser *)photoBrowser photoAtIndex:(NSUInteger)index;

@optional

- (nullable id <MWPhoto>)photoBrowser:(MWPhotoBrowser *)photoBrowser thumbPhotoAtIndex:(NSUInteger)index;

// 丝滑转场（可选）：返回该图片在列表中的缩略图视图，浏览器会从该视图位置
// 连贯放大进入、关闭时飞回该位置；不实现则自动降级为渐隐，老调用方完全兼容
- (nullable UIView *)photoBrowser:(MWPhotoBrowser *)photoBrowser startingViewForPhotoAtIndex:(NSUInteger)index;
- (nullable NSString *)photoBrowser:(MWPhotoBrowser *)photoBrowser titleForPhotoAtIndex:(NSUInteger)index;
- (void)photoBrowser:(MWPhotoBrowser *)photoBrowser didDisplayPhotoAtIndex:(NSUInteger)index;
- (void)photoBrowserDidFinishModalPresentation:(MWPhotoBrowser *)photoBrowser;

@end

// UIActionSheetDelegate 已移除：该协议自 iOS 8 废弃，且本类没有实现任何 UIActionSheet 相关方法，属于历史残留
@interface MWPhotoBrowser : UIViewController <UIScrollViewDelegate, UIViewControllerTransitioningDelegate>

@property (nonatomic, weak, nullable) id<MWPhotoBrowserDelegate> delegate;
@property (nonatomic) BOOL zoomPhotosToFill;
@property (nonatomic) BOOL alwaysShowControls;
@property (nonatomic) BOOL enableGrid;
@property (nonatomic) BOOL enableSwipeToDismiss;
@property (nonatomic) BOOL isHiddenToolBar;
@property (nonatomic) BOOL isShowGriding;

// 是否启用自定义丝滑转场（连贯放大 + 拖拽关闭），默认 NO 保持原有行为；
// 启用后需以 UIModalPresentationOverFullScreen 呈现（保留底层视图以支持拖拽透底），
// 并把包装用导航控制器的 transitioningDelegate 指向本浏览器
@property (nonatomic) BOOL enableCustomTransition;
@property (nonatomic) BOOL startOnGrid;
@property (nonatomic) NSUInteger delayToHideElements;
@property (nonatomic, readonly) NSUInteger currentIndex;

/// Optional factory for loading indicators used by zoom pages and grid cells.
/// Return a new configured view, or nil to use the built-in progress indicator.
/// The returned view is centered in the supplied container and hidden when loading finishes.
/// Custom views may implement -setProgress: to receive download progress from 0 to 1.
@property (nonatomic, copy, nullable) UIView * _Nullable (^loadingViewProvider)(UIView *container);

/// Optional source-thumbnail provider, queried for the current page during transitions.
/// This can be set before presentation without requiring an initialized delegate.
@property (nonatomic, copy, nullable) UIView * _Nullable (^startingViewProvider)(NSUInteger index);

// Init
- (instancetype)initWithPhotos:(NSArray<id<MWPhoto>> *)photosArray;
- (instancetype)initWithDelegate:(id <MWPhotoBrowserDelegate>)delegate;

// Reloads the photo browser and refetches data
- (void)reloadData;

// Set page that photo browser starts on
- (void)setCurrentPhotoIndex:(NSUInteger)index;

// Navigation
- (void)showNextPhotoAnimated:(BOOL)animated;
- (void)showPreviousPhotoAnimated:(BOOL)animated;

// ToolBar
- (void)customToolBarItems:(NSArray<UIButton *> *)array;
/// Sets the toolbar to the left, bottom, or right edge. Clears any custom frame.
- (void)customToolBarPosition:(MWToolBarPosition)position;
/// Uses the supplied frame in the photo browser's view coordinate system.
- (void)customToolBarFrame:(CGRect)frame;
@end

NS_ASSUME_NONNULL_END
