//
//  UIImageViewTap.h
//  Momento
//
//  Created by Michael Waterfall on 04/11/2009.
//  Copyright 2009 d3i. All rights reserved.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@protocol MWTapDetectingImageViewDelegate;

@interface MWTapDetectingImageView : UIImageView {}

/// 手势识别代理（弱引用）
@property (nonatomic, weak, nullable) id <MWTapDetectingImageViewDelegate> tapDelegate;

@end

@protocol MWTapDetectingImageViewDelegate <NSObject>

@optional

/// 识别到单击
- (void)imageView:(UIImageView *)imageView singleTapDetected:(UITouch *)touch;
/// 识别到双击
- (void)imageView:(UIImageView *)imageView doubleTapDetected:(UITouch *)touch;
/// 识别到三击
- (void)imageView:(UIImageView *)imageView tripleTapDetected:(UITouch *)touch;

@end

NS_ASSUME_NONNULL_END