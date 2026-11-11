#import "MWPhotoInteractiveTransition.h"

@interface MWPhotoInteractiveTransition () <UIGestureRecognizerDelegate>
@property (nonatomic, assign, readwrite) BOOL interacting;
@property (nonatomic, copy) UIView * (^currentImageViewBlock)(void);
@property (nonatomic, copy) void (^setPagingEnabled)(BOOL enabled);
@property (nonatomic, copy) void (^setBackgroundAlpha)(CGFloat alpha);
@property (nonatomic, copy) UIView * (^dismissTargetBlock)(void);
@property (nonatomic, copy) void (^dismissBlock)(void);
@property (nonatomic, weak) UIView *sourceImageView;
@property (nonatomic, weak) UIView *rootView;
@property (nonatomic, strong) UIView *dragSnapshot;
@property (nonatomic, weak) UIWindow *overlayWindow;
@property (nonatomic, assign) CGRect originalFrame;
@property (nonatomic, assign) CGPoint touchOffset;
@property (nonatomic, assign) BOOL originalHidden;
@end

@implementation MWPhotoInteractiveTransition

- (instancetype)initWithCurrentImageViewBlock:(UIView * (^)(void))currentImageViewBlock
                            setPagingEnabled:(void (^)(BOOL))setPagingEnabled
                           setBackgroundAlpha:(void (^)(CGFloat))setBackgroundAlpha
                                 dismissBlock:(void (^)(void))dismissBlock {
    return [self initWithCurrentImageViewBlock:currentImageViewBlock setPagingEnabled:setPagingEnabled setBackgroundAlpha:setBackgroundAlpha dismissTargetBlock:nil dismissBlock:dismissBlock];
}

- (instancetype)initWithCurrentImageViewBlock:(UIView * (^)(void))currentImageViewBlock
                            setPagingEnabled:(void (^)(BOOL))setPagingEnabled
                           setBackgroundAlpha:(void (^)(CGFloat))setBackgroundAlpha
                           dismissTargetBlock:(UIView * (^)(void))dismissTargetBlock
                                 dismissBlock:(void (^)(void))dismissBlock {
    if ((self = [super init])) {
        _currentImageViewBlock = [currentImageViewBlock copy];
        _setPagingEnabled = [setPagingEnabled copy];
        _setBackgroundAlpha = [setBackgroundAlpha copy];
        _dismissTargetBlock = [dismissTargetBlock copy];
        _dismissBlock = [dismissBlock copy];
        _dismissScale = 0.22;
        _dismissVelocityY = 650;
        _restoreDuration = 0.28;
    }
    return self;
}

- (void)installGestureOnRootView:(UIView *)rootView {
    self.rootView = rootView;
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(mw_handlePan:)];
    pan.delegate = self;
    pan.maximumNumberOfTouches = 1;
    [rootView addGestureRecognizer:pan];
}

- (void)mw_handlePan:(UIPanGestureRecognizer *)pan {
    UIView *root = self.rootView;
    CGPoint translation = [pan translationInView:root];
    switch (pan.state) {
        case UIGestureRecognizerStateBegan: {
            UIView *image = self.currentImageViewBlock ? self.currentImageViewBlock() : nil;
            UIWindow *window = root.window;
            if (!image || !window || CGRectIsEmpty(image.bounds)) return;
            self.sourceImageView = image;
            self.overlayWindow = window;
            self.originalHidden = image.hidden;
            self.originalFrame = [image convertRect:image.bounds toView:window];
            CGPoint touchPoint = [pan locationInView:root];
            CGPoint imageCenter = [image convertPoint:CGPointMake(CGRectGetMidX(image.bounds), CGRectGetMidY(image.bounds)) toView:root];
            self.touchOffset = CGPointMake(touchPoint.x - imageCenter.x, touchPoint.y - imageCenter.y);
            // UIImageView.snapshotViewAfterScreenUpdates: can produce a blank
            // snapshot for an image that was just installed by an async loader
            // (network/blur completion). Build the drag view from the actual
            // UIImage instead, so the dragged content is independent of the
            // source view's backing layer and reuse lifecycle.
            UIImage *displayedImage = [image isKindOfClass:[UIImageView class]] ? ((UIImageView *)image).image : nil;
            if (!displayedImage) break;
            UIImageView *imageSnapshot = [[UIImageView alloc] initWithImage:displayedImage];
            // The source image view is zoomed by its enclosing UIScrollView,
            // so its screen-space frame is smaller than UIImage.size. Reuse
            // that converted frame as the snapshot's bounds and scale the
            // bitmap into it; UIViewContentModeCenter would draw at the raw
            // pixel size and look enlarged/cropped during the drag.
            imageSnapshot.contentMode = UIViewContentModeScaleToFill;
            imageSnapshot.clipsToBounds = image.clipsToBounds;
            imageSnapshot.backgroundColor = UIColor.clearColor;
            self.dragSnapshot = imageSnapshot;
            self.dragSnapshot.frame = self.originalFrame;
            [window addSubview:self.dragSnapshot];
            image.hidden = YES;
            self.interacting = YES;
            if (self.setPagingEnabled) self.setPagingEnabled(NO);
            // 清理上一次取消手势可能留下的层状态，确保首帧从完全不透明开始。
            if (self.setBackgroundAlpha) self.setBackgroundAlpha(1);
            break;
        }
        case UIGestureRecognizerStateChanged: {
            if (!self.interacting || !self.dragSnapshot) return;
            CGFloat height = MAX(root.bounds.size.height, 1);
            CGFloat downward = MAX(0, translation.y);
            CGFloat scale = MAX(0.42, 1.0 - downward / (height * 1.65));
            CGPoint current = [pan locationInView:root];
            CGPoint centerInWindow = [root convertPoint:current toView:self.overlayWindow];
            centerInWindow.x -= self.touchOffset.x * scale;
            centerInWindow.y -= self.touchOffset.y * scale;
            CGRect frame = self.originalFrame;
            frame.size.width *= scale;
            frame.size.height *= scale;
            frame.origin = CGPointMake(centerInWindow.x - frame.size.width * 0.5,
                                       centerInWindow.y - frame.size.height * 0.5);
            self.dragSnapshot.frame = frame;
            // 参考 YBImageBrowser：透明度从手势起点开始随下拉距离变化，
            // 轻微下拉即可看见底层；上拉时 downward 为 0，背景保持全黑。
            CGFloat progress = MIN(1, downward / (height * 0.5));
            CGFloat alpha = pow(1 - progress, 2.0);
            if (self.setBackgroundAlpha) self.setBackgroundAlpha(alpha);
            break;
        }
        case UIGestureRecognizerStateEnded: {
            if (!self.interacting) return;
            CGPoint velocity = [pan velocityInView:root];
            BOOL dismiss = translation.y > root.bounds.size.height * self.dismissScale || velocity.y > self.dismissVelocityY;
            if (dismiss) [self mw_finishDismiss];
            else [self mw_restore];
            break;
        }
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed:
            if (self.interacting) [self mw_restore];
            break;
        default: break;
    }
}

- (void)mw_restore {
    UIView *snapshot = self.dragSnapshot;
    if (!snapshot) return;
    self.interacting = NO;
    [UIView animateWithDuration:self.restoreDuration delay:0 usingSpringWithDamping:0.86 initialSpringVelocity:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        snapshot.frame = self.originalFrame;
        if (self.setBackgroundAlpha) self.setBackgroundAlpha(1);
    } completion:^(BOOL finished) {
        self.sourceImageView.hidden = self.originalHidden;
        [snapshot removeFromSuperview];
        self.dragSnapshot = nil;
        if (self.setPagingEnabled) self.setPagingEnabled(YES);
    }];
}

- (void)mw_finishDismiss {
    UIView *snapshot = self.dragSnapshot;
    UIWindow *window = self.overlayWindow;
    UIView *root = self.rootView;
    if (!snapshot || !window || !root) { if (self.dismissBlock) self.dismissBlock(); return; }
    UIView *target = self.dismissTargetBlock ? self.dismissTargetBlock() : nil;
    self.interacting = NO;
    CGRect endFrame = target.window ? [target convertRect:target.bounds toView:window] : CGRectMake(CGRectGetMidX(window.bounds) - 12, CGRectGetMidY(window.bounds) - 12, 24, 24);
    [UIView animateWithDuration:0.24 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        snapshot.frame = endFrame;
        if (self.setBackgroundAlpha) self.setBackgroundAlpha(0);
    } completion:^(BOOL finished) {
        [snapshot removeFromSuperview];
        self.dragSnapshot = nil;
        if (self.dismissBlock) self.dismissBlock();
    }];
}

- (BOOL)gestureRecognizerShouldBegin:(UIPanGestureRecognizer *)gesture {
    UIView *image = self.currentImageViewBlock ? self.currentImageViewBlock() : nil;
    // While a network photo is still loading the page's UIImageView exists but
    // has no image. Starting the interaction would hide that view and drag a
    // black placeholder, so wait until real image content is available.
    if (![image isKindOfClass:[UIImageView class]] || !image.window || !((UIImageView *)image).image) return NO;
    CGPoint velocity = [gesture velocityInView:gesture.view];
    return velocity.y > 0 && velocity.y > fabs(velocity.x) * 1.15;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer { return YES; }

@end

