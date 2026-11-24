//
//  MWPhotoProtocol.h
//  MWPhotoBrowser
//
//  Created by Michael Waterfall on 02/01/2012.
//  Copyright (c) 2012 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

@class UIImage;

// 图片加载完成通知：图片就绪或加载失败后发送，object 为自身
#define MWPHOTO_LOADING_DID_END_NOTIFICATION @"MWPHOTO_LOADING_DID_END_NOTIFICATION"
// 图片加载进度通知：上报 0~1 的加载进度
#define MWPHOTO_PROGRESS_NOTIFICATION @"MWPHOTO_PROGRESS_NOTIFICATION"

// 自定义图片模型需遵守本协议；也可直接使用 MWPhoto 或其子类。
// 参考 MWPhoto 的实现作为示例。
NS_ASSUME_NONNULL_BEGIN

@protocol MWPhoto <NSObject>

@required

/// 当前已就绪、可直接显示的 UIImage；未加载完成时返回 nil。
/// 注意：不要在此方法里主动发起网络/文件加载，加载由 -loadUnderlyingImageAndNotify 触发。
@property (nonatomic, strong, nullable) UIImage *underlyingImage;

/// 浏览器发现图片未在内存时调用，准备进入异步加载流程
- (void)loadUnderlyingImageAndNotify;

/// 真正从数据源（缓存/文件/网络）异步取图并解压；
/// 加载完成或失败后发送 MWPHOTO_LOADING_DID_END_NOTIFICATION 通知。
- (void)performLoadUnderlyingImageAndNotify;

/// 浏览器判定图片不再需要或内存紧张时调用，释放已解压的大图数据（可从缓存/文件/URL 重新加载）
- (void)unloadUnderlyingImage;

@optional

/// 是否对图片做高斯模糊
@property (nonatomic) BOOL isBlur;
/// 网格缩略图：可用时由网格视图直接取用
@property (nonatomic, readonly, nullable) UIImage *gridThumbnailImage;
/// 按指定像素尺寸从同一来源加载网格缩略图，不保留完整解码大图
- (void)loadGridThumbnailAndNotifyWithPixelSize:(CGSize)pixelSize;
/// cell 离开可见范围时释放内存中的网格缩略图
- (void)releaseGridThumbnailFromMemory;
/// 高斯模糊半径，默认 30.0
@property (nonatomic) CGFloat radius;

/// 空图片标记：为 YES 时不显示加载失败图标
@property (nonatomic) BOOL emptyImage;

/// 取消所有后台图片加载
- (void)cancelAnyLoading;

@end

NS_ASSUME_NONNULL_END
