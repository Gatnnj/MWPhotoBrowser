//
//  MWPhotoBrowserPrivate.h
//  MWPhotoBrowser
//
//  库内部共享声明，仅供主实现与各 Category 使用。
//  Internal shared declarations, used only by the main implementation and the categories.
//
//  不属于公开契约，子类请改用 MWPhotoBrowserSubclassing.h。
//  Not part of the public contract; subclasses should use MWPhotoBrowserSubclassing.h instead.
//
//  Created by Michael Waterfall on 08/10/2013.
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

NS_ASSUME_NONNULL_BEGIN

/// 主实现私有的实例变量与状态。
/// Instance variables and state private to the main implementation.
@interface MWPhotoBrowser () <UIViewControllerTransitioningDelegate, UIGestureRecognizerDelegate> {

    // 数据 / Data
    NSUInteger _photoCount;
    NSMutableArray *_photos;
    NSMutableArray *_thumbPhotos;
    NSArray<id<MWPhoto>> *_fixedPhotosArray;

    // 视图 / Views
    UIScrollView *_pagingScrollView;

    // 分页与布局 / Paging and layout
    NSMutableSet *_visiblePages, *_recycledPages;
    NSUInteger _currentPageIndex;
    NSUInteger _previousPageIndex;
    CGRect _previousLayoutBounds;
    NSUInteger _pageIndexBeforeRotation;

    // 导航与控件 / Navigation and controls
    MWToolBar *_toolbar;
    NSTimer *_controlVisibilityTimer;
    dispatch_block_t _pendingTapToggleBlock;

    // 网格 / Grid
    MWGridViewController *_gridController;
    UIBarButtonItem *_gridPreviousLeftNavItem;
    UIPanGestureRecognizer *_gridDismissPanGesture;
    BOOL _gridTransitioning;
    BOOL _pendingReloadData;

    // 外观 / Appearance
    BOOL _previousNavBarHidden;
    BOOL _previousNavBarTranslucent;
    UIBarStyle _previousNavBarStyle;
    UIColor *_previousNavBarTintColor;
    UIColor *_previousNavBarBarTintColor;
    UIImage *_previousNavigationBarBackgroundImageDefault;
    UINavigationBarAppearance *_previousNavBarStandardAppearance;
    UINavigationBarAppearance *_previousNavBarScrollEdgeAppearance;
    UINavigationBarAppearance *_previousNavBarCompactAppearance;
    UINavigationBarAppearance *_previousNavBarCompactScrollEdgeAppearance;

    // 其他状态 / Miscellaneous state
    BOOL _hasBelongedToViewController;
    BOOL _statusBarShouldBeHidden;
    BOOL _leaveStatusBarAlone;
    BOOL _performingLayout;
    BOOL _rotating;
    BOOL _viewIsActive;
    BOOL _didSavePreviousStateOfNavBar;
    BOOL _skipNextPagingScrollViewPositioning;
    BOOL _viewHasAppearedInitially;
    CGPoint _currentGridContentOffset;
}

/// 拖拽关闭交互控制器，仅在启用自定义转场时创建。
/// Drag-to-dismiss interaction controller, created only when the custom transition is enabled.
@property (nonatomic, strong, nullable) MWPhotoInteractiveTransition *interactiveTransition;

// 由主实现提供 / Provided by the main implementation
- (void)performLayout;
- (void)doneButtonPressed:(nullable id)sender;
- (void)customToolBarItems:(NSArray<UIButton *> *)array;

@end

/// 由各 Category 提供的内部方法。
/// Internal methods provided by the categories.
///
/// 声明在分类而非类扩展中，避免每个 .m 都触发 -Wincomplete-implementation。
/// Declared in a category rather than the class extension so that no .m triggers
/// -Wincomplete-implementation for methods implemented elsewhere.
@interface MWPhotoBrowser (MWInternal)

// 布局 / Layout  —— MWPhotoBrowser+Layout
- (void)layoutVisiblePages;
- (CGRect)frameForPagingScrollView;
- (CGRect)frameForPageAtIndex:(NSUInteger)index;
- (CGSize)contentSizeForPagingScrollView;
- (CGPoint)contentOffsetForPageAtIndex:(NSUInteger)index;
- (UIInterfaceOrientation)mw_currentInterfaceOrientation;
- (CGRect)frameForToolbarAtOrientation:(UIInterfaceOrientation)orientation;

// 分页 / Paging  —— MWPhotoBrowser+Paging
- (void)tilePages;
- (BOOL)isDisplayingPageForIndex:(NSUInteger)index;
- (nullable MWZoomingScrollView *)pageDisplayedAtIndex:(NSUInteger)index;
- (nullable MWZoomingScrollView *)pageDisplayingPhoto:(id<MWPhoto>)photo;
- (nullable MWZoomingScrollView *)dequeueRecycledPage;
- (void)configurePage:(MWZoomingScrollView *)page forIndex:(NSUInteger)index;
- (void)didStartViewingPageAtIndex:(NSUInteger)index;

// 数据 / Data  —— MWPhotoBrowser+Data
- (NSUInteger)numberOfPhotos;
- (nullable id<MWPhoto>)photoAtIndex:(NSUInteger)index;
- (nullable id<MWPhoto>)thumbPhotoAtIndex:(NSUInteger)index;
- (nullable UIImage *)imageForPhoto:(id<MWPhoto>)photo;
- (void)loadAdjacentPhotosIfNecessary:(id<MWPhoto>)photo;
- (void)releaseAllUnderlyingPhotos:(BOOL)preserveCurrent;
- (void)handleMWPhotoLoadingDidEndNotification:(NSNotification *)notification;

// 导航 / Navigation  —— MWPhotoBrowser+Navigation
- (void)updateNavigation;
- (void)jumpToPageAtIndex:(NSUInteger)index animated:(BOOL)animated;
- (void)gotoPreviousPage;
- (void)gotoNextPage;

// 网格 / Grid  —— MWPhotoBrowser+Grid
// showGrid: 与 showGridAnimated 已在公开头声明，供外部调用
- (void)hideGrid;
- (void)handleGridDismissPan:(UIPanGestureRecognizer *)pan;

// 控件显隐 / Control visibility  —— MWPhotoBrowser+Controls
- (void)cancelControlHiding;
- (void)hideControlsAfterDelay;
- (void)setControlsHidden:(BOOL)hidden animated:(BOOL)animated permanent:(BOOL)permanent;
- (void)toggleControls;
- (BOOL)areControlsHidden;
- (void)scheduleToggleControlsFromTap;
- (void)cancelPendingTapToggle;

// 导航栏外观 / Navigation bar appearance  —— MWPhotoBrowser+NavBar
- (void)setNavBarAppearance:(BOOL)animated;
- (void)storePreviousNavBarAppearance;
- (void)restorePreviousNavBarAppearance:(BOOL)animated;
- (BOOL)presentingViewControllerPrefersStatusBarHidden;

// 转场 / Transition  —— MWPhotoBrowser+Transition
- (nullable UIView *)mw_startingView;

@end

NS_ASSUME_NONNULL_END
