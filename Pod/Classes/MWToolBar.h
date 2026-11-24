//
//  MWToolBar.h
//  MWPhotoBrowser
//
//  Created by 19m on 2026/11/12.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// 工具栏位置
typedef NS_ENUM(NSInteger, MWToolBarPosition) {
    /// 左侧，按钮纵向堆叠
    MWToolBarPositionLeft,
    /// 底部（默认），按钮横向排列
    MWToolBarPositionBottom,
    /// 右侧，按钮纵向堆叠
    MWToolBarPositionRight,
};

@interface MWToolBar : UIView

/// 工具栏位置，默认底部；左右两侧的按钮纵向堆叠
@property (nonatomic) MWToolBarPosition position;
/// 设置后优先于自动计算的 frame
@property (nonatomic, strong, nullable) NSValue *customFrame;

/// 添加工具栏按钮
- (void)addItems:(nullable NSArray<UIButton *> *)array;

/// 按容器 bounds 与底部安全区计算 frame
- (CGRect)frameForContainerBounds:(CGRect)bounds safeAreaInsets:(UIEdgeInsets)safeAreaInsets;

@end

NS_ASSUME_NONNULL_END
