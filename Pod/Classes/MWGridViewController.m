//
//  MWGridViewController.m
//  MWPhotoBrowser
//
//  Created by Michael Waterfall on 08/10/2013.
//
//

#import "MWGridViewController.h"
#import "MWGridCell.h"
#import "MWPhotoBrowserPrivate.h"

@interface MWGridViewController () {
    
    // 记录当前布局的边距与列数
    CGFloat _margin, _gutter, _marginL, _gutterL, _columns, _columnsL;

    // 本网格实例是否已应用过初始定位，防止重复居中
    BOOL _didApplyInitialPosition;
    
}

@end

@implementation MWGridViewController

- (instancetype)init {
    if ((self = [super initWithCollectionViewLayout:[UICollectionViewFlowLayout new]])) {
        
        // 默认列数与边距
        _columns = 3; _columnsL = 4;
        _margin = 0; _gutter = 1;
        _marginL = 0; _gutterL = 1;

        if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
            // iPad
            _columns = 6; _columnsL = 8;
            _margin = 1; _gutter = 2;
            _marginL = 1; _gutterL = 2;
        } else {
            // iPhone 4 寸及以上。iOS 13 起所有支持机型的短边均 >= 568pt，
            // 原 480pt（3.5 寸）分支已不可达，故统一按此配置。
            _columns = 3; _columnsL = 5;
            _margin = 0; _gutter = 1;
            _marginL = 0; _gutterL = 2;
        }
    }
    return self;
}

#pragma mark - View

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.collectionView registerClass:[MWGridCell class] forCellWithReuseIdentifier:@"GridCell"];
    self.collectionView.alwaysBounceVertical = YES;
    if (@available(iOS 26.0, *)) {
        self.collectionView.topEdgeEffect.hidden = YES;
    }
    self.collectionView.backgroundColor = [UIColor blackColor];
}

- (void)viewWillDisappear:(BOOL)animated {
    // 释放可见 cell 的内存缩略图；磁盘缓存保留，再次打开仍可用
    NSArray *visibleCells = [self.collectionView visibleCells];
    if (visibleCells) {
        for (MWGridCell *cell in visibleCells) {
            if ([cell.photo respondsToSelector:@selector(releaseGridThumbnailFromMemory)]) {
                [cell.photo releaseGridThumbnailFromMemory];
            }
        }
    }
    [super viewWillDisappear:animated];
}

- (void)adjustOffsetsAsRequired {
    // 每个网格实例只定位一次：布局回调可能多次触发，重复居中会把用户手动滚动的位置拽回去。
    if (_didApplyInitialPosition) return;
    if (_browser.numberOfPhotos == 0) return;
    _didApplyInitialPosition = YES;

    if (_browser.currentIndex >= _browser.numberOfPhotos) return;

    // 把当前大图对应的格子居中显示。CenteredVertically 会把偏移量夹到合法区间，
    // 所以当前照片位于首行、或内容不足一屏时，结果自然停在顶部，不会出现上方留白。
    NSIndexPath *currentPhotoIndexPath = [NSIndexPath indexPathForItem:_browser.currentIndex inSection:0];
    [self.collectionView scrollToItemAtIndexPath:currentPhotoIndexPath
                               atScrollPosition:UICollectionViewScrollPositionCenteredVertically
                                       animated:NO];
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id <UIViewControllerTransitionCoordinator>)coordinator {
    [self.collectionView reloadData];
}

#pragma mark - Layout

/// 当前是否为竖屏，替代已废弃的 self.interfaceOrientation（iOS 8 废弃）
- (BOOL)mw_isPortrait {
    // 优先从 windowScene 获取当前方向（iOS 13+）
    UIWindowScene *windowScene = self.view.window.windowScene;
    if (windowScene) {
        return UIInterfaceOrientationIsPortrait(windowScene.interfaceOrientation);
    }
    // 视图尚未挂到 window 时按 bounds 尺寸兜底
    return self.view.bounds.size.height >= self.view.bounds.size.width;
}

- (CGFloat)getColumns {
    if ([self mw_isPortrait]) {
        return _columns;
    } else {
        return _columnsL;
    }
}

- (CGFloat)getMargin {
    if ([self mw_isPortrait]) {
        return _margin;
    } else {
        return _marginL;
    }
}

- (CGFloat)getGutter {
    if ([self mw_isPortrait]) {
        return _gutter;
    } else {
        return _gutterL;
    }
}

#pragma mark - Collection View

- (NSInteger)collectionView:(UICollectionView *)view numberOfItemsInSection:(NSInteger)section {
    return [_browser numberOfPhotos];
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    MWGridCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"GridCell" forIndexPath:indexPath];
    if (!cell) {
        cell = [[MWGridCell alloc] init];
    }
    id <MWPhoto> photo = [_browser thumbPhotoAtIndex:indexPath.row];
    cell.gridController = self;
    cell.photo = photo;
    cell.index = indexPath.row;
    // 标记当前大图对应的那一格，打开网格时用户一眼能看到自己正在看哪张。
    cell.isCurrentPhoto = (indexPath.row == _browser.currentIndex);
    if ([photo respondsToSelector:@selector(loadGridThumbnailAndNotifyWithPixelSize:)]) {
        UIImage *thumbnail = [photo respondsToSelector:@selector(gridThumbnailImage)] ? photo.gridThumbnailImage : nil;
        if (thumbnail) {
            [cell displayImage];
        } else {
            CGFloat scale = UIScreen.mainScreen.scale;
            CGSize cellSize = cell.bounds.size;
            if (cellSize.width <= 0 || cellSize.height <= 0) {
                cellSize = [self collectionView:self.collectionView
                                         layout:self.collectionView.collectionViewLayout
                         sizeForItemAtIndexPath:indexPath];
            }
            CGSize pixelSize = CGSizeMake(MAX(1, cellSize.width * scale),
                                          MAX(1, cellSize.height * scale));
            [photo loadGridThumbnailAndNotifyWithPixelSize:pixelSize];
        }
    } else {
        UIImage *img = [_browser imageForPhoto:photo];
        if (img) [cell displayImage];
        else [photo loadUnderlyingImageAndNotify];
    }
    return cell;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    // 记录"曾经从网格中点选过照片"：只置 YES，永不复位。
    _browser.hasPickedFromGrid = YES;
    [_browser setCurrentPhotoIndex:indexPath.row];
    [_browser hideGrid];
}

- (void)collectionView:(UICollectionView *)collectionView didEndDisplayingCell:(UICollectionViewCell *)cell forItemAtIndexPath:(NSIndexPath *)indexPath {
    id<MWPhoto> photo = ((MWGridCell *)cell).photo;
    if ([photo respondsToSelector:@selector(releaseGridThumbnailFromMemory)]) {
        [photo releaseGridThumbnailFromMemory];
    }
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout*)collectionViewLayout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    CGFloat margin = [self getMargin];
    CGFloat gutter = [self getGutter];
    CGFloat columns = [self getColumns];
    CGFloat value = floorf(((self.view.bounds.size.width - (columns - 1) * gutter - 2 * margin) / columns));
    return CGSizeMake(value, value);
}

- (CGFloat)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout*)collectionViewLayout minimumInteritemSpacingForSectionAtIndex:(NSInteger)section {
    return [self getGutter];
}

- (CGFloat)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout*)collectionViewLayout minimumLineSpacingForSectionAtIndex:(NSInteger)section {
    return [self getGutter];
}

- (UIEdgeInsets)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout*)collectionViewLayout insetForSectionAtIndex:(NSInteger)section {
    CGFloat margin = [self getMargin];
    return UIEdgeInsetsMake(margin, margin, margin, margin);
}

@end
