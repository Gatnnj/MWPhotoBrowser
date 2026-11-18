//
//  MWWaterfallLayout.h
//  MWPhotoBrowser_Example
//
//  两列瀑布流布局：列宽由布局计算，高度由代理按图片比例返回。
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class MWWaterfallLayout;

@protocol MWWaterfallLayoutDelegate <NSObject>

/// item 宽度由布局决定，代理只负责返回高度
- (CGFloat)waterfallLayout:(MWWaterfallLayout *)layout
 heightForItemAtIndexPath:(NSIndexPath *)indexPath
                  itemWidth:(CGFloat)itemWidth;

@end

@interface MWWaterfallLayout : UICollectionViewLayout

/// 列数，默认 2
@property (nonatomic, assign) NSInteger numberOfColumns;
/// 列间距，默认 8
@property (nonatomic, assign) CGFloat minimumInteritemSpacing;
/// 行间距，默认 8
@property (nonatomic, assign) CGFloat minimumLineSpacing;
/// 段内边距，默认 12
@property (nonatomic, assign) UIEdgeInsets sectionInset;

@property (nonatomic, weak, nullable) id<MWWaterfallLayoutDelegate> waterfallDelegate;

@end

NS_ASSUME_NONNULL_END
