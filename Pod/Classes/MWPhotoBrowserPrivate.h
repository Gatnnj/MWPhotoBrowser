//
//  MWPhotoBrowserPrivate.h
//  MWPhotoBrowser
//
//  库内部共享声明，仅供主实现与各 Category 使用。
//  不属于公开契约，子类请改用 MWPhotoBrowserSubclassing.h。
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
@interface MWPhotoBrowser () <UIViewControllerTransitioningDelegate, UIGestureRecognizerDelegate> {

    // 数据
    NSUInteger _photoCount;
    NSMutableArray *_photos;
    NSMutableArray *_thumbPhotos;
    NSArray<id<MWPhoto>> *_fixedPhotosArray;

    // 视图
    UIScrollView *_pagingScrollView;

    // 分页与布局
    NSMutableSet *_visiblePages, *_recycledPages;
    NSUInteger _currentPageIndex;
    NSUInteger _previousPageIndex;
    CGRect _previousLayoutBounds;
    NSUInteger _pageIndexBeforeRotation;

    // 导航与控件
    MWToolBar *_toolbar;
    NSTimer *_controlVisibilityTimer;
    dispatch_block_t _pendingTapToggleBlock;

    // 网格
    MWGridViewController *_gridController;
    UIBarButtonItem *_gridPreviousLeftNavItem;
    UIPanGestureRecognizer *_gridDismissPanGesture;
    BOOL _gridTransitioning;
    BOOL _isShowingGrid;
    BOOL _hasPickedFromGrid;
    BOOL _pendingReloadData;

    // 外观
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

    // 其他状态
    BOOL _hasBelongedToViewController;
    BOOL _statusBarShouldBeHidden;
    BOOL _leaveStatusBarAlone;
    BOOL _performingLayout;
    BOOL _rotating;
    BOOL _viewIsActive;
    BOOL _didSavePreviousStateOfNavBar;
    BOOL _skipNextPagingScrollViewPositioning;
    BOOL _viewHasAppearedInitially;
}

/// 拖拽关闭交互控制器，仅在启用自定义转场时创建。
@property (nonatomic, strong, nullable) MWPhotoInteractiveTransition *interactiveTransition;

/// 网格状态的内部可写版本：公开头对外只读，由网格流程与选中回调写入。
@property (nonatomic, readwrite) BOOL hasPickedFromGrid;
@property (nonatomic, readwrite) BOOL isShowingGrid;

// 由主实现提供
/// 重新计算并摆放所有可见页
- (void)performLayout;
/// 完成按钮响应：关闭浏览器或在网格/单图间切换
- (void)doneButtonPressed:(nullable id)sender;
/// 配置自定义工具栏按钮
- (void)customToolBarItems:(NSArray<UIButton *> *)array;

@end

/// 由各 Category 提供的内部方法。
///
/// 声明在分类而非类扩展中，避免每个 .m 都触发 -Wincomplete-implementation。
@interface MWPhotoBrowser (MWInternal)

// 布局 —— MWPhotoBrowser+Layout
/// 重新摆放当前可见页
- (void)layoutVisiblePages;
/// 分页滚动视图的 frame
- (CGRect)frameForPagingScrollView;
/// 指定索引图片页的 frame
- (CGRect)frameForPageAtIndex:(NSUInteger)index;
/// 分页滚动视图的内容尺寸
- (CGSize)contentSizeForPagingScrollView;
/// 指定索引页对应的内容偏移
- (CGPoint)contentOffsetForPageAtIndex:(NSUInteger)index;
/// 当前界面方向
- (UIInterfaceOrientation)mw_currentInterfaceOrientation;
/// 指定方向下工具栏的 frame
- (CGRect)frameForToolbarAtOrientation:(UIInterfaceOrientation)orientation;

// 分页 —— MWPhotoBrowser+Paging
/// 按可见范围创建、复用并摆放图片页
- (void)tilePages;
/// 指定索引是否已有可见页
- (BOOL)isDisplayingPageForIndex:(NSUInteger)index;
/// 取指定索引正在显示的页
- (nullable MWZoomingScrollView *)pageDisplayedAtIndex:(NSUInteger)index;
/// 取展示指定图片对象的页
- (nullable MWZoomingScrollView *)pageDisplayingPhoto:(id<MWPhoto>)photo;
/// 从复用池取一个可复用页
- (nullable MWZoomingScrollView *)dequeueRecycledPage;
/// 绑定页的 frame、索引与图片
- (void)configurePage:(MWZoomingScrollView *)page forIndex:(NSUInteger)index;
/// 某页开始显示时回调
- (void)didStartViewingPageAtIndex:(NSUInteger)index;

// 数据 —— MWPhotoBrowser+Data
/// 图片总数（优先代理，其次固定数组）
- (NSUInteger)numberOfPhotos;
/// 取指定索引的图片对象，必要时懒加载
- (nullable id<MWPhoto>)photoAtIndex:(NSUInteger)index;
/// 取指定索引的缩略图对象
- (nullable id<MWPhoto>)thumbPhotoAtIndex:(NSUInteger)index;
/// 取图片对象当前已就绪的 UIImage
- (nullable UIImage *)imageForPhoto:(id<MWPhoto>)photo;
/// 预加载当前页相邻的图片
- (void)loadAdjacentPhotosIfNecessary:(id<MWPhoto>)photo;
/// 释放所有图片底层数据，可保留当前页
- (void)releaseAllUnderlyingPhotos:(BOOL)preserveCurrent;
/// 处理图片加载完成通知，刷新对应页
- (void)handleMWPhotoLoadingDidEndNotification:(NSNotification *)notification;

// 导航 —— MWPhotoBrowser+Navigation
/// 更新导航栏按钮与标题状态
- (void)updateNavigation;
/// 跳转到指定索引页
- (void)jumpToPageAtIndex:(NSUInteger)index animated:(BOOL)animated;
/// 上一页
- (void)gotoPreviousPage;
/// 下一页
- (void)gotoNextPage;

// 网格 —— MWPhotoBrowser+Grid
// showGrid: 与 showGridAnimated 已在公开头声明，供外部调用
/// 关闭网格并回到单图浏览
- (void)hideGrid;
/// 网格拖拽关闭手势处理
- (void)handleGridDismissPan:(UIPanGestureRecognizer *)pan;

// 控件显隐 —— MWPhotoBrowser+Controls
/// 取消待执行的自动隐藏
- (void)cancelControlHiding;
/// 延迟后自动隐藏控件
- (void)hideControlsAfterDelay;
/// 设置导航栏与工具栏显隐
- (void)setControlsHidden:(BOOL)hidden animated:(BOOL)animated permanent:(BOOL)permanent;
/// 切换控件显隐
- (void)toggleControls;
/// 控件当前是否隐藏
- (BOOL)areControlsHidden;
/// 点击后延迟触发控件切换（合并单击双击时序）
- (void)scheduleToggleControlsFromTap;
/// 取消待执行的点击切换
- (void)cancelPendingTapToggle;

// 导航栏外观 —— MWPhotoBrowser+NavBar
/// 应用导航栏外观
- (void)setNavBarAppearance:(BOOL)animated;
/// 记录进入前的导航栏外观
- (void)storePreviousNavBarAppearance;
/// 恢复进入前的导航栏外观
- (void)restorePreviousNavBarAppearance:(BOOL)animated;
/// 状态栏是否应由呈现方隐藏
- (BOOL)presentingViewControllerPrefersStatusBarHidden;

// 转场 —— MWPhotoBrowser+Transition
/// 解析当前页转场起始缩略图
- (nullable UIView *)mw_startingView;

@end

NS_ASSUME_NONNULL_END
