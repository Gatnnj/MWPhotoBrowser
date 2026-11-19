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

    // Flag
    _performingLayout = YES;

    // Toolbar
    _toolbar.frame = [self frameForToolbarAtOrientation:[self mw_currentInterfaceOrientation]];

    // Remember index
    NSUInteger indexPriorToLayout = _currentPageIndex;

    // Get paging scroll view frame to determine if anything needs changing
    CGRect pagingScrollViewFrame = [self frameForPagingScrollView];

    // Frame needs changing
    if (!_skipNextPagingScrollViewPositioning) {
        _pagingScrollView.frame = pagingScrollViewFrame;
    }
    _skipNextPagingScrollViewPositioning = NO;

    // Recalculate contentSize based on current orientation
    _pagingScrollView.contentSize = [self contentSizeForPagingScrollView];

    // Adjust frames and configuration of each visible page
    for (MWZoomingScrollView *page in _visiblePages) {
        NSUInteger index = page.index;
        page.frame = [self frameForPageAtIndex:index];

        // Adjust scales if bounds has changed since last time
        if (!CGRectEqualToRect(_previousLayoutBounds, self.view.bounds)) {
            // Update zooms for new bounds
            [page setMaxMinZoomScalesForCurrentBounds];
            _previousLayoutBounds = self.view.bounds;
        }

    }

    // Adjust contentOffset to preserve page location based on values collected prior to location
    _pagingScrollView.contentOffset = [self contentOffsetForPageAtIndex:indexPriorToLayout];
    [self didStartViewingPageAtIndex:_currentPageIndex]; // initial

    // Reset
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
        // Force hidden
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
    CGRect frame = self.view.bounds;// [[UIScreen mainScreen] bounds];
    frame.origin.x -= PADDING;
    frame.size.width += (2 * PADDING);
    return CGRectIntegral(frame);
}

- (CGRect)frameForPageAtIndex:(NSUInteger)index {
    // We have to use our paging scroll view's bounds, not frame, to calculate the page placement. When the device is in
    // landscape orientation, the frame will still be in portrait because the pagingScrollView is the root view controller's
    // view, so its frame is in window coordinate space, which is never rotated. Its bounds, however, will be in landscape
    // because it has a rotation transform applied.
    CGRect bounds = _pagingScrollView.bounds;
    CGRect pageFrame = bounds;
    pageFrame.size.width -= (2 * PADDING);
    pageFrame.origin.x = (bounds.size.width * index) + PADDING;
    return CGRectIntegral(pageFrame);
}

- (CGSize)contentSizeForPagingScrollView {
    // We have to use the paging scroll view's bounds to calculate the contentSize, for the same reason outlined above.
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
    CGFloat width = self.view.bounds.size.width;
    CGFloat height = 83;
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone &&
        UIInterfaceOrientationIsLandscape(orientation)) height = self.view.bounds.size.width;
    return CGRectIntegral(CGRectMake(0, self.view.bounds.size.height - height, width, height));
}

@end
