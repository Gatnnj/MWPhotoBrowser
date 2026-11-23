//
//  MWPhotoBrowser_Private.h
//  MWPhotoBrowser
//
//  Created by Michael Waterfall on 08/10/2013.
//
//

#import <UIKit/UIKit.h>
#import "MWGridViewController.h"
#import "MWZoomingScrollView.h"
#import "MWToolBar.h"

@class MWPhotoInteractiveTransition;
@class MWPhotoTransitionAnimator;

#ifndef PADDING
#define PADDING 10
#endif

// Declare private methods of browser
// 遵循 UIViewControllerTransitioningDelegate 以提供自定义丝滑转场
@interface MWPhotoBrowser () <UIViewControllerTransitioningDelegate, UIGestureRecognizerDelegate> {
    
	// Data
    NSUInteger _photoCount;
    NSMutableArray *_photos;
    NSMutableArray *_thumbPhotos;
	NSArray<id<MWPhoto>> *_fixedPhotosArray; // Provided via init
	
	// Views
	UIScrollView *_pagingScrollView;
	
	// Paging & layout
	NSMutableSet *_visiblePages, *_recycledPages;
	NSUInteger _currentPageIndex;
    NSUInteger _previousPageIndex;
    CGRect _previousLayoutBounds;
	NSUInteger _pageIndexBeforeRotation;
	
	// Navigation & controls
    MWToolBar *_toolbar;
	NSTimer *_controlVisibilityTimer;
    dispatch_block_t _pendingTapToggleBlock; // 排队中的单击切换显隐，可被双击或退出取消
    
    // Grid
    MWGridViewController *_gridController;
    UIBarButtonItem *_gridPreviousLeftNavItem;
    UIPanGestureRecognizer *_gridDismissPanGesture;
    BOOL _gridTransitioning;
    BOOL _pendingReloadData;
    
    // Appearance
    BOOL _previousNavBarHidden;
    BOOL _previousNavBarTranslucent;
    UIBarStyle _previousNavBarStyle;
    // _previousStatusBarStyle 已移除：现代状态栏机制下无需手动保存/恢复样式
    UIColor *_previousNavBarTintColor;
    UIColor *_previousNavBarBarTintColor;
    UIImage *_previousNavigationBarBackgroundImageDefault;
    UINavigationBarAppearance *_previousNavBarStandardAppearance;
    UINavigationBarAppearance *_previousNavBarScrollEdgeAppearance;
    UINavigationBarAppearance *_previousNavBarCompactAppearance;
    UINavigationBarAppearance *_previousNavBarCompactScrollEdgeAppearance;
    // _previousNavigationBarBackgroundImageLandscapePhone 已移除：iOS 8 后横屏使用统一 metrics

    
    // Misc
    BOOL _hasBelongedToViewController;
    // _isVCBasedStatusBarAppearance 已移除：iOS 13 起状态栏外观统一由 VC 管理
    BOOL _statusBarShouldBeHidden;
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
// 自定义转场的交互控制器（拖拽关闭），启用丝滑转场时创建
@property (nonatomic, strong) MWPhotoInteractiveTransition *interactiveTransition;

// Layout
- (void)layoutVisiblePages;
- (void)performLayout;
- (BOOL)presentingViewControllerPrefersStatusBarHidden;
- (UIView *)mw_startingView;
- (void)handleGridDismissPan:(UIPanGestureRecognizer *)pan;

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
- (UIInterfaceOrientation)mw_currentInterfaceOrientation;
- (CGRect)frameForToolbarAtOrientation:(UIInterfaceOrientation)orientation;

// Navigation
- (void)updateNavigation;
- (void)jumpToPageAtIndex:(NSUInteger)index animated:(BOOL)animated;
- (void)gotoPreviousPage;
- (void)gotoNextPage;

// Grid
- (void)showGridAnimated;
- (void)showGrid:(BOOL)animated;
- (void)hideGrid;

// Misc
- (void)doneButtonPressed:(id)sender;
- (void)customToolBarItems:(NSArray<UIButton *> *)array;
- (void)handleMWPhotoLoadingDidEndNotification:(NSNotification *)notification;
- (void)showPreviousPhotoAnimated:(BOOL)animated;
- (void)showNextPhotoAnimated:(BOOL)animated;

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
- (nullable id<MWPhoto>)photoAtIndex:(NSUInteger)index;
- (nullable id<MWPhoto>)thumbPhotoAtIndex:(NSUInteger)index;
- (UIImage *)imageForPhoto:(id<MWPhoto>)photo;
- (void)loadAdjacentPhotosIfNecessary:(id<MWPhoto>)photo;
- (void)releaseAllUnderlyingPhotos:(BOOL)preserveCurrent;

@end

