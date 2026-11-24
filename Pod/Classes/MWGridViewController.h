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

/// 所属浏览器（弱引用）
@property (nonatomic, assign, nullable) MWPhotoBrowser *browser;

/// 由浏览器在网格挂载后调用一次，把当前大图对应的格子居中显示。
- (void)adjustOffsetsAsRequired;

@end

NS_ASSUME_NONNULL_END
