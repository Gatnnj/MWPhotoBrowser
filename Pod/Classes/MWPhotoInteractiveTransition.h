//
//  MWPhotoInteractiveTransition.h
//  MWPhotoBrowser
//
//  拖拽关闭交互控制器（对照 JXPhotoBrowser 实现）：
//  手势加在浏览器根视图，变换对象是内部图片视图，而非整个滚动页。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class MWZoomingScrollView;

@interface MWPhotoInteractiveTransition : NSObject

/// 是否正在交互（供外部读取）
@property (nonatomic, assign, readonly) BOOL interacting;

/// 关闭判定阈值（可微调）
@property (nonatomic, assign) CGFloat dismissScale;
@property (nonatomic, assign) CGFloat dismissVelocityY;
@property (nonatomic, assign) NSTimeInterval restoreDuration;

/// 初始化：注入当前图片视图、分页开关控制、背景透明度控制与关闭回调
/// @param currentImageViewBlock 返回当前页内部图片视图
/// @param setPagingEnabled 控制分页 scrollView 是否可滚动
/// @param setBackgroundAlpha 控制背景透明度
/// @param dismissBlock 松手判定关闭时回调
- (instancetype)initWithCurrentImageViewBlock:(UIView * _Nullable (^)(void))currentImageViewBlock
                            setPagingEnabled:(void (^)(BOOL enabled))setPagingEnabled
                           setBackgroundAlpha:(void (^)(CGFloat alpha))setBackgroundAlpha
                           dismissTargetBlock:(nullable UIView * _Nullable (^)(void))dismissTargetBlock
                                 dismissBlock:(void (^)(void))dismissBlock;

/// 兼容旧初始化接口
- (instancetype)initWithCurrentImageViewBlock:(UIView * _Nullable (^)(void))currentImageViewBlock
                            setPagingEnabled:(void (^)(BOOL enabled))setPagingEnabled
                           setBackgroundAlpha:(void (^)(CGFloat alpha))setBackgroundAlpha
                                 dismissBlock:(void (^)(void))dismissBlock;

/// 在浏览器根视图上安装拖拽手势
- (void)installGestureOnRootView:(UIView *)rootView;

@end

NS_ASSUME_NONNULL_END
