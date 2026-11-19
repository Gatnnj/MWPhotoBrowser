#import "MWPhotoTransitionAnimator.h"

@interface MWPhotoTransitionAnimator ()
@property (nonatomic, weak) UIView *hiddenSourceView;
@property (nonatomic, weak) UIView *hiddenDestinationView;
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
    UIView *destination = self.destinationImageView;
    CGRect end;
    if (destination.window && !CGRectIsEmpty(destination.bounds)) {
        // Match the actual image view after MWPhotoBrowser has applied its
        // paging, safe-area and zoom layout, as Lantern does for its visible cell.
        end = [destination convertRect:destination.bounds toView:container];
    } else {
        CGFloat scale = MIN(CGRectGetWidth(container.bounds) / self.transitionImage.size.width,
                            CGRectGetHeight(container.bounds) / self.transitionImage.size.height);
        CGSize size = CGSizeMake(self.transitionImage.size.width * scale,
                                 self.transitionImage.size.height * scale);
        end = CGRectMake(CGRectGetMidX(container.bounds) - size.width * 0.5,
                         CGRectGetMidY(container.bounds) - size.height * 0.5,
                         size.width,
                         size.height);
    }
    UIImageView *moving = [self mw_imageViewWithImage:self.transitionImage from:self.startView];
    moving.frame = start;
    [container addSubview:moving];
    self.hiddenSourceView = self.startView;
    self.startView.hidden = YES;
    self.hiddenDestinationView = destination;
    destination.hidden = YES;
    toView.alpha = 0;
    [UIView animateWithDuration:self.duration delay:0 usingSpringWithDamping:0.9 initialSpringVelocity:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        moving.frame = end;
        toView.alpha = 1;
    } completion:^(BOOL finished) {
        BOOL completed = !ctx.transitionWasCancelled;
        [moving removeFromSuperview];
        self.hiddenSourceView.hidden = NO;
        self.hiddenDestinationView.hidden = NO;
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
            target.hidden = NO;
            fromView.alpha = 1;
            [ctx completeTransition:completed];
        }];
        return;
    }

    CGRect start = [source convertRect:source.bounds toView:container];
    CGRect end = [target convertRect:target.bounds toView:container];
    UIImageView *moving = [self mw_imageViewWithImage:((UIImageView *)source).image from:target];
    // The source photo view uses .center and is enlarged by its scroll view's
    // zoom transform. The transition view has a frame in screen coordinates,
    // so copying .center would draw the bitmap at its unscaled pixel size.
    // Fill the target thumbnail's actual bounds during the closing flight.
    // A mismatched portrait photo may be cropped, but it reaches the cover's
    // real displayed size instead of shrinking with empty side margins.
    moving.contentMode = UIViewContentModeScaleAspectFill;
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
