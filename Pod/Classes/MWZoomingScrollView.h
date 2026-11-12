//
//  ZoomingScrollView.h
//  MWPhotoBrowser
//
//  Created by Michael Waterfall on 14/10/2010.
//  Copyright 2010 d3i. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MWPhotoProtocol.h"
#import "MWTapDetectingImageView.h"
#import "MWTapDetectingView.h"

@class MWPhotoBrowser, MWPhoto, MWCaptionView;

@interface MWZoomingScrollView : UIScrollView <UIScrollViewDelegate, MWTapDetectingImageViewDelegate, MWTapDetectingViewDelegate> {

}

@property () NSUInteger index;
@property (nonatomic) id <MWPhoto> photo;
@property (nonatomic, weak) MWCaptionView *captionView;
@property (nonatomic, weak) UIButton *selectedButton;

- (id)initWithPhotoBrowser:(MWPhotoBrowser *)browser;
- (void)displayImage;
- (void)displayImageFailure;
- (void)setMaxMinZoomScalesForCurrentBounds;
- (void)prepareForReuse;
- (void)setImageHidden:(BOOL)hidden;

// 暴露所属浏览器，供交互控制器复位时重算布局
- (MWPhotoBrowser *)photoBrowser;

// 暴露内部图片视图，供自定义转场获取其当前位置（含拖拽后的 transform）
- (UIView *)photoImageViewForTransition;

// 统一设置页面内部黑色背景的透明度（不影响图片本身），用于拖拽时背景渐隐
- (void)setBackgroundAlpha:(CGFloat)alpha;

@end
