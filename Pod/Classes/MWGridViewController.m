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
#import "MWCommon.h"

@interface MWGridViewController () {
    
    // Store margins for current setup
    CGFloat _margin, _gutter, _marginL, _gutterL, _columns, _columnsL;
    
    // Initial position already applied for this grid instance; prevents repeated reapplication.
    BOOL _didApplyInitialPosition;
    
}

@end

@implementation MWGridViewController

- (id)init {
    if ((self = [super initWithCollectionViewLayout:[UICollectionViewFlowLayout new]])) {
        
        // Defaults
        _columns = 3; _columnsL = 4;
        _margin = 0; _gutter = 1;
        _marginL = 0; _gutterL = 1;
        
        // For pixel perfection...
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
    // Drop decoded thumbnails from the photo objects; their SDWebImage disk
    // entries remain available if the grid is opened again.
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

- (void)viewWillLayoutSubviews {
    [super viewWillLayoutSubviews];
    [self performLayout];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
}

- (void)adjustOffsetsAsRequired {
    // 每个网格实例只定位一次：布局回调可能多次触发，重复居中会把用户手动滚动的位置拽回去。
    // Position the current photo once per grid instance; repeated layout passes must not
    // yank the content back while the user is scrolling.
    if (_didApplyInitialPosition) return;
    if (_browser.numberOfPhotos == 0) return;
    _didApplyInitialPosition = YES;

    if (_browser.currentIndex >= _browser.numberOfPhotos) return;

    // 把当前大图对应的格子居中显示。CenteredVertically 会把偏移量夹到合法区间，
    // 所以当前照片位于首行、或内容不足一屏时，结果自然停在顶部，不会出现上方留白。
    // Center the cell of the photo currently shown in the pager. UICollectionView clamps
    // the offset, so a photo in the first rows (or content shorter than one screen) stays
    // at the top rather than leaving blank space above.
    NSIndexPath *currentPhotoIndexPath = [NSIndexPath indexPathForItem:_browser.currentIndex inSection:0];
    [self.collectionView scrollToItemAtIndexPath:currentPhotoIndexPath
                               atScrollPosition:UICollectionViewScrollPositionCenteredVertically
                                       animated:NO];
}

- (void)performLayout {
//    UINavigationBar *navBar = self.navigationController.navigationBar;
//    self.collectionView.contentInset = UIEdgeInsetsMake(navBar.frame.origin.y + navBar.frame.size.height + [self getGutter], 0, 0, 0);
}

//- (void)willAnimateRotationToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration {
//    [self.collectionView reloadData];
//    [self performLayout]; // needed for iOS 5 & 6
//}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id <UIViewControllerTransitionCoordinator>)coordinator {
    [self.collectionView reloadData];
    [self performLayout]; // needed for iOS 8
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
    // Mark the cell matching the photo currently shown in the pager.
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
    // Record that the user has picked a photo from the grid: set once, never reset.
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
