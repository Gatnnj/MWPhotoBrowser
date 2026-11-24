//
//  UIViewTap.h
//  Momento
//
//  Created by Michael Waterfall on 04/11/2009.
//  Copyright 2009 d3i. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol MWTapDetectingViewDelegate;

@interface MWTapDetectingView : UIView {}

/// 手势识别代理（弱引用）
@property (nonatomic, weak, nullable) id <MWTapDetectingViewDelegate> tapDelegate;

@end

@protocol MWTapDetectingViewDelegate <NSObject>

@optional

/// 识别到单击
- (void)view:(UIView *)view singleTapDetected:(UITouch *)touch;
/// 识别到双击
- (void)view:(UIView *)view doubleTapDetected:(UITouch *)touch;
/// 识别到三击
- (void)view:(UIView *)view tripleTapDetected:(UITouch *)touch;

@end

NS_ASSUME_NONNULL_END