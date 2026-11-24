#import "MWPhotoTransitionAnimator.h"

@interface MWPhotoTransitionAnimator ()
@property (nonatomic, weak) UIView *hiddenSourceView;
@property (nonatomic, weak) UIView *hiddenDestinationView;
@end

@implementation MWPhotoTransitionAnimator

- (instancetype)init {
    if ((self = [super init])) _duration = 0.25;
    return self;
}

- (NSTimeInterval)transitionDuration:(id<UIViewControllerContextTransitioning>)transitionContext { return self.duration; }

- (void)animateTransition:(id<UIViewControllerContextTransitioning>)ctx {
    if (self.isDismissing) [self mw_dismiss:ctx];
    else [self mw_present:ctx];
}

/// 以参考视图的内容样式创建飞行快照 UIImageView
- (UIImageView *)mw_imageViewWithImage:(UIImage *)image from:(UIView *)reference {
    UIImageView *view = [[UIImageView alloc] initWithImage:image];
    if ([reference isKindOfClass:UIImageView.class]) {
        UIImageView *referenceImageView = (UIImageView *)reference;
        view.contentMode = referenceImageView.contentMode;
        view.clipsToBounds = referenceImageView.clipsToBounds;
        view.backgroundColor = referenceImageView.backgroundColor;
        view.layer.cornerRadius = referenceImageView.layer.cornerRadius;
        view.layer.masksToBounds = referenceImageView.layer.masksToBounds;
    } else {
        view.contentMode = UIViewContentModeScaleAspectFit;
        view.clipsToBounds = YES;
    }
    if (reference) {
        view.layer.cornerRadius = reference.layer.cornerRadius;
    }
    return view;
}

/// 校验入场起点视图与过渡图片是否齐全可用
- (BOOL)mw_validSourceIn:(UIView *)container {
    return self.startView && self.startView.window && self.transitionImage && self.transitionImage.size.width > 0 && self.transitionImage.size.height > 0 && container.bounds.size.width > 0;
}

/// 按 aspectFit 计算图片在 bounds 内居中的 frame
- (CGRect)mw_aspectFitFrameForImage:(UIImage *)image inBounds:(CGRect)bounds {
    if (image.size.width <= 0 || image.size.height <= 0) return CGRectZero;
    CGFloat scale = MIN(CGRectGetWidth(bounds) / image.size.width,
                        CGRectGetHeight(bounds) / image.size.height);
    CGSize size = CGSizeMake(image.size.width * scale, image.size.height * scale);
    return CGRectMake(CGRectGetMidX(bounds) - size.width * 0.5,
                      CGRectGetMidY(bounds) - size.height * 0.5,
                      size.width, size.height);
}

/// 创建铺满容器的黑色背景层，动画期间用于压暗
- (UIView *)mw_blackBackdropInContainer:(UIView *)container alpha:(CGFloat)alpha {
    UIView *backdrop = [[UIView alloc] initWithFrame:container.bounds];
    backdrop.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    backdrop.backgroundColor = [UIColor colorWithWhite:0 alpha:alpha];
    [container addSubview:backdrop];
    return backdrop;
}

/// 入场：缩略图连贯放大到全屏；起点不可用时降级为渐隐
- (void)mw_present:(id<UIViewControllerContextTransitioning>)ctx {
    UIView *container = ctx.containerView;
    UIViewController *toVC = [ctx viewControllerForKey:UITransitionContextToViewControllerKey];
    UIView *toView = [ctx viewForKey:UITransitionContextToViewKey] ?: toVC.view;
    CGRect finalFrame = [ctx finalFrameForViewController:toVC];
    if (CGRectIsEmpty(finalFrame)) finalFrame = container.bounds;
    toView.frame = finalFrame;
    [container addSubview:toView];
    if (![self mw_validSourceIn:container]) {
        toView.alpha = 0;
        [UIView animateWithDuration:self.duration animations:^{ toView.alpha = 1; } completion:^(BOOL finished) {
            BOOL completed = !ctx.transitionWasCancelled;
            if (!completed) [toView removeFromSuperview];
            [ctx completeTransition:completed];
        }];
        return;
    }

    CGRect start = [self.startView convertRect:self.startView.bounds toView:container];
    // 先隐藏目标控制器，让独立缩略图快照飞到全屏 frame，避免目标 cell 尚未构建
    CGRect end = [self mw_aspectFitFrameForImage:self.transitionImage inBounds:container.bounds];
    UIImageView *moving = [self mw_imageViewWithImage:self.transitionImage from:self.startView];
    moving.frame = start;
    moving.image = self.transitionImage;
    [container addSubview:moving];
    self.hiddenSourceView = self.startView;
    self.startView.hidden = YES;
    UIView *backdrop = [self mw_blackBackdropInContainer:container alpha:0];
    [container bringSubviewToFront:moving];
    toView.alpha = 0;
    [UIView animateWithDuration:self.duration animations:^{
        moving.frame = end;
        backdrop.backgroundColor = UIColor.blackColor;
    } completion:^(BOOL finished) {
        BOOL completed = !ctx.transitionWasCancelled;
        [moving removeFromSuperview];
        self.hiddenSourceView.hidden = NO;
        toView.alpha = 1;
        [backdrop removeFromSuperview];
        if (!completed) [toView removeFromSuperview];
        [ctx completeTransition:completed];
    }];
}

/// 出场：图片飞回缩略图位置；目标不可用时降级为渐隐
- (void)mw_dismiss:(id<UIViewControllerContextTransitioning>)ctx {
    UIView *container = ctx.containerView;
    UIViewController *fromVC = [ctx viewControllerForKey:UITransitionContextFromViewControllerKey];
    UIView *fromView = [ctx viewForKey:UITransitionContextFromViewKey] ?: fromVC.view;
    UIView *target = self.endView;
    UIView *source = self.dismissingImageView;
    BOOL canZoom = target && target.window && source && source.window && [source isKindOfClass:UIImageView.class] && ((UIImageView *)source).image;
    if (!canZoom) {
        [UIView animateWithDuration:self.duration animations:^{ fromView.alpha = 0; } completion:^(BOOL finished) {
            BOOL completed = !ctx.transitionWasCancelled;
            target.hidden = NO;
            fromView.alpha = 1;
            [ctx completeTransition:completed];
        }];
        return;
    }

    CGRect start = [source convertRect:source.bounds toView:container];
    CGRect end = [target convertRect:target.bounds toView:container];
    // 缩小飞回前把飞行图换成目标缩略图的内容模式，使其贴合终点
    UIImageView *moving = [self mw_imageViewWithImage:((UIImageView *)source).image from:target];
    moving.frame = start;
    [container addSubview:moving];
    UIView *backdrop = [self mw_blackBackdropInContainer:container alpha:1];
    [container bringSubviewToFront:moving];
    fromView.alpha = 0;
    source.hidden = YES;
    target.hidden = YES;
    [UIView animateWithDuration:self.duration animations:^{
        moving.frame = end;
        backdrop.backgroundColor = [UIColor colorWithWhite:0 alpha:0];
    } completion:^(BOOL finished) {
        BOOL completed = !ctx.transitionWasCancelled;
        [moving removeFromSuperview];
        source.hidden = NO;
        target.hidden = NO;
        fromView.alpha = 1;
        [backdrop removeFromSuperview];
        [ctx completeTransition:completed];
    }];
}

@end
