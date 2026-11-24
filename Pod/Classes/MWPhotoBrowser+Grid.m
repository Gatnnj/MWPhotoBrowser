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
    // Public entry point: prepare the view and grid prerequisites first, so the call
    // never fails silently or shows an empty grid.
    [self loadViewIfNeeded];
    if (!self.enableGrid) return;
    if (_gridTransitioning) return;
    if (_gridController) return;
    _gridTransitioning = YES;
    _isShowingGrid = YES;

    // Init grid controller
    _gridController = [[MWGridViewController alloc] init];
    _gridController.browser = self;
    _gridController.view.frame = self.view.bounds;
    _gridController.view.frame = CGRectOffset(_gridController.view.frame, 0, (self.startOnGrid ? -1 : 1) * self.view.bounds.size.height);

    // Stop specific layout being triggered
    _skipNextPagingScrollViewPositioning = YES;

    // Add as a child view controller
    [self addChildViewController:_gridController];
    [self.view addSubview:_gridController.view];

    // Grid gets its own downward gesture. The photo-browser pull gesture stays
    // disabled while a grid is present, so this can only close the grid.
    _gridDismissPanGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handleGridDismissPan:)];
    _gridDismissPanGesture.delegate = self;
    _gridDismissPanGesture.cancelsTouchesInView = NO;
    [_gridController.view addGestureRecognizer:_gridDismissPanGesture];
    // At the top, let a downward grid-dismiss pan win before the collection
    // view's pan. If it rejects the gesture, normal scrolling proceeds without
    // interruption or a content-offset reset.
    [_gridController.collectionView.panGestureRecognizer requireGestureRecognizerToFail:_gridDismissPanGesture];

    // Perform any adjustments
    [_gridController.view layoutIfNeeded];
    [_gridController adjustOffsetsAsRequired];

    // Update
    [self updateNavigation];
    [self setControlsHidden:NO animated:YES permanent:YES];

    // Animate grid in and photo scroller out
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

- (void)hideGrid {

    if (!_gridController) return;
    _gridTransitioning = YES;

    // Position prior to hide animation
    CGRect newPagingFrame = [self frameForPagingScrollView];
    newPagingFrame = CGRectOffset(newPagingFrame, 0, (self.startOnGrid ? 1 : -1) * newPagingFrame.size.height);
    _pagingScrollView.frame = newPagingFrame;

    // Remember and remove controller now so things can detect a nil grid controller
    MWGridViewController *tmpGridController = _gridController;
    if (_gridDismissPanGesture) {
        [tmpGridController.view removeGestureRecognizer:_gridDismissPanGesture];
        _gridDismissPanGesture.delegate = nil;
        _gridDismissPanGesture = nil;
    }
    _gridController = nil;
    _isShowingGrid = NO;

    // Update
    [self updateNavigation];

    // Animate, hide grid and show paging scroll view
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

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer {
    if (gestureRecognizer != _gridDismissPanGesture) return YES;
    if (!_gridController || _gridTransitioning) return NO;

    CGPoint velocity = [(UIPanGestureRecognizer *)gestureRecognizer velocityInView:self.view];
    if (velocity.y <= 0 || velocity.y <= fabs(velocity.x) * 1.15) return NO;

    CGFloat topOffset = -_gridController.collectionView.adjustedContentInset.top;
    return _gridController.collectionView.contentOffset.y <= topOffset + 1.0;
}

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
