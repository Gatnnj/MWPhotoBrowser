//
//  MWPhotoBrowser_Private.h
//  MWPhotoBrowser
//
//  Created by Michael Waterfall on 08/10/2013.
//
//

#import <UIKit/UIKit.h>
#import <MBProgressHUD/MBProgressHUD.h>
// MediaPlayer 框架（MPMoviePlayerViewController，iOS 9 废弃）已移除，
// 现代播放器 AVPlayerViewController 位于 AVKit，在 .m 中导入
#import "MWGridViewController.h"
#import "MWZoomingScrollView.h"

@class AVPlayerViewController;
@class MWPhotoInteractiveTransition;
@class MWPhotoTransitionAnimator;

// Declare private methods of browser
// 遵循 UIAdaptivePresentationControllerDelegate 以监听用户手动关闭播放器；
// 遵循 UIViewControllerTransitioningDelegate 以提供自定义丝滑转场
@interface MWPhotoBrowser () <UIAdaptivePresentationControllerDelegate, UIViewControllerTransitioningDelegate> {
    
	// Data
    NSUInteger _photoCount;
    NSMutableArray *_photos;
    NSMutableArray *_thumbPhotos;
	NSArray *_fixedPhotosArray; // Provided via init
	
	// Views
	UIScrollView *_pagingScrollView;
	
	// Paging & layout
	NSMutableSet *_visiblePages, *_recycledPages;
	NSUInteger _currentPageIndex;
    NSUInteger _previousPageIndex;
    CGRect _previousLayoutBounds;
	NSUInteger _pageIndexBeforeRotation;
	
	// Navigation & controls
	UIToolbar *_toolbar;
	NSTimer *_controlVisibilityTimer;
    dispatch_block_t _pendingTapToggleBlock; // 排队中的单击切换显隐，可被双击或退出取消
	UIBarButtonItem *_previousButton, *_nextButton, *_actionButton, *_doneButton;
    MBProgressHUD *_progressHUD;
    
    // Grid
    MWGridViewController *_gridController;
    UIBarButtonItem *_gridPreviousLeftNavItem;
    UIBarButtonItem *_gridPreviousRightNavItem;
    
    // Appearance
    BOOL _previousNavBarHidden;
    BOOL _previousNavBarTranslucent;
    UIBarStyle _previousNavBarStyle;
    // _previousStatusBarStyle 已移除：现代状态栏机制下无需手动保存/恢复样式
    UIColor *_previousNavBarTintColor;
    UIColor *_previousNavBarBarTintColor;
    UIBarButtonItem *_previousViewControllerBackButton;
    UIImage *_previousNavigationBarBackgroundImageDefault;
    // _previousNavigationBarBackgroundImageLandscapePhone 已移除：iOS 8 后横屏使用统一 metrics

    // Video
    // 类型由 MPMoviePlayerViewController 替换为 AVPlayerViewController（AVKit）
    AVPlayerViewController *_currentVideoPlayerViewController;
    NSUInteger _currentVideoIndex;
    UIActivityIndicatorView *_currentVideoLoadingIndicator;
    
    // Misc
    BOOL _hasBelongedToViewController;
    // _isVCBasedStatusBarAppearance 已移除：iOS 13 起状态栏外观统一由 VC 管理
    BOOL _statusBarShouldBeHidden;
    BOOL _displayActionButton;
    BOOL _leaveStatusBarAlone;
	BOOL _performingLayout;
	BOOL _rotating;
    BOOL _viewIsActive; // active as in it's in the view heirarchy
    BOOL _didSavePreviousStateOfNavBar;
    BOOL _skipNextPagingScrollViewPositioning;
    BOOL _viewHasAppearedInitially;
    CGPoint _currentGridContentOffset;
    
}

// Properties
@property (nonatomic) UIActivityViewController *activityViewController;
// 自定义转场的交互控制器（拖拽关闭），启用丝滑转场时创建
@property (nonatomic, strong) MWPhotoInteractiveTransition *interactiveTransition;

// Layout
- (void)layoutVisiblePages;
- (void)performLayout;
- (BOOL)presentingViewControllerPrefersStatusBarHidden;
- (UIView *)mw_startingView;

// Nav Bar Appearance
- (void)setNavBarAppearance:(BOOL)animated;
- (void)storePreviousNavBarAppearance;
- (void)restorePreviousNavBarAppearance:(BOOL)animated;

// Paging
- (void)tilePages;
- (BOOL)isDisplayingPageForIndex:(NSUInteger)index;
- (MWZoomingScrollView *)pageDisplayedAtIndex:(NSUInteger)index;
- (MWZoomingScrollView *)pageDisplayingPhoto:(id<MWPhoto>)photo;
- (MWZoomingScrollView *)dequeueRecycledPage;
- (void)configurePage:(MWZoomingScrollView *)page forIndex:(NSUInteger)index;
- (void)didStartViewingPageAtIndex:(NSUInteger)index;

// Frames
- (CGRect)frameForPagingScrollView;
- (CGRect)frameForPageAtIndex:(NSUInteger)index;
- (CGSize)contentSizeForPagingScrollView;
- (CGPoint)contentOffsetForPageAtIndex:(NSUInteger)index;
- (CGRect)frameForToolbarAtOrientation:(UIInterfaceOrientation)orientation;
- (CGRect)frameForCaptionView:(MWCaptionView *)captionView atIndex:(NSUInteger)index;
- (CGRect)frameForSelectedButton:(UIButton *)selectedButton atIndex:(NSUInteger)index;

// Navigation
- (void)updateNavigation;
- (void)jumpToPageAtIndex:(NSUInteger)index animated:(BOOL)animated;
- (void)gotoPreviousPage;
- (void)gotoNextPage;

// Grid
- (void)showGrid:(BOOL)animated;
- (void)hideGrid;

// Controls
- (void)cancelControlHiding;
- (void)hideControlsAfterDelay;
- (void)setControlsHidden:(BOOL)hidden animated:(BOOL)animated permanent:(BOOL)permanent;
- (void)toggleControls;
- (BOOL)areControlsHidden;
// 单击延迟切换控件显隐（可被双击 / 退出页面取消）
- (void)scheduleToggleControlsFromTap;
- (void)cancelPendingTapToggle;

// Data
- (NSUInteger)numberOfPhotos;
- (id<MWPhoto>)photoAtIndex:(NSUInteger)index;
- (id<MWPhoto>)thumbPhotoAtIndex:(NSUInteger)index;
- (UIImage *)imageForPhoto:(id<MWPhoto>)photo;
- (BOOL)photoIsSelectedAtIndex:(NSUInteger)index;
- (void)setPhotoSelected:(BOOL)selected atIndex:(NSUInteger)index;
- (void)loadAdjacentPhotosIfNecessary:(id<MWPhoto>)photo;
- (void)releaseAllUnderlyingPhotos:(BOOL)preserveCurrent;

@end

