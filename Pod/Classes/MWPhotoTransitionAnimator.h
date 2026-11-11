//
//  MWPhotoTransitionAnimator.h
//  MWPhotoBrowser
//
//  自定义模态转场动画器：实现图片从缩略图位置“连贯放大”到全屏，
//  以及关闭时从全屏“飞回”缩略图位置；条件不满足时自动降级为渐隐。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 转场动画类型
typedef NS_ENUM(NSInteger, MWPhotoTransitionType) {
    /// 渐隐（无可用缩略图时的兜底方案）
    MWPhotoTransitionTypeFade,
    /// 连贯移动（图片在缩略图与全屏位置之间平滑移动）
    MWPhotoTransitionTypeCoherent
};

/**
 同时负责 present（入场）与 dismiss（出场）的动画器。
 通过 dismissing 属性区分方向，由 MWPhotoBrowser 在转场代理回调中创建并填充上下文。
 */
@interface MWPhotoTransitionAnimator : NSObject <UIViewControllerAnimatedTransitioning>

/// YES 表示出场（dismiss），NO 表示入场（present）
@property (nonatomic, assign, getter=isDismissing) BOOL dismissing;

/// 动画时长（入场/出场统一）
@property (nonatomic, assign) NSTimeInterval duration;

/// 入场时的起始缩略图视图（present 起点）
@property (nonatomic, weak, nullable) UIView *startView;

/// 出场时飞回的缩略图视图（dismiss 终点）
@property (nonatomic, weak, nullable) UIView *endView;

/// 出场时浏览器内当前显示的图片视图，用于取其当前实际位置（含拖拽 transform）
@property (nonatomic, weak, nullable) UIView *dismissingImageView;

/// 入场时用于连贯移动的图片（通常取 startView 上的 image）
@property (nonatomic, strong, nullable) UIImage *transitionImage;

@end

NS_ASSUME_NONNULL_END
