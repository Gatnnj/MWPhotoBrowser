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

@property (nonatomic, weak, nullable) MWGridViewController *gridController;
@property (nonatomic) NSUInteger index;
@property (nonatomic, nullable) id <MWPhoto> photo;

/// 是否为当前正在大图查看的照片；用于在网格中柔和地标记这一格。
/// Whether this cell is the photo currently shown in the pager, used to softly mark it.
@property (nonatomic) BOOL isCurrentPhoto;

- (void)displayImage;

@end

NS_ASSUME_NONNULL_END
