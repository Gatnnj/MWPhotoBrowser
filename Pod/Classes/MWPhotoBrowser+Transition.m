//
//  MWPhotoBrowser+Transition.m
//  MWPhotoBrowser
//
//  自定义转场：起始缩略图解析、present/dismiss 动画器、交互控制器
//

#import "MWPhotoBrowser.h"
#import "MWPhotoBrowserPrivate.h"
#import "MWPhotoTransitionAnimator.h"
#import <QuartzCore/QuartzCore.h>

/// 取过渡图片：UIImageView 直接取 image，否则渲染图层快照
static UIImage *MWTransitionSnapshot(UIView *view) {
    if ([view isKindOfClass:UIImageView.class]) {
        UIImage *image = ((UIImageView *)view).image;
        if (image) return image;
    }
    if (!view || CGRectIsEmpty(view.bounds)) return nil;
    UIGraphicsBeginImageContextWithOptions(view.bounds.size, NO, 0);
    [view.layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return image;
}

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
    // 同时支持 UIImageView 起点与其它投影视图快照，保证连贯飞行可走兜底
    animator.transitionImage = MWTransitionSnapshot(startView);
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
