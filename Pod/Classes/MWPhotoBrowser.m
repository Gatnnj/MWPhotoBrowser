//
//  MWPhotoBrowser.m
//  MWPhotoBrowser
//
//  主实现：初始化、生命周期、视图装配与布局入口。
//  Main implementation: initialization, lifecycle, view assembly and layout entry points.
//
//  数据源 / 分页 / 布局 / 导航 / 网格 / 控件 / 导航栏 / 转场逻辑见对应 Category 文件。
//  Data source, paging, layout, navigation, grid, controls, navigation bar and transition
//  logic live in the corresponding category files.
//
//  Created by Michael Waterfall on 14/10/2010.
//  Copyright 2010 d3i. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>
#import "MWPhotoBrowser.h"
#import "MWPhotoBrowserSubclassing.h"
#import "MWPhotoBrowserPrivate.h"
#import "MWPhotoInteractiveTransition.h"

@implementation MWPhotoBrowser

#pragma mark - Initialization

- (instancetype)init {
    if ((self = [super init])) {
        [self commonInit];
    }
    return self;
}

- (instancetype)initWithDelegate:(id <MWPhotoBrowserDelegate>)delegate {
    if ((self = [self init])) {
        _delegate = delegate;
    }
    return self;
}

- (instancetype)initWithPhotos:(NSArray<id<MWPhoto>> *)photosArray {
    if ((self = [self init])) {
        _fixedPhotosArray = photosArray;
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)decoder {
    if ((self = [super initWithCoder:decoder])) {
        [self commonInit];
    }
    return self;
}

/// 各初始化入口共用的默认状态设置。
- (void)commonInit {
    self.hidesBottomBarWhenPushed = YES;
    _hasBelongedToViewController = NO;
    _photoCount = NSNotFound;
    _previousLayoutBounds = CGRectZero;
    _currentPageIndex = 0;
    _previousPageIndex = NSUIntegerMax;
    _zoomPhotosToFill = YES;
    _performingLayout = NO;
    _rotating = NO;
    _viewIsActive = NO;
    _enableGrid = YES;
    _startOnGrid = NO;
    _enableSwipeToDismiss = YES;
    _delayToHideElements = 5;
    _visiblePages = [[NSMutableSet alloc] init];
    _recycledPages = [[NSMutableSet alloc] init];
    _photos = [[NSMutableArray alloc] init];
    _thumbPhotos = [[NSMutableArray alloc] init];
    _didSavePreviousStateOfNavBar = NO;

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleMWPhotoLoadingDidEndNotification:)
                                                 name:MWPHOTO_LOADING_DID_END_NOTIFICATION
                                               object:nil];
}

- (void)dealloc {
    // 取消排队的单击切换，避免回调到已销毁对象。
    [self cancelPendingTapToggle];
    // 控件定时器持有 self，必须断开，否则会拖住整个视图树延迟释放。
    [self cancelControlHiding];
    _pagingScrollView.delegate = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self releaseAllUnderlyingPhotos:NO];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    [self releaseAllUnderlyingPhotos:YES];
    [_recycledPages removeAllObjects];
}

#pragma mark - View Loading

- (void)viewDidLoad {
    [super viewDidLoad];

    [self validateGridSettings];
    [self setUpRootView];

    _pagingScrollView = [self makePagingScrollView];
    [self configurePagingScrollView:_pagingScrollView];
    [self.view addSubview:_pagingScrollView];

    _toolbar = [self makeToolbar];
    [self configureToolbar:_toolbar];
    [self.view addSubview:_toolbar];

    [self setUpDismissInteraction];
    [self reloadData];
    [self setUpLegacyDismissGestureIfNeeded];
}

#pragma mark - Setup Hooks

- (void)validateGridSettings {
    if (_startOnGrid) _enableGrid = YES;
    if (_enableGrid) {
        _enableGrid = [_delegate respondsToSelector:@selector(photoBrowser:thumbPhotoAtIndex:)];
    }
    if (!_enableGrid) _startOnGrid = NO;
}

- (void)setUpRootView {
    self.view.backgroundColor = [UIColor blackColor];
    self.view.opaque = NO;
    self.view.clipsToBounds = YES;
}

#pragma mark - Factory Hooks

- (UIScrollView *)makePagingScrollView {
    return [[UIScrollView alloc] initWithFrame:[self frameForPagingScrollView]];
}

- (void)configurePagingScrollView:(UIScrollView *)pagingScrollView {
    // 禁止系统自动调整安全区 inset，保持手动布局。
    pagingScrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    // iOS 26 在透明导航栏下方新增滚动边缘渐隐，图片需铺满全屏故关闭。
    if (@available(iOS 26.0, *)) {
        pagingScrollView.topEdgeEffect.hidden = YES;
    }
    pagingScrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    pagingScrollView.pagingEnabled = YES;
    pagingScrollView.delegate = self;
    pagingScrollView.showsHorizontalScrollIndicator = NO;
    pagingScrollView.showsVerticalScrollIndicator = NO;
    pagingScrollView.backgroundColor = [UIColor blackColor];
    pagingScrollView.opaque = NO;
    pagingScrollView.contentSize = [self contentSizeForPagingScrollView];
}

- (MWToolBar *)makeToolbar {
    UIInterfaceOrientation orientation = [self mw_currentInterfaceOrientation];
    return [[MWToolBar alloc] initWithFrame:[self frameForToolbarAtOrientation:orientation]];
}

- (void)configureToolbar:(MWToolBar *)toolbar {
    toolbar.clipsToBounds = YES;
    toolbar.hidden = _isHiddenToolBar;
}

- (MWPhotoInteractiveTransition *)makeInteractiveTransition {
    __weak typeof(self) weakSelf = self;
    MWPhotoInteractiveTransition *transition =
    [[MWPhotoInteractiveTransition alloc] initWithCurrentImageViewBlock:^UIView *{
        MWPhotoBrowser *strongSelf = weakSelf;
        if (!strongSelf) return nil;
        // 网格覆盖在图片页之上，其垂直拖动不应触发下拉关闭。
        if (strongSelf->_gridController || strongSelf->_gridTransitioning) return nil;
        MWZoomingScrollView *page = [strongSelf pageDisplayedAtIndex:strongSelf.currentIndex];
        if (!page && strongSelf->_visiblePages.count > 0) {
            page = strongSelf->_visiblePages.allObjects.firstObject;
        }
        // 处于最小缩放才允许拖拽；初始 zoomScale 不一定等于 1。
        if (page.zoomScale > page.minimumZoomScale + 0.01) return nil;
        return [page photoImageViewForTransition];
    } setPagingEnabled:^(BOOL enabled) {
        MWPhotoBrowser *strongSelf = weakSelf;
        // 必须先判空：对 nil 直接解引用 ivar 会崩溃。
        if (!strongSelf) return;
        strongSelf->_pagingScrollView.scrollEnabled = enabled;
    } setBackgroundAlpha:^(CGFloat alpha) {
        MWPhotoBrowser *strongSelf = weakSelf;
        if (!strongSelf) return;
        // 各层背景共用同一 alpha，图片本身保持不透明。
        UIColor *background = [UIColor colorWithWhite:0 alpha:alpha];
        strongSelf.view.backgroundColor = background;
        strongSelf.view.opaque = NO;
        strongSelf.navigationController.view.backgroundColor = [UIColor clearColor];
        strongSelf.navigationController.view.opaque = NO;
        strongSelf->_pagingScrollView.backgroundColor = background;
        strongSelf->_pagingScrollView.opaque = NO;
        for (MWZoomingScrollView *page in strongSelf->_visiblePages) {
            [page setBackgroundAlpha:alpha];
        }
    } dismissTargetBlock:^UIView *{
        return [weakSelf mw_startingView];
    } dismissBlock:^{
        // 拖拽快照已完成飞回动画，故关闭系统 dismiss 动画避免重复播放。
        MWPhotoBrowser *strongSelf = weakSelf;
        [strongSelf dismissViewControllerAnimated:NO completion:nil];
    }];

    transition.interactionDidRestore = ^{
        MWPhotoBrowser *strongSelf = weakSelf;
        if (!strongSelf || !strongSelf->_pendingReloadData) return;
        strongSelf->_pendingReloadData = NO;
        [strongSelf reloadData];
    };
    return transition;
}

- (void)setUpDismissInteraction {
    if (!_enableCustomTransition) return;
    self.interactiveTransition = [self makeInteractiveTransition];
    if (!self.interactiveTransition) return;
    [self.interactiveTransition installGestureOnRootView:self.view];
}

- (void)setUpLegacyDismissGestureIfNeeded {
    // 自定义转场由跟手拖拽负责关闭，旧手势会在松手前提前 dismiss。
    if (!_enableSwipeToDismiss || _enableCustomTransition) return;
    UISwipeGestureRecognizer *swipeGesture =
    [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(doneButtonPressed:)];
    swipeGesture.direction = UISwipeGestureRecognizerDirectionDown | UISwipeGestureRecognizerDirectionUp;
    [self.view addGestureRecognizer:swipeGesture];
}

#pragma mark - Layout

- (void)performLayout {
    _performingLayout = YES;
    [self willPerformLayout];

    [_visiblePages removeAllObjects];
    [_recycledPages removeAllObjects];

    [self updateNavigation];

    _pagingScrollView.contentOffset = [self contentOffsetForPageAtIndex:_currentPageIndex];
    [self tilePages];

    [self didPerformLayout];
    _performingLayout = NO;
}

- (void)willPerformLayout {
    // 默认空实现，供子类扩展。
}

- (void)didPerformLayout {
    // 默认空实现，供子类扩展。
}

#pragma mark - Toolbar

- (void)customToolBarItems:(NSArray<UIButton *> *)array {
    [self loadViewIfNeeded];
    [_toolbar addItems:array];
    [_toolbar setNeedsLayout];
    [self.view setNeedsLayout];
}

- (void)customToolBarPosition:(MWToolBarPosition)position {
    [self loadViewIfNeeded];
    _toolbar.customFrame = nil;
    _toolbar.position = position;
    _toolbar.frame = [self frameForToolbarAtOrientation:[self mw_currentInterfaceOrientation]];
    [_toolbar setNeedsLayout];
    [self.view setNeedsLayout];
}

- (void)customToolBarFrame:(CGRect)frame {
    [self loadViewIfNeeded];
    _toolbar.customFrame = [NSValue valueWithCGRect:frame];
    _toolbar.frame = frame;
    [_toolbar setNeedsLayout];
    [self.view setNeedsLayout];
}

#pragma mark - Appearance

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    if (!_viewHasAppearedInitially) {
        _leaveStatusBarAlone = [self presentingViewControllerPrefersStatusBarHidden];
        UIStatusBarManager *statusBarManager = self.view.window.windowScene.statusBarManager;
        if (statusBarManager && statusBarManager.statusBarHidden) {
            _leaveStatusBarAlone = YES;
        }
    }
    if (!_leaveStatusBarAlone && [[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone) {
        [self setNeedsStatusBarAppearanceUpdate];
    }

    if (!_viewIsActive && [self.navigationController.viewControllers objectAtIndex:0] != self) {
        [self storePreviousNavBarAppearance];
    }
    [self setNavBarAppearance:animated];

    [self hideControlsAfterDelay];

    if (!_viewHasAppearedInitially) {
        if (_startOnGrid) {
            [self showGrid:NO];
        }
    }

    // 模态呈现期间发生旋转且页码变化时，恢复到旋转前的页。
    if (_currentPageIndex != _pageIndexBeforeRotation) {
        [self jumpToPageAtIndex:_pageIndexBeforeRotation animated:NO];
    }

    [self.view setNeedsLayout];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    _viewIsActive = YES;
    _viewHasAppearedInitially = YES;
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];

    _pageIndexBeforeRotation = _currentPageIndex;

    // isMovingFromParentViewController / isBeingDismissed 在此场景不可靠，改用导航栈判定。
    if (self.navigationController.isBeingDismissed ||
        ([self.navigationController.viewControllers objectAtIndex:0] != self &&
         ![self.navigationController.viewControllers containsObject:self])) {
        _viewIsActive = NO;
        [self restorePreviousNavBarAppearance:animated];
    }

    [self.navigationController.navigationBar.layer removeAllAnimations];
    [NSObject cancelPreviousPerformRequestsWithTarget:self];
    [self cancelPendingTapToggle];
    [self setControlsHidden:NO animated:NO permanent:YES];
}

- (void)willMoveToParentViewController:(UIViewController *)parent {
    [super willMoveToParentViewController:parent];
    if (parent && _hasBelongedToViewController) {
        [NSException raise:@"MWPhotoBrowser Instance Reuse" format:@"MWPhotoBrowser instances cannot be reused."];
    }
}

- (void)didMoveToParentViewController:(UIViewController *)parent {
    [super didMoveToParentViewController:parent];
    if (!parent) _hasBelongedToViewController = YES;
}

#pragma mark - Properties

- (void)setCurrentPhotoIndex:(NSUInteger)index {
    NSUInteger photoCount = [self numberOfPhotos];
    if (photoCount == 0) {
        index = 0;
    } else if (index >= photoCount) {
        index = photoCount - 1;
    }
    _currentPageIndex = index;
    if ([self isViewLoaded]) {
        [self jumpToPageAtIndex:index animated:NO];
        // 视图不可见时强制铺页，保证首次显示即为正确页。
        if (!_viewIsActive) [self tilePages];
    }
}

#pragma mark - Actions

- (void)doneButtonPressed:(id)sender {
    // 网格模式下完成按钮用于在网格与单图之间切换。
    if (self.enableGrid) {
        if (self.startOnGrid && !_gridController) {
            [self showGrid:YES];
            return;
        } else if (!self.startOnGrid && _gridController) {
            [self hideGrid];
            return;
        }
    }
    if ([_delegate respondsToSelector:@selector(photoBrowserDidFinishModalPresentation:)]) {
        [_delegate photoBrowserDidFinishModalPresentation:self];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

@end
