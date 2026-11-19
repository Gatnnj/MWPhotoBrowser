//
//  MWPhotoBrowser.m
//  MWPhotoBrowser
//
//  主实现：初始化、生命周期、视图加载与布局入口；
//  数据源 / 分页 / 布局 / 导航 / 网格 / 控件 / 导航栏 / 转场逻辑见对应 Category 文件。
//
//  Created by Michael Waterfall on 14/10/2010.
//  Copyright 2010 d3i. All rights reserved.
//

#import <QuartzCore/QuartzCore.h>
#import "MWCommon.h"
#import "MWPhotoBrowser.h"
#import "MWPhotoBrowserPrivate.h"
#import "MWPhotoTransitionAnimator.h"
#import "MWPhotoInteractiveTransition.h"
#import "UIImage+MWPhotoBrowser.h"

@implementation MWPhotoBrowser

#pragma mark - Init

- (instancetype)init {
    if ((self = [super init])) {
        [self _initialisation];
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
        [self _initialisation];
    }
    return self;
}

- (void)_initialisation {

    // 旧的 UIViewControllerBasedStatusBarAppearance 判断已移除：
    // iOS 13 起状态栏外观统一由视图控制器管理（本库下限 iOS 15），
    // 不再存在非 VC based 的生效路径，相关逻辑由 preferredStatusBarStyle/
    // prefersStatusBarHidden + setNeedsStatusBarAppearanceUpdate 实现
    self.hidesBottomBarWhenPushed = YES;
    _hasBelongedToViewController = NO;
    _photoCount = NSNotFound;
    _previousLayoutBounds = CGRectZero;
    _currentPageIndex = 0;
    _previousPageIndex = NSUIntegerMax;
    _zoomPhotosToFill = YES;
    _performingLayout = NO; // Reset on view did appear
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
    _currentGridContentOffset = CGPointMake(0, CGFLOAT_MAX);
    _didSavePreviousStateOfNavBar = NO;
    // 旧的 automaticallyAdjustsScrollViewInsets（iOS 11 废弃）已移除，
    // 等价设置在 pagingScrollView 创建处通过 contentInsetAdjustmentBehavior 完成

    // Listen for MWPhoto notifications
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleMWPhotoLoadingDidEndNotification:)
                                                 name:MWPHOTO_LOADING_DID_END_NOTIFICATION
                                               object:nil];

}

- (void)dealloc {
    // 撤销排队中的单击切换显隐（block 只弱持有 self，这里取消是为了不再回调到已销毁对象）
    [self cancelPendingTapToggle];
    // 控件显隐定时器必须在这里断开：它持有 self，不断开会拖住整个视图树延迟释放
    [self cancelControlHiding];
    _pagingScrollView.delegate = nil;
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [self releaseAllUnderlyingPhotos:NO];
    // 不再调用 [[SDImageCache sharedImageCache] clearMemory]：
    // sharedImageCache 是全局单例，在这里清会连带清掉宿主 App 其他页面的图片内存缓存，
    // 关闭一个相册浏览器不该影响整个进程。内存压力交给 SDWebImage 自身的
    // didReceiveMemoryWarning 监听处理。
}

- (void)didReceiveMemoryWarning {

    // Release any cached data, images, etc that aren't in use.
    [self releaseAllUnderlyingPhotos:YES];
    [_recycledPages removeAllObjects];

    // Releases the view if it doesn't have a superview.
    [super didReceiveMemoryWarning];

}

#pragma mark - View Loading

// Implement viewDidLoad to do additional setup after loading the view, typically from a nib.
- (void)viewDidLoad {

    // Validate grid settings
    if (_startOnGrid) _enableGrid = YES;
    if (_enableGrid) {
        _enableGrid = [_delegate respondsToSelector:@selector(photoBrowser:thumbPhotoAtIndex:)];
    }
    if (!_enableGrid) _startOnGrid = NO;

    // View
    self.view.backgroundColor = [UIColor clearColor];
    self.view.opaque = NO;
    self.view.clipsToBounds = YES;

    // Setup paging scrolling view
    CGRect pagingScrollViewFrame = [self frameForPagingScrollView];
    _pagingScrollView = [[UIScrollView alloc] initWithFrame:pagingScrollViewFrame];
    // 等价于旧的 self.automaticallyAdjustsScrollViewInsets = NO，
    // 明确禁止系统自动调整安全区 inset，保持现有手动布局不变
    _pagingScrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    _pagingScrollView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _pagingScrollView.pagingEnabled = YES;
    _pagingScrollView.delegate = self;
    _pagingScrollView.showsHorizontalScrollIndicator = NO;
    _pagingScrollView.showsVerticalScrollIndicator = NO;
    _pagingScrollView.backgroundColor = [UIColor blackColor];
    _pagingScrollView.opaque = NO;
    _pagingScrollView.contentSize = [self contentSizeForPagingScrollView];
    [self.view addSubview:_pagingScrollView];

    // Toolbar
    _toolbar = [[MWToolBar alloc] initWithFrame:[self frameForToolbarAtOrientation:[self mw_currentInterfaceOrientation]]];
    _toolbar.clipsToBounds = YES;
    [self.view addSubview:_toolbar];
    [_toolbar setHidden:_isHiddenToolBar];


    // 自定义丝滑转场：交互控制器把手势装在根视图，只对内部图片视图做 transform
    // （对照 JXPhotoBrowser），因此与 reloadData 先后顺序无关
    if (_enableCustomTransition) {
        __weak typeof(self) weakSelf = self;
        self.interactiveTransition =
        [[MWPhotoInteractiveTransition alloc] initWithCurrentImageViewBlock:^UIView *{
            MWPhotoBrowser *strongSelf = weakSelf;
            if (!strongSelf) return nil;
            // Grid overlays the photo pages; do not let its vertical pan start
            // the photo-browser pull-to-dismiss interaction.
            if (strongSelf->_gridController || strongSelf->_gridTransitioning) return nil;
            // 先按当前索引找 page；找不到（索引不匹配）时退化为取任意可见页
            MWZoomingScrollView *page = [strongSelf pageDisplayedAtIndex:strongSelf.currentIndex];
            if (!page && strongSelf->_visiblePages.count > 0) {
                page = strongSelf->_visiblePages.allObjects.firstObject;
            }
            // 正确的"未放大"判断：当前处于最小缩放（初始 zoomScale 可能不等于 1）
            if (page.zoomScale > page.minimumZoomScale + 0.01) return nil;
            return [page photoImageViewForTransition];
        } setPagingEnabled:^(BOOL enabled) {
            MWPhotoBrowser *strongSelf = weakSelf;
            // nil 时直接返回：nil 的 ivar 直接解引用会崩溃（给 nil 发消息才安全）
            if (!strongSelf) return;
            strongSelf->_pagingScrollView.scrollEnabled = enabled;
        } setBackgroundAlpha:^(CGFloat alpha) {
            MWPhotoBrowser *strongSelf = weakSelf;
            if (!strongSelf) return;
            // 统一控制各层黑色背景，图片本身不透明
            UIColor *background = [UIColor colorWithWhite:0 alpha:alpha];
            strongSelf.view.backgroundColor = background;
            strongSelf.view.opaque = NO;
            strongSelf.navigationController.view.backgroundColor = [UIColor clearColor];
            strongSelf.navigationController.view.opaque = NO;
            // 导航栏整体（含标题和按钮）与浏览器背景共用同一 alpha。
//            strongSelf.navigationController.navigationBar.alpha = alpha;
            strongSelf->_pagingScrollView.backgroundColor = background;
            strongSelf->_pagingScrollView.opaque = NO;
            for (MWZoomingScrollView *page in strongSelf->_visiblePages) {
                [page setBackgroundAlpha:alpha];
            }
        } dismissTargetBlock:^UIView *{
            return [weakSelf mw_startingView];
        } dismissBlock:^{
            // 拖拽快照已经完成了完整的缩略图回收动画，系统 dismiss 动画关闭，
            // 避免松手后又额外播放一次重复的 zoom-out。
            MWPhotoBrowser *strongSelf = weakSelf;
            [strongSelf dismissViewControllerAnimated:NO completion:nil];
        }];
        self.interactiveTransition.interactionDidRestore = ^{
            MWPhotoBrowser *strongSelf = weakSelf;
            if (!strongSelf || !strongSelf->_pendingReloadData) return;
            strongSelf->_pendingReloadData = NO;
            [strongSelf reloadData];
        };
        // 手势安装在浏览器根视图
        [self.interactiveTransition installGestureOnRootView:self.view];
    }

    // Update
    [self reloadData];

    // 自定义转场启用时由交互式下拉手势负责关闭；旧的 swipe 手势会
    // 在手指释放前直接触发 dismiss，破坏图片跟手的交互体验。
    if (_enableSwipeToDismiss && !_enableCustomTransition) {
        UISwipeGestureRecognizer *swipeGesture = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(doneButtonPressed:)];
        swipeGesture.direction = UISwipeGestureRecognizerDirectionDown | UISwipeGestureRecognizerDirectionUp;
        [self.view addGestureRecognizer:swipeGesture];
    }

    // Super
    [super viewDidLoad];

}

- (void)performLayout {

    // Setup
    _performingLayout = YES;

    // Setup pages
    [_visiblePages removeAllObjects];
    [_recycledPages removeAllObjects];

    // Update nav
    [self updateNavigation];

    // Content offset
    _pagingScrollView.contentOffset = [self contentOffsetForPageAtIndex:_currentPageIndex];
    [self tilePages];
    _performingLayout = NO;

}

/// add toolBar
- (void)customToolBarItems:(NSArray<UIButton *> *)array {
    [_toolbar addItems:array];
}

#pragma mark - Appearance

- (void)viewWillAppear:(BOOL)animated {

    // Super
    [super viewWillAppear:animated];

    // Status bar
    if (!_viewHasAppearedInitially) {
        _leaveStatusBarAlone = [self presentingViewControllerPrefersStatusBarHidden];
        // Check if status bar is hidden on first appear, and if so then ignore it
        // 旧的 statusBarFrame（iOS 9 废弃）替换为 statusBarManager.statusBarHidden
        UIStatusBarManager *statusBarManager = self.view.window.windowScene.statusBarManager;
        if (statusBarManager && statusBarManager.statusBarHidden) {
            _leaveStatusBarAlone = YES;
        }
    }
    // Set style
    // 旧的 setStatusBarStyle:animated:（iOS 9 废弃）替换为触发 VC 状态栏更新，
    // 具体样式由 preferredStatusBarStyle 返回 UIStatusBarStyleLightContent
    if (!_leaveStatusBarAlone && [[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone) {
        [self setNeedsStatusBarAppearanceUpdate];
    }

    // Navigation bar appearance
    if (!_viewIsActive && [self.navigationController.viewControllers objectAtIndex:0] != self) {
        [self storePreviousNavBarAppearance];
    }
    [self setNavBarAppearance:animated];

    // Update UI
    [self hideControlsAfterDelay];

    // Initial appearance
    if (!_viewHasAppearedInitially) {
        if (_startOnGrid) {
            [self showGrid:NO];
        }
    }

    // If rotation occured while we're presenting a modal
    // and the index changed, make sure we show the right one now
    if (_currentPageIndex != _pageIndexBeforeRotation) {
        [self jumpToPageAtIndex:_pageIndexBeforeRotation animated:NO];
    }

    // Layout
    [self.view setNeedsLayout];

}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    _viewIsActive = YES;

    _viewHasAppearedInitially = YES;

}

- (void)viewWillDisappear:(BOOL)animated {

    // Detect if rotation occurs while we're presenting a modal
    _pageIndexBeforeRotation = _currentPageIndex;

    // Check that we're disappearing for good
    // self.isMovingFromParentViewController just doesn't work, ever. Or self.isBeingDismissed
    if (self.navigationController.isBeingDismissed ||
        ([self.navigationController.viewControllers objectAtIndex:0] != self && ![self.navigationController.viewControllers containsObject:self])) {

        // State
        _viewIsActive = NO;

        // Bar state / appearance
        [self restorePreviousNavBarAppearance:animated];

    }

    // Controls
    [self.navigationController.navigationBar.layer removeAllAnimations]; // Stop all animations on nav bar
    [NSObject cancelPreviousPerformRequestsWithTarget:self]; // 取消历史 performSelector 排队的调用
    [self cancelPendingTapToggle]; // 撤销排队中的单击切换显隐，避免退出过渡期间控件又隐藏
    [self setControlsHidden:NO animated:NO permanent:YES];

    // 旧的 setStatusBarStyle 还原逻辑已移除：现代机制下系统会根据
    // preferredStatusBarStyle 自动管理，无需手动保存和恢复状态栏样式

    // Super
    [super viewWillDisappear:animated];

}

- (void)willMoveToParentViewController:(UIViewController *)parent {
    if (parent && _hasBelongedToViewController) {
        [NSException raise:@"MWPhotoBrowser Instance Reuse" format:@"MWPhotoBrowser instances cannot be reused."];
    }
}

- (void)didMoveToParentViewController:(UIViewController *)parent {
    if (!parent) _hasBelongedToViewController = YES;
}

#pragma mark - Properties

- (void)setCurrentPhotoIndex:(NSUInteger)index {
    // Validate
    NSUInteger photoCount = [self numberOfPhotos];
    if (photoCount == 0) {
        index = 0;
    } else {
        if (index >= photoCount)
            index = [self numberOfPhotos]-1;
    }
    _currentPageIndex = index;
    if ([self isViewLoaded]) {
        [self jumpToPageAtIndex:index animated:NO];
        if (!_viewIsActive)
            [self tilePages]; // Force tiling if view is not visible
    }
}

#pragma mark - Misc

- (void)doneButtonPressed:(id)sender {
    // See if we actually just want to show/hide grid
    if (self.enableGrid) {
        if (self.startOnGrid && !_gridController) {
            [self showGrid:YES];
            return;
        } else if (!self.startOnGrid && _gridController) {
            [self hideGrid];
            return;
        }
    }
    // Dismiss view controller
    if ([_delegate respondsToSelector:@selector(photoBrowserDidFinishModalPresentation:)]) {
        // Call delegate method and let them dismiss us
        [_delegate photoBrowserDidFinishModalPresentation:self];
    } else  {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

@end
