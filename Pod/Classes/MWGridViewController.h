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

/// 由浏览器在网格挂载后调用一次，把当前大图对应的格子居中显示。
/// Called once by the browser after the grid is attached, centering the current photo.
- (void)adjustOffsetsAsRequired;

@end

NS_ASSUME_NONNULL_END
