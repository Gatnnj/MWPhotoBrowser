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

@class MWPhotoBrowser, MWPhoto;

NS_ASSUME_NONNULL_BEGIN

@interface MWZoomingScrollView : UIScrollView <UIScrollViewDelegate, MWTapDetectingImageViewDelegate, MWTapDetectingViewDelegate>

/// 当前页索引
@property () NSUInteger index;
/// 当前展示的图片对象
@property (nonatomic, nullable) id <MWPhoto> photo;

/// 绑定所属浏览器初始化
- (instancetype)initWithPhotoBrowser:(MWPhotoBrowser *)browser;
/// 刷新并显示当前图片
- (void)displayImage;
/// 显示加载失败占位图
- (void)displayImageFailure;
/// 按当前 bounds 计算最大/最小缩放比例
- (void)setMaxMinZoomScalesForCurrentBounds;
/// 复用时清理状态
- (void)prepareForReuse;
/// 隐藏或显示图片视图（转场过渡用）
- (void)setImageHidden:(BOOL)hidden;

/// 重新绑定刷新后的图片数据，同时保留当前已可见的图片。
- (void)reloadPhotoKeepingDisplayedImage:(nullable id<MWPhoto>)photo;

// 暴露所属浏览器，供交互控制器复位时重算布局
- (nullable MWPhotoBrowser *)photoBrowser;

// 暴露内部图片视图，供自定义转场获取其当前位置（含拖拽后的 transform）
- (nullable UIView *)photoImageViewForTransition;

// 统一设置页面内部黑色背景的透明度（不影响图片本身），用于拖拽时背景渐隐
- (void)setBackgroundAlpha:(CGFloat)alpha;

@end

NS_ASSUME_NONNULL_END
