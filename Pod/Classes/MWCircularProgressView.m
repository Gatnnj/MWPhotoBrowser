//
//  MWCircularProgressView.m
//  MWPhotoBrowser
//
//  用 CAShapeLayer + strokeEnd 实现的环形进度视图，替代 DACircularProgressView。
//  几何与配色对齐 DACircularProgressView，保证替换后视觉一致。
//

#import "MWCircularProgressView.h"
#import "MWPhotoBrowser.h"

@interface MWCircularProgressView () <MWPhotoBrowserLoadingView> {
    CAShapeLayer *_trackShapeLayer;
    CAShapeLayer *_progressShapeLayer;
    // 路径缓存标记：仅在尺寸或厚度变化时重建 UIBezierPath
    CGSize _lastLayoutSize;
    CGFloat _lastLayoutThicknessRatio;
}
@end

@implementation MWCircularProgressView

#pragma mark - Lifecycle

- (instancetype)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {
        [self mw_commonInit];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if ((self = [super initWithCoder:coder])) {
        [self mw_commonInit];
    }
    return self;
}

- (void)mw_commonInit {
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;
    self.userInteractionEnabled = NO;

    _trackShapeLayer = [CAShapeLayer layer];
    _trackShapeLayer.fillColor = [UIColor clearColor].CGColor;
    _trackShapeLayer.lineCap = kCALineCapButt;
    _trackShapeLayer.strokeStart = 0.0f;
    _trackShapeLayer.strokeEnd = 1.0f;

    _progressShapeLayer = [CAShapeLayer layer];
    _progressShapeLayer.fillColor = [UIColor clearColor].CGColor;
    _progressShapeLayer.lineCap = kCALineCapButt;
    _progressShapeLayer.strokeStart = 0.0f;
    _progressShapeLayer.strokeEnd = 0.0f;

    [self.layer addSublayer:_trackShapeLayer];
    [self.layer addSublayer:_progressShapeLayer];

    // 与 DACircularProgressView 的默认值保持一致
    _thicknessRatio = 0.3f;
    _trackTintColor = [[UIColor whiteColor] colorWithAlphaComponent:0.3f];
    _progressTintColor = [UIColor whiteColor];
    _progress = 0.0f;

    _trackShapeLayer.strokeColor = _trackTintColor.CGColor;
    _progressShapeLayer.strokeColor = _progressTintColor.CGColor;

    _lastLayoutSize = CGSizeZero;
    _lastLayoutThicknessRatio = -1.0f;
}

#pragma mark - Layout

- (void)layoutSubviews {
    [super layoutSubviews];
    [self mw_updateShapeLayersIfNeeded];
}

- (void)mw_updateShapeLayersIfNeeded {
    CGSize size = self.bounds.size;
    if (size.width <= 0.0f || size.height <= 0.0f) {
        return;
    }
    // 尺寸与厚度都没变时直接返回，避免滚动过程中反复重建路径
    if (CGSizeEqualToSize(_lastLayoutSize, size) &&
        _lastLayoutThicknessRatio == _thicknessRatio) {
        return;
    }
    _lastLayoutSize = size;
    _lastLayoutThicknessRatio = _thicknessRatio;

    CGRect bounds = self.bounds;
    CGFloat radius = MIN(size.width, size.height) / 2.0f;
    // 与 DACircularProgressLayer 的几何关系一致：
    // 环外缘 = radius，内缘 = radius * (1 - thicknessRatio)，
    // 因此线宽 = radius * thicknessRatio，描边中心线半径 = radius - 线宽 / 2。
    CGFloat lineWidth = radius * _thicknessRatio;
    CGFloat strokeRadius = radius - lineWidth / 2.0f;
    if (strokeRadius <= 0.0f) {
        return;
    }

    CGPoint center = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
    UIBezierPath *path = [UIBezierPath bezierPathWithArcCenter:center
                                                        radius:strokeRadius
                                                    startAngle:(CGFloat)(-M_PI_2)
                                                      endAngle:(CGFloat)(3.0f * M_PI_2)
                                                     clockwise:YES];
    CGPathRef pathRef = path.CGPath;

    _trackShapeLayer.frame = bounds;
    _trackShapeLayer.path = pathRef;
    _trackShapeLayer.lineWidth = lineWidth;

    _progressShapeLayer.frame = bounds;
    _progressShapeLayer.path = pathRef;
    _progressShapeLayer.lineWidth = lineWidth;
}

#pragma mark - Properties

- (void)setProgress:(CGFloat)progress {
    CGFloat pinnedProgress = MIN(MAX(progress, 0.0f), 1.0f);
    _progress = pinnedProgress;
    // 关闭隐式动画：进度回调可能非常频繁，隐式动画会为每次赋值新建 CAAnimation
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _progressShapeLayer.strokeEnd = pinnedProgress;
    [CATransaction commit];
}

- (void)setThicknessRatio:(CGFloat)thicknessRatio {
    _thicknessRatio = MIN(MAX(thicknessRatio, 0.0f), 1.0f);
    [self setNeedsLayout];
}

- (void)setTrackTintColor:(UIColor *)trackTintColor {
    _trackTintColor = trackTintColor;
    _trackShapeLayer.strokeColor = trackTintColor.CGColor;
}

- (void)setProgressTintColor:(UIColor *)progressTintColor {
    _progressTintColor = progressTintColor;
    _progressShapeLayer.strokeColor = progressTintColor.CGColor;
}

@end
