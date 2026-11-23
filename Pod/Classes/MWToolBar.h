//
//  MWToolBar.h
//  MWPhotoBrowser
//
//  Created by 19m on 2026/11/12.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, MWToolBarPosition) {
    MWToolBarPositionLeft,
    MWToolBarPositionBottom,
    MWToolBarPositionRight,
};

@interface MWToolBar : UIView

/// Defaults to bottom. Left and right toolbars stack 50-point items vertically.
@property (nonatomic) MWToolBarPosition position;
/// When set, this frame takes precedence over the calculated position frame.
@property (nonatomic, strong, nullable) NSValue *customFrame;

- (void)addItems:(nullable NSArray<UIButton *> *)array;

/// Calculates a frame using the container bounds and its bottom safe-area inset.
- (CGRect)frameForContainerBounds:(CGRect)bounds safeAreaInsets:(UIEdgeInsets)safeAreaInsets;

@end

NS_ASSUME_NONNULL_END
