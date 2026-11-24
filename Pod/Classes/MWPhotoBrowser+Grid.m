//
//  MWPhotoBrowser+Grid.m
//  MWPhotoBrowser
//
//  网格总览：网格控制器展示/隐藏、下拉关闭手势与手势判定
//

#import "MWPhotoBrowser.h"
#import "MWPhotoBrowserPrivate.h"

@implementation MWPhotoBrowser (Grid)

- (void)showGridAnimated {
    [self showGrid:YES];
}

- (void)showGrid:(BOOL)animated {

    // 外部调用入口：先确保视图与网格前置条件就绪，避免静默失败或空白网格。
    [self loadViewIfNeeded];
    if (!self.enableGrid) return;
    if (_gridTransitioning) return;
    if (_gridController) return;
    _gridTransitioning = YES;
    _isShowingGrid = YES;

    // 创建网格控制器
    _gridController = [[MWGridViewController alloc] init];
    _gridController.browser = self;
    _gridController.view.frame = self.view.bounds;
    _gridController.view.frame = CGRectOffset(_gridController.view.frame, 0, (self.startOnGrid ? -1 : 1) * self.view.bounds.size.height);

    // 跳过下一次分页滚动视图定位，避免触发多余布局
    _skipNextPagingScrollViewPositioning = YES;

    // 挂载为子控制器
    [self addChildViewController:_gridController];
    [self.view addSubview:_gridController.view];

    // 网格单独挂下滑关闭手势；网格展示期间大图下拉手势已禁用，此手势只用于关闭网格
    _gridDismissPanGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleGridDismissPan:)];
    _gridDismissPanGesture.delegate = self;
    _gridDismissPanGesture.cancelsTouchesInView = NO;
    [_gridController.view addGestureRecognizer:_gridDismissPanGesture];
    // 顶部时让下滑关闭手势优先于 collectionView 的 pan；被拒绝则正常滚动，不打断也不重置偏移
    [_gridController.collectionView.panGestureRecognizer requireGestureRecognizerToFail:_gridDismissPanGesture];

    // 触发布局并把当前页居中定位
    [_gridController.view layoutIfNeeded];
    [_gridController adjustOffsetsAsRequired];

    // 更新导航并常显控件
    [self updateNavigation];
    [self setControlsHidden:NO animated:YES permanent:YES];

    // 网格滑入、分页滚动视图滑出
    [_gridController willMoveToParentViewController:self];
    [UIView animateWithDuration:animated ? 0.3 : 0 animations:^(void) {
        // 显式 self 消除 block 隐式 retain 警告
        self->_gridController.view.frame = self.view.bounds;
        CGRect newPagingFrame = [self frameForPagingScrollView];
        newPagingFrame = CGRectOffset(newPagingFrame, 0, (self.startOnGrid ? 1 : -1) * newPagingFrame.size.height);
        self->_pagingScrollView.frame = newPagingFrame;
    } completion:^(BOOL finished) {
        [self->_gridController didMoveToParentViewController:self];
        if (self->_gridController) self->_gridTransitioning = NO;
    }];

}

/// 关闭网格：滑出网格并回到单图分页
- (void)hideGrid {

    if (!_gridController) return;
    _gridTransitioning = YES;

    // 动画前先把分页视图放到滑出起点
    CGRect newPagingFrame = [self frameForPagingScrollView];
    newPagingFrame = CGRectOffset(newPagingFrame, 0, (self.startOnGrid ? 1 : -1) * newPagingFrame.size.height);
    _pagingScrollView.frame = newPagingFrame;

    // 先暂存并清空控制器，便于外部检测 nil
    MWGridViewController *tmpGridController = _gridController;
    if (_gridDismissPanGesture) {
        [tmpGridController.view removeGestureRecognizer:_gridDismissPanGesture];
        _gridDismissPanGesture.delegate = nil;
        _gridDismissPanGesture = nil;
    }
    _gridController = nil;
    _isShowingGrid = NO;

    // 更新导航
    [self updateNavigation];

    // 网格滑出、分页视图归位
    [UIView animateWithDuration:0.3 animations:^{
        tmpGridController.view.frame = CGRectOffset(self.view.bounds, 0, (self.startOnGrid ? -1 : 1) * self.view.bounds.size.height);
        // 显式 self 消除 block 隐式 retain 警告
        self->_pagingScrollView.frame = [self frameForPagingScrollView];
    } completion:^(BOOL finished) {
        [tmpGridController willMoveToParentViewController:nil];
        [tmpGridController.view removeFromSuperview];
        [tmpGridController removeFromParentViewController];
        self->_gridTransitioning = NO;
        [self setControlsHidden:NO animated:YES permanent:NO]; // retrigger timer
    }];

}

/// 网格下滑关闭手势的判定：仅顶部、且为向下主导的拖动才允许开始
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer != _gridDismissPanGesture) return YES;
    if (!_gridController || _gridTransitioning) return NO;

    CGPoint velocity = [(UIPanGestureRecognizer *)gestureRecognizer velocityInView:self.view];
    if (velocity.y <= 0 || velocity.y <= fabs(velocity.x) * 1.15) return NO;

    // 只有滚动到顶部附近才响应下滑关闭
    CGFloat topOffset = -_gridController.collectionView.adjustedContentInset.top;
    return _gridController.collectionView.contentOffset.y <= topOffset + 1.0;
}

/// 网格下滑手势处理：跟手下移，松手达阈值关闭否则回弹
- (void)handleGridDismissPan:(UIPanGestureRecognizer *)pan {
    if (!_gridController) return;
    switch (pan.state) {
        case UIGestureRecognizerStateBegan:
            break;
        case UIGestureRecognizerStateChanged: {
            CGFloat downward = MAX(0, [pan translationInView:self.view].y);
            CGRect frame = self.view.bounds;
            frame.origin.y = downward;
            _gridController.view.frame = frame;
            break;
        }
        case UIGestureRecognizerStateEnded: {
            CGPoint translation = [pan translationInView:self.view];
            CGPoint velocity = [pan velocityInView:self.view];
            BOOL shouldClose = translation.y > self.view.bounds.size.height * 0.2 || velocity.y > 650;
            if (shouldClose) {
                [self hideGrid];
            } else {
                [UIView animateWithDuration:0.25 delay:0 usingSpringWithDamping:0.86 initialSpringVelocity:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
                    self->_gridController.view.frame = self.view.bounds;
                } completion:nil];
            }
            break;
        }
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed: {
            [UIView animateWithDuration:0.25 delay:0 usingSpringWithDamping:0.86 initialSpringVelocity:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
                self->_gridController.view.frame = self.view.bounds;
            } completion:nil];
        }
            break;
        default:
            break;
    }
}

@end
