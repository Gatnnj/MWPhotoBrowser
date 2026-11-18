//
//  MWWaterfallViewController.m
//  MWPhotoBrowser_Example
//

#import "MWWaterfallViewController.h"
#import "MWWaterfallLayout.h"
#if __has_include(<SDWebImage/SDWebImage.h>)
#import <SDWebImage/SDWebImage.h>
#else
#import "SDWebImage.h"
#endif
#import "MWPhotoBrowser.h"
#import "MWCommon.h"

static NSString * const kMWWaterfallCellReuseID = @"MWWaterfallCellReuseID";

#pragma mark - Cell

@interface MWWaterfallCell : UICollectionViewCell
@property (nonatomic, strong) UIImageView *imageView;
@end

@implementation MWWaterfallCell

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.contentView.clipsToBounds = YES;
        self.contentView.layer.cornerRadius = 6.0;
        self.contentView.backgroundColor = [UIColor secondarySystemBackgroundColor];

        _imageView = [[UIImageView alloc] initWithFrame:self.contentView.bounds];
        _imageView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _imageView.contentMode = UIViewContentModeScaleAspectFill;
        _imageView.clipsToBounds = YES;
        [self.contentView addSubview:_imageView];
    }
    return self;
}

- (void)prepareForReuse {
    [super prepareForReuse];
    [self.imageView sd_cancelCurrentImageLoad];
    self.imageView.image = nil;
}

@end

#pragma mark - 工具：从 picsum URL 末尾两位解析高宽比

static CGFloat MWImageAspectRatioFromURLString(NSString *urlString) {
    NSMutableArray<NSNumber *> *numbers = [NSMutableArray array];
    for (NSString *component in [urlString pathComponents].reverseObjectEnumerator) {
        if (component.length == 0) {
            continue;
        }
        BOOL numeric = YES;
        for (NSUInteger i = 0; i < component.length; i++) {
            unichar c = [component characterAtIndex:i];
            if (c < '0' || c > '9') {
                numeric = NO;
                break;
            }
        }
        if (numeric) {
            [numbers addObject:@(component.doubleValue)];
            if (numbers.count == 2) {
                break;
            }
        }
    }
    if (numbers.count < 2) {
        return 0.75; // 兜底 4:3
    }
    CGFloat height = numbers[0].doubleValue; // URL 末位是 height
    CGFloat width  = numbers[1].doubleValue; // 倒数第二位是 width
    return (width > 0.0) ? (height / width) : 0.75;
}

#pragma mark - View Controller

@interface MWWaterfallViewController () <MWWaterfallLayoutDelegate, MWPhotoBrowserDelegate>

@property (nonatomic, strong) NSArray<NSString *> *imageURLStrings;
@property (nonatomic, strong) MWWaterfallLayout *waterfallLayout;
@property (nonatomic, strong) NSMutableArray<MWPhoto *> *photos;

// 丝滑转场演示专用：在窗口上放置一个缩略图作为连贯动画的起点
@property (nonatomic, weak) UIImageView *demoSourceImageView;
@end

@implementation MWWaterfallViewController

- (instancetype)init {
    MWWaterfallLayout *layout = [[MWWaterfallLayout alloc] init];
    layout.numberOfColumns = 2;
    layout.minimumInteritemSpacing = 8.0;
    layout.minimumLineSpacing = 8.0;
    layout.sectionInset = UIEdgeInsetsMake(12.0, 12.0, 12.0, 12.0);

    if (self = [super initWithCollectionViewLayout:layout]) {
        _waterfallLayout = layout;
        _waterfallLayout.waterfallDelegate = self;
        // 缩略尺寸：保留原始比例（3:2 / 16:9 / 2:3 / 1:1），宽度压到 400~640
        // 15 张基础图 × 4 份 = 60 条；顺序已打散：竖图不相邻、同图不相邻、同类比例最多连续 3 个
        _imageURLStrings = @[
            @"https://picsum.photos/id/1021/640/360",
            @"https://picsum.photos/id/1035/640/360",
            @"https://picsum.photos/id/1025/400/600",
            @"https://picsum.photos/id/1035/640/360",
            @"https://picsum.photos/id/1015/600/400",
            @"https://picsum.photos/id/1036/600/400",
            @"https://picsum.photos/id/1023/500/500",
            @"https://picsum.photos/id/1022/400/600",
            @"https://picsum.photos/id/1041/640/360",
            @"https://picsum.photos/id/1015/600/400",
            @"https://picsum.photos/id/1040/600/400",
            @"https://picsum.photos/id/1016/600/400",
            @"https://picsum.photos/id/1019/400/600",
            @"https://picsum.photos/id/1036/600/400",
            @"https://picsum.photos/id/1023/500/500",
            @"https://picsum.photos/id/1025/400/600",
            @"https://picsum.photos/id/1021/640/360",
            @"https://picsum.photos/id/1020/600/400",
            @"https://picsum.photos/id/1023/500/500",
            @"https://picsum.photos/id/1039/400/600",
            @"https://picsum.photos/id/1040/600/400",
            @"https://picsum.photos/id/1016/600/400",
            @"https://picsum.photos/id/1020/600/400",
            @"https://picsum.photos/id/1022/400/600",
            @"https://picsum.photos/id/1040/600/400",
            @"https://picsum.photos/id/1039/400/600",
            @"https://picsum.photos/id/1016/600/400",
            @"https://picsum.photos/id/1024/600/400",
            @"https://picsum.photos/id/1023/500/500",
            @"https://picsum.photos/id/1019/400/600",
            @"https://picsum.photos/id/1018/640/360",
            @"https://picsum.photos/id/1036/600/400",
            @"https://picsum.photos/id/1040/600/400",
            @"https://picsum.photos/id/1039/400/600",
            @"https://picsum.photos/id/1020/600/400",
            @"https://picsum.photos/id/1041/640/360",
            @"https://picsum.photos/id/1020/600/400",
            @"https://picsum.photos/id/1024/600/400",
            @"https://picsum.photos/id/1025/400/600",
            @"https://picsum.photos/id/1016/600/400",
            @"https://picsum.photos/id/1018/640/360",
            @"https://picsum.photos/id/1019/400/600",
            @"https://picsum.photos/id/1015/600/400",
            @"https://picsum.photos/id/1041/640/360",
            @"https://picsum.photos/id/1015/600/400",
            @"https://picsum.photos/id/1039/400/600",
            @"https://picsum.photos/id/1018/640/360",
            @"https://picsum.photos/id/1035/640/360",
            @"https://picsum.photos/id/1021/640/360",
            @"https://picsum.photos/id/1022/400/600",
            @"https://picsum.photos/id/1021/640/360",
            @"https://picsum.photos/id/1025/400/600",
            @"https://picsum.photos/id/1036/600/400",
            @"https://picsum.photos/id/1018/640/360",
            @"https://picsum.photos/id/1024/600/400",
            @"https://picsum.photos/id/1035/640/360",
            @"https://picsum.photos/id/1022/400/600",
            @"https://picsum.photos/id/1041/640/360",
            @"https://picsum.photos/id/1019/400/600",
            @"https://picsum.photos/id/1024/600/400",
        ];
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.navigationItem.title = @"Waterfall";
    self.collectionView.backgroundColor = [UIColor systemBackgroundColor];
    self.collectionView.alwaysBounceVertical = YES;
    [self.collectionView registerClass:[MWWaterfallCell class]
                forCellWithReuseIdentifier:kMWWaterfallCellReuseID];
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)collectionView:(UICollectionView *)collectionView
     numberOfItemsInSection:(NSInteger)section {
    return self.imageURLStrings.count;
}

- (__kindof UICollectionViewCell *)collectionView:(UICollectionView *)collectionView
                           cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    MWWaterfallCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:kMWWaterfallCellReuseID
                                                                      forIndexPath:indexPath];
    NSURL *url = [NSURL URLWithString:self.imageURLStrings[indexPath.item]];
    [cell.imageView sd_setImageWithURL:url
                      placeholderImage:nil
                               options:SDWebImageRetryFailed | SDWebImageLowPriority];
    return cell;
}

#pragma mark - MWWaterfallLayoutDelegate

- (CGFloat)waterfallLayout:(MWWaterfallLayout *)layout
 heightForItemAtIndexPath:(NSIndexPath *)indexPath
                  itemWidth:(CGFloat)itemWidth {
    CGFloat ratio = MWImageAspectRatioFromURLString(self.imageURLStrings[indexPath.item]);
    return itemWidth * ratio;
}

#pragma mark - UICollectionViewDelegate

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    [[SDImageCache sharedImageCache] clearDiskOnCompletion:^{
        
    }];
    
    // 1. 准备本地图片数据
    NSMutableArray *demoPhotos = [NSMutableArray array];
//    NSArray *urls = @[@"photo1", @"photo2", @"photo2", @"photo3", @"photo4"];
    NSArray<NSString *> *urls = @[
        @"https://picsum.photos/id/1015/3840/2560",
        @"https://picsum.photos/id/1016/3840/2560",
        @"https://picsum.photos/id/1020/3840/2560",
        @"https://picsum.photos/id/1024/3840/2560",
        @"https://picsum.photos/id/1036/3840/2560",
        @"https://picsum.photos/id/1040/3840/2560",
        @"https://picsum.photos/id/1018/3840/2160",
        @"https://picsum.photos/id/1021/3840/2160",
        @"https://picsum.photos/id/1035/3840/2160",
        @"https://picsum.photos/id/1041/3840/2160",
        @"https://picsum.photos/id/1019/2560/3840",
        @"https://picsum.photos/id/1022/2560/3840",
        @"https://picsum.photos/id/1025/2560/3840",
        @"https://picsum.photos/id/1039/2560/3840",
        @"https://picsum.photos/id/1023/3000/3000",
    ];

    NSInteger index = 0;
    for (NSString *url in urls) {
//        MWPhoto *p = [MWPhoto photoWithURL:[NSURL fileURLWithPath:[[NSBundle mainBundle] pathForResource:url ofType:@"jpg"]] isBlur:[url isEqualToString:@"photo2"]];
        MWPhoto *p = [MWPhoto photoWithURL:[NSURL URLWithString:url] isBlur:[url isEqualToString:@"https://picsum.photos/id/1016/3840/2560"]];
        p.radius = index == 1 ? 30 : 20;
        [demoPhotos addObject:p];
        index++;
    }
    self.photos = demoPhotos;

    // 2. 在窗口左下角放一个缩略图作为连贯动画起点
    // 真实 App 中应直接传入列表 cell 上的 imageView，无需额外创建
    MWWaterfallCell *cell = (MWWaterfallCell *)[collectionView cellForItemAtIndexPath:indexPath];
    self.demoSourceImageView = cell.imageView;

    // 3. 创建浏览器并启用自定义转场
    MWPhotoBrowser *browser = [[MWPhotoBrowser alloc] initWithDelegate:self];
    browser.enableCustomTransition = YES;
    browser.enableGrid = YES;
    browser.startOnGrid = NO;
    [browser setCurrentPhotoIndex:0];

    // 4. 使用 OverFullScreen 保留底层列表，拖拽时才能透出背景
    UINavigationController *nc = [[UINavigationController alloc] initWithRootViewController:browser];
    nc.modalPresentationStyle = UIModalPresentationOverFullScreen;
    nc.view.backgroundColor = [UIColor clearColor];
    nc.view.opaque = NO;
    nc.transitioningDelegate = browser;
    [self presentViewController:nc animated:YES completion:nil];
}

#pragma mark - 丝滑转场演示

#pragma mark - MWPhotoBrowserDelegate

- (NSUInteger)numberOfPhotosInPhotoBrowser:(MWPhotoBrowser *)photoBrowser {
    return _photos.count;
}

// 丝滑转场：返回连贯动画的起始/飞回缩略图
- (UIView *)photoBrowser:(MWPhotoBrowser *)photoBrowser startingViewForPhotoAtIndex:(NSUInteger)index {
    // 仅首张返回演示源视图，其余页返回 nil 由动画器自动降级
    return self.demoSourceImageView;
}

- (id <MWPhoto>)photoBrowser:(MWPhotoBrowser *)photoBrowser photoAtIndex:(NSUInteger)index {
    if (index < _photos.count)
        return [_photos objectAtIndex:index];
    return nil;
}

- (id <MWPhoto>)photoBrowser:(MWPhotoBrowser *)photoBrowser thumbPhotoAtIndex:(NSUInteger)index {
//    if (index < _thumbs.count)
//        return [_thumbs objectAtIndex:index];
    return nil;
}

//- (MWCaptionView *)photoBrowser:(MWPhotoBrowser *)photoBrowser captionViewForPhotoAtIndex:(NSUInteger)index {
//    MWPhoto *photo = [self.photos objectAtIndex:index];
//    MWCaptionView *captionView = [[MWCaptionView alloc] initWithPhoto:photo];
//    return [captionView autorelease];
//}

- (void)photoBrowser:(MWPhotoBrowser *)photoBrowser didDisplayPhotoAtIndex:(NSUInteger)index {
    NSLog(@"Did start viewing photo at index %lu", (unsigned long)index);
}

- (void)photoBrowserDidFinishModalPresentation:(MWPhotoBrowser *)photoBrowser {
    // If we subscribe to this method we must dismiss the view controller ourselves
    NSLog(@"Did finish modal presentation");
    UIImageView *demoSource = self.demoSourceImageView;
    [self dismissViewControllerAnimated:YES completion:^{
        // 关闭动画结束后移除演示用的缩略图源视图
        [demoSource removeFromSuperview];
    }];
}

@end
