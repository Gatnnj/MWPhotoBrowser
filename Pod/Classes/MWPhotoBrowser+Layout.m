//
//  MWPhotoBrowser+Layout.m
//  MWPhotoBrowser
//
//  布局与坐标：可见页布局、旋转适配、分页/工具栏 Frame 计算
//

#import "MWPhotoBrowser.h"
#import "MWPhotoBrowserPrivate.h"

@implementation MWPhotoBrowser (Layout)

#pragma mark - Layout

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    [self layoutVisiblePages];
}

- (void)layoutVisiblePages {

    // 标记布局进行中
    _performingLayout = YES;

    // 工具栏 frame
    _toolbar.frame = [self frameForToolbarAtOrientation:[self mw_currentInterfaceOrientation]];

    // 记录布局前页码，布局后保持同一页
    NSUInteger indexPriorToLayout = _currentPageIndex;

    // 取分页滚动视图 frame，判断是否需要变更
    CGRect pagingScrollViewFrame = [self frameForPagingScrollView];

    if (!_skipNextPagingScrollViewPositioning) {
        _pagingScrollView.frame = pagingScrollViewFrame;
    }
    _skipNextPagingScrollViewPositioning = NO;

    // 按当前方向重算 contentSize
    _pagingScrollView.contentSize = [self contentSizeForPagingScrollView];

    // 调整各可见页 frame
    for (MWZoomingScrollView *page in _visiblePages) {
        NSUInteger index = page.index;
        page.frame = [self frameForPageAtIndex:index];

        // bounds 变化时重算缩放比例
        if (!CGRectEqualToRect(_previousLayoutBounds, self.view.bounds)) {
            [page setMaxMinZoomScalesForCurrentBounds];
            _previousLayoutBounds = self.view.bounds;
        }

    }

    // 保持布局前所在页的偏移
    _pagingScrollView.contentOffset = [self contentOffsetForPageAtIndex:indexPriorToLayout];
    [self didStartViewingPageAtIndex:_currentPageIndex]; // initial

    // 复位布局标记
    _currentPageIndex = indexPriorToLayout;
    _performingLayout = NO;

}

#pragma mark - Rotation

- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAll;
}

// 旧的 shouldAutorotateToInterfaceOrientation/willRotate/willAnimateRotation/didRotate
// 四个 iOS 8 废弃回调已合并为这一个现代回调，原有三段逻辑分别迁移到
// 过渡前准备、过渡动画、过渡完成三个阶段，行为保持一致
- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];

    // —— 对应旧 willRotate：记录旋转前页码，标记旋转中 ——
    _pageIndexBeforeRotation = _currentPageIndex;
    _rotating = YES;
    if ([self areControlsHidden]) {
        // 旋转中强制隐藏导航栏
        self.navigationController.navigationBarHidden = YES;
    }

    // 控件隐藏延迟计时，对应旧 willAnimate 中的 hideControlsAfterDelay
    [self hideControlsAfterDelay];

    [coordinator animateAlongsideTransition:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        // —— 对应旧 willAnimate：恢复页码并执行布局 ——
        self->_currentPageIndex = self->_pageIndexBeforeRotation;
        [self layoutVisiblePages];
    } completion:^(id<UIViewControllerTransitionCoordinatorContext> context) {
        // —— 对应旧 didRotate：结束旋转，导航栏保持隐藏但还原其 hidden 状态 ——
        self->_rotating = NO;
        if ([self areControlsHidden]) {
            self.navigationController.navigationBarHidden = NO;
            self.navigationController.navigationBar.alpha = 0;
        }
    }];
}

#pragma mark - Frame Calculations

- (CGRect)frameForPagingScrollView {
    CGRect frame = self.view.bounds;
    frame.origin.x -= PADDING;
    frame.size.width += (2 * PADDING);
    return CGRectIntegral(frame);
}

- (CGRect)frameForPageAtIndex:(NSUInteger)index {
    // 用 bounds 而非 frame：frame 处于窗口坐标不随旋转变，bounds 才反映实际方向
    CGRect bounds = _pagingScrollView.bounds;
    CGRect pageFrame = bounds;
    pageFrame.size.width -= (2 * PADDING);
    pageFrame.origin.x = (bounds.size.width * index) + PADDING;
    return CGRectIntegral(pageFrame);
}

- (CGSize)contentSizeForPagingScrollView {
    // 同样用 bounds 计算 contentSize
    CGRect bounds = _pagingScrollView.bounds;
    return CGSizeMake(bounds.size.width * [self numberOfPhotos], bounds.size.height);
}

- (CGPoint)contentOffsetForPageAtIndex:(NSUInteger)index {
    CGFloat pageWidth = _pagingScrollView.bounds.size.width;
    CGFloat newOffset = index * pageWidth;
    return CGPointMake(newOffset, 0);
}

/// 获取当前界面方向，替代已废弃的 self.interfaceOrientation（iOS 8 废弃）
- (UIInterfaceOrientation)mw_currentInterfaceOrientation {
    // 优先从 windowScene 获取（iOS 13+）
    UIWindowScene *windowScene = self.view.window.windowScene;
    if (windowScene) {
        return windowScene.interfaceOrientation;
    }
    // 视图尚未挂到 window 时，根据 bounds 尺寸兜底判断
    return self.view.bounds.size.width > self.view.bounds.size.height
        ? UIInterfaceOrientationLandscapeLeft
        : UIInterfaceOrientationPortrait;
}

- (CGRect)frameForToolbarAtOrientation:(UIInterfaceOrientation)orientation {
    (void)orientation;
    return CGRectIntegral([_toolbar frameForContainerBounds:self.view.bounds safeAreaInsets:self.view.safeAreaInsets]);
}

@end
