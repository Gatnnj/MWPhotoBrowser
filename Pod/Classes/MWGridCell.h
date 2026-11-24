//
//  MWGridCell.h
//  MWPhotoBrowser
//
//  Created by Michael Waterfall on 08/10/2013.
//
//

#import <UIKit/UIKit.h>
#import "MWPhoto.h"
#import "MWGridViewController.h"

NS_ASSUME_NONNULL_BEGIN

@interface MWGridCell : UICollectionViewCell {}

/// 所属网格控制器（弱引用）
@property (nonatomic, weak, nullable) MWGridViewController *gridController;
/// 当前 cell 在网格中的索引
@property (nonatomic) NSUInteger index;
/// 当前展示的图片对象
@property (nonatomic, nullable) id <MWPhoto> photo;

/// 是否为当前正在大图查看的照片；用于在网格中柔和地标记这一格。
@property (nonatomic) BOOL isCurrentPhoto;

/// 用已就绪的缩略图刷新显示
- (void)displayImage;

@end

NS_ASSUME_NONNULL_END
