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
@property (nonatomic) BOOL selectionMode;
@property (nonatomic) BOOL isSelected;

- (void)displayImage;

@end

NS_ASSUME_NONNULL_END
