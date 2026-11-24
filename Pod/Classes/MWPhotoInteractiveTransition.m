#import "MWPhotoInteractiveTransition.h"

@interface MWPhotoInteractiveTransition () <UIGestureRecognizerDelegate>
@property (nonatomic, assign, readwrite) BOOL interacting;
@property (nonatomic, assign, readwrite, getter=isTransitionInProgress) BOOL transitionInProgress;
@property (nonatomic, copy) UIView * (^currentImageViewBlock)(void);
@property (nonatomic, copy) void (^setPagingEnabled)(BOOL enabled);
@property (nonatomic, copy) void (^setBackgroundAlpha)(CGFloat alpha);
@property (nonatomic, copy) UIView * (^dismissTargetBlock)(void);
@property (nonatomic, copy) void (^dismissBlock)(void);
@property (nonatomic, weak) UIView *sourceImageView;
@property (nonatomic, weak) UIView *dismissTargetView;
@property (nonatomic, weak) UIView *rootView;
@property (nonatomic, strong) UIView *dragSnapshot;
@property (nonatomic, weak) UIWindow *overlayWindow;
@property (nonatomic, assign) CGRect originalFrame;
@property (nonatomic, assign) CGPoint touchOffset;
@property (nonatomic, assign) BOOL originalHidden;
@property (nonatomic, assign) BOOL dismissTargetOriginalHidden;
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

/// 拖拽手势主处理：按阶段建快照、跟手缩放位移、松手判定回弹或关闭
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
            // 异步刚装上的图用 snapshotViewAfterScreenUpdates: 可能得到空白快照，
            // 故直接取 UIImage 建拖拽视图，与源视图的 backing layer 和复用生命周期解耦
            UIImage *displayedImage = [image isKindOfClass:[UIImageView class]] ? ((UIImageView *)image).image : nil;
            if (!displayedImage) break;
            UIImageView *imageSnapshot = [[UIImageView alloc] initWithImage:displayedImage];
            // 源视图被外层 scrollView 缩放，屏幕 frame 小于图片原尺寸；复用该 frame 并把位图填进去，
            // 用 Center 模式会按原像素绘制，拖拽时看起来放大裁切
            imageSnapshot.contentMode = UIViewContentModeScaleToFill;
            imageSnapshot.clipsToBounds = image.clipsToBounds;
            imageSnapshot.backgroundColor = UIColor.clearColor;
            self.dragSnapshot = imageSnapshot;
            self.dragSnapshot.frame = self.originalFrame;
            [window addSubview:self.dragSnapshot];
            image.hidden = YES;
            UIView *target = self.dismissTargetBlock ? self.dismissTargetBlock() : nil;
            self.dismissTargetView = target;
            self.dismissTargetOriginalHidden = target.hidden;
            target.hidden = YES;
            self.interacting = YES;
            self.transitionInProgress = YES;
            if (self.setPagingEnabled) self.setPagingEnabled(NO);
            // 清理上一次取消手势可能留下的层状态，确保首帧从完全不透明开始。
            if (self.setBackgroundAlpha) self.setBackgroundAlpha(1);
            break;
        }
        case UIGestureRecognizerStateChanged: {
            if (!self.interacting || !self.dragSnapshot) return;
            CGFloat height = MAX(root.bounds.size.height, 1);
            CGFloat verticalDistance = ABS(translation.y);
            CGFloat scale = MAX(0.42, 1.0 - verticalDistance / (height * 1.65));
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
            // 两个垂直方向都对称缩放与渐隐
            CGFloat progress = MIN(1, verticalDistance / (height * 0.5));
            CGFloat alpha = pow(1 - progress, 2.0);
            if (self.setBackgroundAlpha) self.setBackgroundAlpha(alpha);
            break;
        }
        case UIGestureRecognizerStateEnded: {
            if (!self.interacting) return;
            CGPoint velocity = [pan velocityInView:root];
            BOOL dismiss = ABS(translation.y) > root.bounds.size.height * self.dismissScale || ABS(velocity.y) > self.dismissVelocityY;
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

/// 未达关闭阈值：弹簧回弹到原位并恢复层状态
- (void)mw_restore {
    UIView *snapshot = self.dragSnapshot;
    if (!snapshot) return;
    self.interacting = NO;
    [UIView animateWithDuration:self.restoreDuration delay:0 usingSpringWithDamping:0.86 initialSpringVelocity:0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        snapshot.frame = self.originalFrame;
        if (self.setBackgroundAlpha) self.setBackgroundAlpha(1);
    } completion:^(BOOL finished) {
        self.sourceImageView.hidden = self.originalHidden;
        self.dismissTargetView.hidden = self.dismissTargetOriginalHidden;
        [snapshot removeFromSuperview];
        self.dragSnapshot = nil;
        self.dismissTargetView = nil;
        if (self.setPagingEnabled) self.setPagingEnabled(YES);
        self.transitionInProgress = NO;
        if (self.interactionDidRestore) self.interactionDidRestore();
    }];
}

/// 达到关闭阈值：快照飞到目标位、透明度归零后回调关闭
- (void)mw_finishDismiss {
    UIView *snapshot = self.dragSnapshot;
    UIWindow *window = self.overlayWindow;
    UIView *root = self.rootView;
    UIView *target = self.dismissTargetView ?: (self.dismissTargetBlock ? self.dismissTargetBlock() : nil);
    if (!snapshot || !window || !root) {
        target.hidden = self.dismissTargetOriginalHidden;
        self.dismissTargetView = nil;
        if (self.dismissBlock) self.dismissBlock();
        return;
    }
    self.interacting = NO;
    CGRect endFrame = target.window ? [target convertRect:target.bounds toView:window] : CGRectMake(CGRectGetMidX(window.bounds) - 12, CGRectGetMidY(window.bounds) - 12, 24, 24);
    [UIView animateWithDuration:0.24 delay:0 options:UIViewAnimationOptionCurveEaseInOut animations:^{
        snapshot.frame = endFrame;
        if (self.setBackgroundAlpha) self.setBackgroundAlpha(0);
    } completion:^(BOOL finished) {
        [snapshot removeFromSuperview];
        self.dragSnapshot = nil;
        // 快照落位的同帧恢复真实封面；dismissBlock 执行前浏览器仍盖住列表
        target.hidden = self.dismissTargetOriginalHidden;
        self.dismissTargetView = nil;
        if (self.dismissBlock) self.dismissBlock();
    }];
}

- (BOOL)gestureRecognizerShouldBegin:(UIPanGestureRecognizer *)gesture {
    UIView *image = self.currentImageViewBlock ? self.currentImageViewBlock() : nil;
    // 网络图还在加载时 UIImageView 已存在但无图，此时启动会拖一个黑色占位，
    // 故等真实图片就绪；且要求以纵向速度为主
    if (![image isKindOfClass:[UIImageView class]] || !image.window || !((UIImageView *)image).image) return NO;
    CGPoint velocity = [gesture velocityInView:gesture.view];
    return fabs(velocity.y) > fabs(velocity.x) * 1.15;
}

- (BOOL)gestureRecognizer:(UIGestureRecognizer *)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer *)otherGestureRecognizer { return YES; }

@end

