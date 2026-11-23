//
//  MWWaterfallLayout.m
//  MWPhotoBrowser_Example
//

#import "MWWaterfallLayout.h"

@interface MWWaterfallLayout ()

@property (nonatomic, strong) NSMutableDictionary<NSIndexPath *, UICollectionViewLayoutAttributes *> *itemAttributes;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *columnHeights;
@property (nonatomic, assign) CGFloat contentHeight;

@end

@implementation MWWaterfallLayout

- (instancetype)init {
    if (self = [super init]) {
        _numberOfColumns = 2;
        _minimumInteritemSpacing = 8.0;
        _minimumLineSpacing = 8.0;
        _sectionInset = UIEdgeInsetsMake(12.0, 12.0, 12.0, 12.0);
    }
    return self;
}

#pragma mark - Lazy

- (NSMutableDictionary<NSIndexPath *, UICollectionViewLayoutAttributes *> *)itemAttributes {
    if (!_itemAttributes) {
        _itemAttributes = [NSMutableDictionary dictionary];
    }
    return _itemAttributes;
}

- (NSMutableArray<NSNumber *> *)columnHeights {
    if (!_columnHeights) {
        _columnHeights = [NSMutableArray array];
    }
    return _columnHeights;
}

#pragma mark - Setters（参数变化时重新排版）

- (void)setNumberOfColumns:(NSInteger)numberOfColumns {
    _numberOfColumns = MAX(1, numberOfColumns);
    [self invalidateLayout];
}

- (void)setMinimumInteritemSpacing:(CGFloat)minimumInteritemSpacing {
    _minimumInteritemSpacing = minimumInteritemSpacing;
    [self invalidateLayout];
}

- (void)setMinimumLineSpacing:(CGFloat)minimumLineSpacing {
    _minimumLineSpacing = minimumLineSpacing;
    [self invalidateLayout];
}

- (void)setSectionInset:(UIEdgeInsets)sectionInset {
    _sectionInset = sectionInset;
    [self invalidateLayout];
}

#pragma mark - Layout

- (void)prepareLayout {
    [super prepareLayout];

    [self.itemAttributes removeAllObjects];
    [self.columnHeights removeAllObjects];
    self.contentHeight = 0.0;

    UICollectionView *collectionView = self.collectionView;
    if (!collectionView) {
        return;
    }

    NSInteger columnCount = MAX(1, self.numberOfColumns);
    CGFloat itemWidth = [self itemWidthForColumnCount:columnCount];
    if (itemWidth <= 0.0) {
        return;
    }

    CGFloat sectionTop = 0.0;
    NSInteger sectionCount = [collectionView numberOfSections];

    for (NSInteger section = 0; section < sectionCount; section++) {
        [self.columnHeights removeAllObjects];

        NSMutableArray<NSNumber *> *columnItemCounts = [NSMutableArray array];
        for (NSInteger column = 0; column < columnCount; column++) {
            [self.columnHeights addObject:@(sectionTop + self.sectionInset.top)];
            [columnItemCounts addObject:@(0)];
        }

        NSInteger itemCount = [collectionView numberOfItemsInSection:section];
        for (NSInteger item = 0; item < itemCount; item++) {
            NSIndexPath *indexPath = [NSIndexPath indexPathForItem:item inSection:section];

            CGFloat itemHeight = [self heightForItemAtIndexPath:indexPath itemWidth:itemWidth];
            itemHeight = MAX(ceil(itemHeight), 1.0);

            // 选当前最矮的一列；相等时取左侧，保证排布稳定
            NSInteger shortestColumn = 0;
            CGFloat shortestBottom = CGFLOAT_MAX;
            for (NSInteger column = 0; column < columnCount; column++) {
                CGFloat bottom = self.columnHeights[column].doubleValue;
                if (bottom < shortestBottom) {
                    shortestBottom = bottom;
                    shortestColumn = column;
                }
            }

            NSInteger placedCount = columnItemCounts[shortestColumn].integerValue;
            CGFloat y = shortestBottom + (placedCount > 0 ? self.minimumLineSpacing : 0.0);
            CGFloat x = self.sectionInset.left + shortestColumn * (itemWidth + self.minimumInteritemSpacing);

            UICollectionViewLayoutAttributes *attributes =
                [UICollectionViewLayoutAttributes layoutAttributesForCellWithIndexPath:indexPath];
            attributes.frame = CGRectMake(x, y, itemWidth, itemHeight);

            self.itemAttributes[indexPath] = attributes;
            self.columnHeights[shortestColumn] = @(CGRectGetMaxY(attributes.frame));
            columnItemCounts[shortestColumn] = @(placedCount + 1);
        }

        CGFloat maxColumnBottom = sectionTop + self.sectionInset.top;
        for (NSNumber *bottom in self.columnHeights) {
            maxColumnBottom = MAX(maxColumnBottom, bottom.doubleValue);
        }
        sectionTop = maxColumnBottom + self.sectionInset.bottom;
        self.contentHeight = sectionTop;
    }
}

- (NSArray<UICollectionViewLayoutAttributes *> *)layoutAttributesForElementsInRect:(CGRect)rect {
    NSMutableArray<UICollectionViewLayoutAttributes *> *result = [NSMutableArray array];
    for (UICollectionViewLayoutAttributes *attributes in self.itemAttributes.allValues) {
        if (CGRectIntersectsRect(attributes.frame, rect)) {
            [result addObject:attributes];
        }
    }
    return result;
}

- (UICollectionViewLayoutAttributes *)layoutAttributesForItemAtIndexPath:(NSIndexPath *)indexPath {
    return self.itemAttributes[indexPath];
}

- (CGSize)collectionViewContentSize {
    CGFloat width = CGRectGetWidth(self.collectionView.bounds);
    return CGSizeMake(width, MAX(self.contentHeight, 0.0));
}

- (BOOL)shouldInvalidateLayoutForBoundsChange:(CGRect)newBounds {
    return !CGSizeEqualToSize(newBounds.size, self.collectionView.bounds.size);
}

#pragma mark - Private

- (CGFloat)itemWidthForColumnCount:(NSInteger)columnCount {
    CGFloat totalWidth = CGRectGetWidth(self.collectionView.bounds) - self.sectionInset.left - self.sectionInset.right;
    if (totalWidth <= 0.0) {
        return 0.0;
    }
    CGFloat itemWidth = (totalWidth - self.minimumInteritemSpacing * (columnCount - 1)) / columnCount;
    return floor(itemWidth);
}

- (CGFloat)heightForItemAtIndexPath:(NSIndexPath *)indexPath itemWidth:(CGFloat)itemWidth {
    if ([self.waterfallDelegate respondsToSelector:@selector(waterfallLayout:heightForItemAtIndexPath:itemWidth:)]) {
        return [self.waterfallDelegate waterfallLayout:self heightForItemAtIndexPath:indexPath itemWidth:itemWidth];
    }
    return itemWidth * 0.75; // 兜底 4:3
}

@end
