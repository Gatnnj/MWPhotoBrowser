#import "MWPhotoTransitionAnimator.h"

@interface MWPhotoTransitionAnimator ()
@property (nonatomic, weak) UIView *hiddenSourceView;
@end

@implementation MWPhotoTransitionAnimator

- (instancetype)init {
    if ((self = [super init])) _duration = 0.32;
    return self;
}

- (NSTimeInterval)transitionDuration:(id<UIViewControllerContextTransitioning>)transitionContext { return self.duration; }

- (void)animateTransition:(id<UIViewControllerContextTransitioning>)ctx {
    if (self.isDismissing) [self mw_dismiss:ctx];
    else [self mw_present:ctx];
}

- (UIImageView *)mw_imageViewWithImage:(UIImage *)image from:(UIView *)reference {
    UIImageView *view = [[UIImageView alloc] initWithImage:image];
    view.contentMode = UIViewContentModeScaleAspectFill;
    view.clipsToBounds = YES;
    if (reference) {
        view.layer.cornerRadius = reference.layer.cornerRadius;
        view.layer.masksToBounds = YES;
    }
    return view;
}

- (BOOL)mw_validSourceIn:(UIView *)container {
    return self.startView && self.startView.window && self.transitionImage && self.transitionImage.size.width > 0 && self.transitionImage.size.height > 0 && container.bounds.size.width > 0;
}

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
    CGRect end = CGRectMake((CGRectGetWidth(container.bounds) - self.transitionImage.size.width * MIN(CGRectGetWidth(container.bounds) / self.transitionImage.size.width, CGRectGetHeight(container.bounds) / self.transitionImage.size.height)) * 0.5,
                            (CGRectGetHeight(container.bounds) - self.transitionImage.size.height * MIN(CGRectGetWidth(container.bounds) / self.transitionImage.size.width, CGRectGetHeight(container.bounds) / self.transitionImage.size.height)) * 0.5,
                            self.transitionImage.size.width * MIN(CGRectGetWidth(container.bounds) / self.transitionImage.size.width, CGRectGetHeight(container.bounds) / self.transitionImage.size.height),
                            self.transitionImage.size.height * MIN(CGRectGetWidth(container.bounds) / self.transitionImage.size.width, CGRectGetHeight(container.bounds) / self.transitionImage.size.height));
    UIImageView *moving = [self mw_imageViewWithImage:self.transitionImage from:self.startView];
    moving.frame = start;
    [container addSubview:moving];
    self.hiddenSourceView = self.startView;
    self.startView.hidden = YES;
    toView.alpha = 0;
    [UIView animateWithDuration:self.duration delay:0 usingSpringWithDamping:0.9 initialSpringVelocity:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        moving.frame = end;
        toView.alpha = 1;
    } completion:^(BOOL finished) {
        BOOL completed = !ctx.transitionWasCancelled;
        [moving removeFromSuperview];
        self.hiddenSourceView.hidden = NO;
        toView.alpha = 1;
        if (!completed) [toView removeFromSuperview];
        [ctx completeTransition:completed];
    }];
}

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
            fromView.alpha = 1;
            [ctx completeTransition:completed];
        }];
        return;
    }

    CGRect start = [source convertRect:source.bounds toView:container];
    CGRect end = [target convertRect:target.bounds toView:container];
    UIImageView *moving = [self mw_imageViewWithImage:((UIImageView *)source).image from:target];
    moving.contentMode = UIViewContentModeScaleAspectFit;
    moving.frame = start;
    [container addSubview:moving];
    fromView.alpha = 1;
    source.hidden = YES;
    target.hidden = YES;
    [UIView animateWithDuration:self.duration delay:0 usingSpringWithDamping:0.92 initialSpringVelocity:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        moving.frame = end;
        fromView.alpha = 0;
    } completion:^(BOOL finished) {
        BOOL completed = !ctx.transitionWasCancelled;
        [moving removeFromSuperview];
        source.hidden = NO;
        target.hidden = NO;
        fromView.alpha = 1;
        [ctx completeTransition:completed];
    }];
}

@end
