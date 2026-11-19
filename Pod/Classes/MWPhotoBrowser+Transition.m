//
//  MWPhotoBrowser+Transition.m
//  MWPhotoBrowser
//
//  自定义转场：起始缩略图解析、present/dismiss 动画器、交互控制器
//

#import "MWPhotoBrowser.h"
#import "MWPhotoBrowserPrivate.h"
#import "MWPhotoTransitionAnimator.h"

@implementation MWPhotoBrowser (Transition)

/// 获取当前图片对应的起始缩略图视图（调用方未实现则为 nil）
- (UIView *)mw_startingView {
    if (self.startingViewProvider) {
        UIView *startingView = self.startingViewProvider(_currentPageIndex);
        if (startingView) return startingView;
    }
    if ([self.delegate respondsToSelector:@selector(photoBrowser:startingViewForPhotoAtIndex:)]) {
        return [self.delegate photoBrowser:self startingViewForPhotoAtIndex:_currentPageIndex];
    }
    return nil;
}

- (id<UIViewControllerAnimatedTransitioning>)animationControllerForPresentedController:(UIViewController *)presented
                                                                   presentingController:(UIViewController *)presenting
                                                                       sourceController:(UIViewController *)source {
    MWPhotoTransitionAnimator *animator = [[MWPhotoTransitionAnimator alloc] init];
    animator.dismissing = NO;
    UIView *startView = [self mw_startingView];
    animator.startView = startView;
    MWZoomingScrollView *page = [self pageDisplayedAtIndex:_currentPageIndex];
    animator.destinationImageView = [page photoImageViewForTransition];
    // 取缩略图上的图片作为连贯移动素材，取不到则动画器内部自动降级渐隐
    if ([startView isKindOfClass:[UIImageView class]]) {
        animator.transitionImage = ((UIImageView *)startView).image;
    }
    return animator;
}

- (id<UIViewControllerAnimatedTransitioning>)animationControllerForDismissedController:(UIViewController *)dismissed {
    MWPhotoTransitionAnimator *animator = [[MWPhotoTransitionAnimator alloc] init];
    animator.dismissing = YES;
    // 关闭时飞回的目标缩略图
    animator.endView = [self mw_startingView];
    // 提供当前页图片视图，动画器从其当前实际位置（含拖拽 transform）飞回
    MWZoomingScrollView *page = [self pageDisplayedAtIndex:_currentPageIndex];
    animator.dismissingImageView = [page photoImageViewForTransition];
    return animator;
}

- (id<UIViewControllerInteractiveTransitioning>)interactionControllerForDismissal:(id<UIViewControllerAnimatedTransitioning>)animator {
    // 拖拽在手势结束后以非交互方式触发，始终返回 nil
    return nil;
}

- (id<UIViewControllerInteractiveTransitioning>)interactionControllerForPresentation:(id<UIViewControllerAnimatedTransitioning>)animator {
    return nil;
}

@end
