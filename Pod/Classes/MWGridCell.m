//
//  MWGridCell.m
//  MWPhotoBrowser
//
//  Created by Michael Waterfall on 08/10/2013.
//
//

#import "MWCircularProgressView.h"
#import "MWGridCell.h"
#import "MWPhotoBrowserPrivate.h"
#import "UIImage+MWPhotoBrowser.h"


@interface MWGridCell () {
    
    UIImageView *_imageView;
    UIImageView *_loadingError;
	UIView *_loadingIndicator;
    UIView *_currentPhotoOverlay;
    
}

@end

@implementation MWGridCell

- (id)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {

        // 灰色背景
        self.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1];

        // 缩略图视图
        _imageView = [UIImageView new];
        _imageView.frame = self.bounds;
        _imageView.contentMode = UIViewContentModeScaleAspectFill;
        _imageView.clipsToBounds = YES;
        _imageView.autoresizesSubviews = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
        [self addSubview:_imageView];

        // 当前大图对应的格子：白色细描边 + 极轻的外发光，柔和地"点亮"这一格。
        // 只用 layer 绘制，不额外加载图片，也不压暗缩略图本身。
        _currentPhotoOverlay = [UIView new];
        _currentPhotoOverlay.userInteractionEnabled = NO;
        _currentPhotoOverlay.backgroundColor = [UIColor clearColor];
        _currentPhotoOverlay.hidden = YES;
        CALayer *overlayLayer = _currentPhotoOverlay.layer;
        overlayLayer.cornerRadius = 2.0;
        overlayLayer.borderWidth = 1.0;
        overlayLayer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.6].CGColor;
        overlayLayer.shadowColor = [UIColor whiteColor].CGColor;
        overlayLayer.shadowOpacity = 0.15;
        overlayLayer.shadowRadius = 2.0;
        overlayLayer.shadowOffset = CGSizeZero;
        [self addSubview:_currentPhotoOverlay];

        
		// 监听图片加载进度与完成通知
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(setProgressFromNotification:)
                                                     name:MWPHOTO_PROGRESS_NOTIFICATION
                                                   object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(handleMWPhotoLoadingDidEndNotification:)
                                                     name:MWPHOTO_LOADING_DID_END_NOTIFICATION
                                                   object:nil];
        
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

/// 绑定网格控制器，并懒建加载指示器
- (void)setGridController:(MWGridViewController *)gridController {
    _gridController = gridController;
    [self ensureLoadingIndicator];
}

/// 懒建加载指示器：优先用浏览器提供的自定义视图，否则用内置环形进度
- (void)ensureLoadingIndicator {
    if (_loadingIndicator) return;
    UIView *customView = _gridController.browser.loadingViewProvider ? _gridController.browser.loadingViewProvider(self) : nil;
    if (customView) {
        _loadingIndicator = customView;
        if (_loadingIndicator.bounds.size.width <= 0 || _loadingIndicator.bounds.size.height <= 0) {
            _loadingIndicator.frame = CGRectMake(0, 0, 40.0f, 40.0f);
        }
    } else {
        MWCircularProgressView *defaultIndicator = [[MWCircularProgressView alloc] initWithFrame:CGRectMake(0, 0, 40.0f, 40.0f)];
        defaultIndicator.thicknessRatio = 0.1;
        _loadingIndicator = defaultIndicator;
    }
    _loadingIndicator.userInteractionEnabled = NO;
    [self addSubview:_loadingIndicator];
}

#pragma mark - View

- (void)layoutSubviews {
    [super layoutSubviews];
    _imageView.frame = self.bounds;
    _currentPhotoOverlay.frame = self.bounds;
    // 固定 shadowPath，避免阴影每次都触发离屏渲染。
    _currentPhotoOverlay.layer.shadowPath = [UIBezierPath bezierPathWithRoundedRect:_currentPhotoOverlay.bounds cornerRadius:2.0].CGPath;
    _loadingIndicator.frame = CGRectMake(floorf((self.bounds.size.width - _loadingIndicator.frame.size.width) / 2.),
                                         floorf((self.bounds.size.height - _loadingIndicator.frame.size.height) / 2),
                                         _loadingIndicator.frame.size.width,
                                         _loadingIndicator.frame.size.height);
}

#pragma mark - Cell

- (void)prepareForReuse {
    _photo = nil;
    _gridController = nil;
    _imageView.image = nil;
    _isCurrentPhoto = NO;
    _currentPhotoOverlay.hidden = YES;
    if ([_loadingIndicator respondsToSelector:@selector(setProgress:)]) {
        [(id<MWPhotoBrowserLoadingView>)_loadingIndicator setProgress:0];
    }
    [self hideImageFailure];
    [super prepareForReuse];
}

#pragma mark - Current Photo Marker

/// 切换"当前大图"标记的显隐
- (void)setIsCurrentPhoto:(BOOL)isCurrentPhoto {
    if (_isCurrentPhoto == isCurrentPhoto) return;
    _isCurrentPhoto = isCurrentPhoto;
    _currentPhotoOverlay.hidden = !isCurrentPhoto;
}

#pragma mark - Image Handling

/// 绑定图片：已就绪则直接显示，未就绪显示加载态，空对象显示失败
- (void)setPhoto:(id <MWPhoto>)photo {
    [self ensureLoadingIndicator];
    _photo = photo;
    if (_photo) {
        UIImage *thumbnail = [_photo respondsToSelector:@selector(gridThumbnailImage)] ? _photo.gridThumbnailImage : nil;
        if (!thumbnail && ![_photo underlyingImage]) {
            [self showLoadingIndicator];
        } else {
            [self displayImage];
        }
    } else {
        [self showImageFailure];
    }
}

- (void)displayImage {
    UIImage *gridImage = nil;
    if ([_photo respondsToSelector:@selector(gridThumbnailImage)]) {
        gridImage = _photo.gridThumbnailImage;
    }
    _imageView.image = gridImage ?: [_photo underlyingImage];
    [self hideImageFailure];
    // 拿到可展示的图才收起进度环；否则保持加载态（不能无条件隐藏，
    // 否则缩略图未就绪时进度环会提前消失）
    if (_imageView.image) {
        [self hideLoadingIndicator];
    }
}

#pragma mark - Touches

- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    _imageView.alpha = 0.6;
    [super touchesBegan:touches withEvent:event];
}

- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event {
    _imageView.alpha = 1;
    [super touchesEnded:touches withEvent:event];
}

- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event {
    _imageView.alpha = 1;
    [super touchesCancelled:touches withEvent:event];
}

#pragma mark Indicators

- (void)hideLoadingIndicator {
    _loadingIndicator.hidden = YES;
}

- (void)showLoadingIndicator {
    // 统一走 MWPhotoBrowserLoadingView 协议：内置实现与外部自定义 loading view
    // 只要实现了 -setProgress: 就能被重置，不再按具体类做类型判断
    if ([_loadingIndicator respondsToSelector:@selector(setProgress:)]) {
        [(id<MWPhotoBrowserLoadingView>)_loadingIndicator setProgress:0];
    }
    _loadingIndicator.hidden = NO;
    [self hideImageFailure];
}

- (void)showImageFailure {
    // 空图片不显示失败图标
    if (![_photo respondsToSelector:@selector(emptyImage)] || !_photo.emptyImage) {
        if (!_loadingError) {
            _loadingError = [UIImageView new];
            _loadingError.image = [UIImage mw_imageNamed:@"ImageError"];
            _loadingError.userInteractionEnabled = NO;
            [_loadingError sizeToFit];
            [self addSubview:_loadingError];
        }
        _loadingError.frame = CGRectMake(floorf((self.bounds.size.width - _loadingError.frame.size.width) / 2.),
                                         floorf((self.bounds.size.height - _loadingError.frame.size.height) / 2),
                                         _loadingError.frame.size.width,
                                         _loadingError.frame.size.height);
    }
    [self hideLoadingIndicator];
    _imageView.image = nil;
}

- (void)hideImageFailure {
    if (_loadingError) {
        [_loadingError removeFromSuperview];
        _loadingError = nil;
    }
}

#pragma mark - Notifications

- (void)setProgressFromNotification:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDictionary *dict = [notification object];
        id <MWPhoto> photoWithProgress = [dict objectForKey:@"photo"];
        // 显式 self 消除 block 隐式 retain 警告
        if (photoWithProgress == self->_photo) {
            float progress = [[dict valueForKey:@"progress"] floatValue];
            CGFloat normalizedProgress = MAX(MIN(1, progress), 0);
            if ([self->_loadingIndicator respondsToSelector:@selector(setProgress:)]) {
                [(id<MWPhotoBrowserLoadingView>)self->_loadingIndicator setProgress:normalizedProgress];
            }
        }
    });
}

- (void)handleMWPhotoLoadingDidEndNotification:(NSNotification *)notification {
    id <MWPhoto> photo = [notification object];
    if (photo == _photo) {
        UIImage *thumbnail = [photo respondsToSelector:@selector(gridThumbnailImage)] ? photo.gridThumbnailImage : nil;
        if (thumbnail || [photo underlyingImage]) {
            // 加载成功，刷新显示
            [self displayImage];
        } else {
            // 加载失败，显示失败占位
            [self showImageFailure];
        }
        [self hideLoadingIndicator];
    }
}

@end
