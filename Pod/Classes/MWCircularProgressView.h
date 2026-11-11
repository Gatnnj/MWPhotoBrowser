//
//  MWCircularProgressView.h
//  MWPhotoBrowser
//
//  内置的环形加载进度视图，用于替代第三方 DACircularProgressView。
//
//  实现要点：
//  - 使用 CAShapeLayer + strokeEnd 绘制，不参与 CPU 位图绘制，也不产生 backing store；
//  - 进度变化只修改 strokeEnd 一个图层属性，由 GPU 完成合成；
//  - 圆形路径只在尺寸或厚度变化时重建，避免每帧分配 UIBezierPath。
//
//  视觉与 DACircularProgressView 保持一致：轨道为白色 30% 透明，进度弧为白色，
//  从 12 点方向顺时针增长，端点平直（roundedCorners = NO）。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface MWCircularProgressView : UIView

/// 圆环轨道颜色，默认白色 30% 透明
@property (nonatomic, strong, nullable) UIColor *trackTintColor UI_APPEARANCE_SELECTOR;
/// 进度弧颜色，默认白色
@property (nonatomic, strong, nullable) UIColor *progressTintColor UI_APPEARANCE_SELECTOR;
/// 环的厚度与半径之比，默认 0.3
@property (nonatomic, assign) CGFloat thicknessRatio UI_APPEARANCE_SELECTOR;
/// 当前进度，取值 0 ~ 1
@property (nonatomic, assign) CGFloat progress;

@end

NS_ASSUME_NONNULL_END
