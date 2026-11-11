//
//  MWGridCell.m
//  MWPhotoBrowser
//
//  Created by Michael Waterfall on 08/10/2013.
//
//

#import "MWCircularProgressView.h"
#import "MWGridCell.h"
#import "MWCommon.h"
#import "MWPhotoBrowserPrivate.h"
#import "UIImage+MWPhotoBrowser.h"

#define VIDEO_INDICATOR_PADDING 10

@interface MWGridCell () {
    
    UIImageView *_imageView;
    UIImageView *_videoIndicator;
    UIImageView *_loadingError;
	UIView *_loadingIndicator;
    UIButton *_selectedButton;
    
}

@end

@implementation MWGridCell

- (id)initWithFrame:(CGRect)frame {
    if ((self = [super initWithFrame:frame])) {

        // Grey background
        self.backgroundColor = [UIColor colorWithWhite:0.12 alpha:1];
        
        // Image
        _imageView = [UIImageView new];
        _imageView.frame = self.bounds;
        _imageView.contentMode = UIViewContentModeScaleAspectFill;
        _imageView.clipsToBounds = YES;
        _imageView.autoresizesSubviews = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth;
        [self addSubview:_imageView];
        
        // Video Image
        _videoIndicator = [UIImageView new];
        _videoIndicator.hidden = NO;
        UIImage *videoIndicatorImage = [UIImage mw_imageNamed:@"VideoOverlay"];
        _videoIndicator.frame = CGRectMake(self.bounds.size.width - videoIndicatorImage.size.width - VIDEO_INDICATOR_PADDING, self.bounds.size.height - videoIndicatorImage.size.height - VIDEO_INDICATOR_PADDING, videoIndicatorImage.size.width, videoIndicatorImage.size.height);
        _videoIndicator.image = videoIndicatorImage;
        _videoIndicator.autoresizesSubviews = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin;
        [self addSubview:_videoIndicator];
        
        // Selection button
        _selectedButton = [UIButton buttonWithType:UIButtonTypeCustom];
        _selectedButton.contentMode = UIViewContentModeTopRight;
        // adjustsImageWhenHighlighted（iOS 15 废弃）已移除：该属性默认值即为 NO，删除后行为完全等价
        [_selectedButton setImage:[UIImage mw_imageNamed:@"ImageSelectedSmallOff"] forState:UIControlStateNormal];
        [_selectedButton setImage:[UIImage mw_imageNamed:@"ImageSelectedSmallOn"] forState:UIControlStateSelected];
        [_selectedButton addTarget:self action:@selector(selectionButtonPressed) forControlEvents:UIControlEventTouchDown];
        _selectedButton.hidden = YES;
        _selectedButton.frame = CGRectMake(0, 0, 44, 44);
        [self addSubview:_selectedButton];
    
		// Loading indicator
        // Listen for photo loading notifications
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

- (void)setGridController:(MWGridViewController *)gridController {
    _gridController = gridController;
    [self ensureLoadingIndicator];
    // Set custom selection image if required
    if (_gridController.browser.customImageSelectedSmallIconName) {
        [_selectedButton setImage:[UIImage imageNamed:_gridController.browser.customImageSelectedSmallIconName] forState:UIControlStateSelected];
    }
}

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
    _loadingIndicator.frame = CGRectMake(floorf((self.bounds.size.width - _loadingIndicator.frame.size.width) / 2.),
                                         floorf((self.bounds.size.height - _loadingIndicator.frame.size.height) / 2),
                                         _loadingIndicator.frame.size.width,
                                         _loadingIndicator.frame.size.height);
    _selectedButton.frame = CGRectMake(self.bounds.size.width - _selectedButton.frame.size.width - 0,
                                       0, _selectedButton.frame.size.width, _selectedButton.frame.size.height);
}

#pragma mark - Cell

- (void)prepareForReuse {
    _photo = nil;
    _gridController = nil;
    _imageView.image = nil;
    if ([_loadingIndicator respondsToSelector:@selector(setProgress:)]) {
        [(id<MWPhotoBrowserLoadingView>)_loadingIndicator setProgress:0];
    }
    _selectedButton.hidden = YES;
    [self hideImageFailure];
    [super prepareForReuse];
}

#pragma mark - Image Handling

- (void)setPhoto:(id <MWPhoto>)photo {
    [self ensureLoadingIndicator];
    _photo = photo;
    if ([photo respondsToSelector:@selector(isVideo)]) {
        _videoIndicator.hidden = !photo.isVideo;
    } else {
        _videoIndicator.hidden = YES;
    }
    if (_photo) {
        if (![_photo underlyingImage]) {
            [self showLoadingIndicator];
        } else {
            [self hideLoadingIndicator];
        }
    } else {
        [self showImageFailure];
    }
}

- (void)displayImage {
    UIImage *gridImage = nil;
    if ([_photo respondsToSelector:@selector(isZoom)] && _photo.isZoom &&
        [_photo respondsToSelector:@selector(gridThumbnailImage)]) {
        gridImage = _photo.gridThumbnailImage;
    }
    _imageView.image = gridImage ?: [_photo underlyingImage];
    _selectedButton.hidden = !_selectionMode;
    [self hideImageFailure];
    // 拿到可展示的图才收起进度环；否则保持加载态（不能无条件隐藏，
    // 否则缩略图未就绪时进度环会提前消失）
    if (_imageView.image) {
        [self hideLoadingIndicator];
    }
}

#pragma mark - Selection

- (void)setSelectionMode:(BOOL)selectionMode {
    _selectionMode = selectionMode;
}

- (void)setIsSelected:(BOOL)isSelected {
    _isSelected = isSelected;
    _selectedButton.selected = isSelected;
}

- (void)selectionButtonPressed {
    _selectedButton.selected = !_selectedButton.selected;
    [_gridController.browser setPhotoSelected:_selectedButton.selected atIndex:_index];
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
    // Only show if image is not empty
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
//            NSLog(@"%f", [[dict valueForKey:@"progress"] floatValue]);
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
        if ([photo underlyingImage]) {
            // Successful load
            [self displayImage];
        } else {
            // Failed to load
            [self showImageFailure];
        }
        [self hideLoadingIndicator];
    }
}

@end
