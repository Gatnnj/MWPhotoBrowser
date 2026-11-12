//
//  MWGridViewController.h
//  MWPhotoBrowser
//
//  Created by Michael Waterfall on 08/10/2013.
//
//

#import <UIKit/UIKit.h>
#import "MWPhotoBrowser.h"

NS_ASSUME_NONNULL_BEGIN

@interface MWGridViewController : UICollectionViewController {}

@property (nonatomic, assign, nullable) MWPhotoBrowser *browser;
@property (nonatomic) BOOL selectionMode;
@property (nonatomic) CGPoint initialContentOffset;

- (void)adjustOffsetsAsRequired;

@end

NS_ASSUME_NONNULL_END
