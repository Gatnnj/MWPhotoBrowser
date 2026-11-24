//
//  ZoomingScrollView.m
//  MWPhotoBrowser
//
//  Created by Michael Waterfall on 14/10/2010.
//  Copyright 2010 d3i. All rights reserved.
//

#import "MWCircularProgressView.h"
#import "MWZoomingScrollView.h"
#import "MWPhotoBrowser.h"
#import "MWPhoto.h"
#import "MWPhotoBrowserPrivate.h"
#import "UIImage+MWPhotoBrowser.h"

// 私有方法与属性
@interface MWZoomingScrollView () {
    
    MWPhotoBrowser __weak *_photoBrowser;
	MWTapDetectingView *_tapView; // for background taps
	MWTapDetectingImageView *_photoImageView;
	UIView *_loadingIndicator;
    UIImageView *_loadingError;
    
}

@end

@implementation MWZoomingScrollView

- (instancetype)initWithPhotoBrowser:(MWPhotoBrowser *)browser {
    if ((self = [super init])) {

        // 关闭 iOS 26 透明导航栏下方的滚动边缘渐隐，避免给图片染色
        if (@available(iOS 26.0, *)) {
            self.topEdgeEffect.hidden = YES;
        }

        _index = NSUIntegerMax;
        _photoBrowser = browser;

        // 背景点击视图
        _tapView = [[MWTapDetectingView alloc] initWithFrame:self.bounds];
        _tapView.tapDelegate = self;
        _tapView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        _tapView.backgroundColor = [UIColor blackColor];
        _tapView.opaque = NO;
        [self addSubview:_tapView];

        // 图片视图
        _photoImageView = [[MWTapDetectingImageView alloc] initWithFrame:CGRectZero];
        _photoImageView.tapDelegate = self;
        _photoImageView.contentMode = UIViewContentModeCenter;
        _photoImageView.backgroundColor = [UIColor blackColor];
        _photoImageView.opaque = NO;
        [self addSubview:_photoImageView];

        // 加载指示器：优先用浏览器提供的自定义视图，否则用内置环形进度
        _loadingIndicator = browser.loadingViewProvider ? browser.loadingViewProvider(self) : nil;
        if (!_loadingIndicator) {
            MWCircularProgressView *defaultIndicator = [[MWCircularProgressView alloc] initWithFrame:CGRectMake(0, 0, 40.0f, 40.0f)];
            defaultIndicator.thicknessRatio = 0.1;
            _loadingIndicator = defaultIndicator;
        } else if (_loadingIndicator.bounds.size.width <= 0 || _loadingIndicator.bounds.size.height <= 0) {
            _loadingIndicator.frame = CGRectMake(0, 0, 40.0f, 40.0f);
        }
        _loadingIndicator.userInteractionEnabled = NO;
		_loadingIndicator.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin |
        UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleRightMargin;
		[self addSubview:_loadingIndicator];

        // 监听加载进度通知
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(setProgressFromNotification:)
                                                     name:MWPHOTO_PROGRESS_NOTIFICATION
                                                   object:nil];

        self.backgroundColor = [UIColor blackColor];
		self.delegate = self;
		self.showsHorizontalScrollIndicator = NO;
		self.showsVerticalScrollIndicator = NO;
		self.decelerationRate = UIScrollViewDecelerationRateFast;
		self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;

    }
    return self;
}

- (void)dealloc {
    if ([_photo respondsToSelector:@selector(cancelAnyLoading)]) {
        [_photo cancelAnyLoading];
    }
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)prepareForReuse {
    [self hideImageFailure];
    self.photo = nil;
    _photoImageView.hidden = NO;
    _photoImageView.image = nil;
    _index = NSUIntegerMax;
}


- (void)setImageHidden:(BOOL)hidden {
    _photoImageView.hidden = hidden;
}

- (void)reloadPhotoKeepingDisplayedImage:(id<MWPhoto>)photo {
    if (_photo != photo && [_photo respondsToSelector:@selector(cancelAnyLoading)]) {
        [_photo cancelAnyLoading];
    }
    _photo = photo;
    [self hideImageFailure];

    if (!photo) {
        _photoImageView.image = nil;
        self.contentSize = CGSizeZero;
        [self showLoadingIndicator];
        return;
    }

    UIImage *image = [photo underlyingImage];
    if (image) {
        [self displayImage];
    } else {
        // 刷新模型加载期间保留旧图显示
        [self hideLoadingIndicator];
        [photo loadUnderlyingImageAndNotify];
    }
}

#pragma mark - Image

- (void)setPhoto:(id<MWPhoto>)photo {
    // 旧图有在途加载时先取消
    if (_photo && photo == nil) {
        if ([_photo respondsToSelector:@selector(cancelAnyLoading)]) {
            [_photo cancelAnyLoading];
        }
    }
    _photo = photo;
    UIImage *img = [_photoBrowser imageForPhoto:_photo];
    if (img) {
        [self displayImage];
    } else {
        // 尚未就绪，显示加载指示器
        [self showLoadingIndicator];
    }
}

/// 取图并显示；位图真正变化时才重置缩放
- (void)displayImage {
    if (!_photo) return;

    // 取图或触发加载；刷新模型未就绪时保留现有图
    UIImage *img = [_photoBrowser imageForPhoto:_photo];
    if (!img || img == _photoImageView.image) return;

    // 仅在实际位图变化时重置缩放
    self.maximumZoomScale = 1;
    self.minimumZoomScale = 1;
    self.zoomScale = 1;
    self.contentSize = CGSizeMake(0, 0);
    [self hideLoadingIndicator];
    [self hideImageFailure];

    _photoImageView.image = img;
    _photoImageView.hidden = NO;

    CGRect photoImageViewFrame = CGRectMake(0, 0, img.size.width, img.size.height);
    _photoImageView.frame = photoImageViewFrame;
    self.contentSize = photoImageViewFrame.size;
    [self setMaxMinZoomScalesForCurrentBounds];
    [self setNeedsLayout];
}

/// 加载失败：清空图片并显示失败占位（空图片不显示）
- (void)displayImageFailure {
    [self hideLoadingIndicator];
    _photoImageView.image = nil;

    // 非空图片才显示失败图标
    if (![_photo respondsToSelector:@selector(emptyImage)] || !_photo.emptyImage) {
        if (!_loadingError) {
            _loadingError = [UIImageView new];
            _loadingError.image = [UIImage mw_imageNamed:@"ImageError"];
            _loadingError.userInteractionEnabled = NO;
            _loadingError.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin |
            UIViewAutoresizingFlexibleBottomMargin | UIViewAutoresizingFlexibleRightMargin;
            [_loadingError sizeToFit];
            [self addSubview:_loadingError];
        }
        _loadingError.frame = CGRectMake(floorf((self.bounds.size.width - _loadingError.frame.size.width) / 2.),
                                         floorf((self.bounds.size.height - _loadingError.frame.size.height) / 2),
                                         _loadingError.frame.size.width,
                                         _loadingError.frame.size.height);
    }
}

- (void)hideImageFailure {
    if (_loadingError) {
        [_loadingError removeFromSuperview];
        _loadingError = nil;
    }
}

#pragma mark - Loading Progress

- (void)setProgressFromNotification:(NSNotification *)notification {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSDictionary *dict = [notification object];
        id <MWPhoto> photoWithProgress = [dict objectForKey:@"photo"];
        if (photoWithProgress == self.photo) {
            float progress = [[dict valueForKey:@"progress"] floatValue];
            // 显式 self 消除 block 隐式 retain 警告
            CGFloat normalizedProgress = MAX(MIN(1, progress), 0);
            if ([self->_loadingIndicator respondsToSelector:@selector(setProgress:)]) {
                [(id<MWPhotoBrowserLoadingView>)self->_loadingIndicator setProgress:normalizedProgress];
            }
        }
    });
}

- (void)hideLoadingIndicator {
    _loadingIndicator.hidden = YES;
}

/// 无图且图片未就绪时补显示加载指示器；已有位图或图片已加载则不动。
- (void)mw_showLoadingIndicatorIfNeeded {
    if (_photoImageView.image) return;
    if (_photo && [_photo underlyingImage]) return;
    [self showLoadingIndicator];
}

- (void)showLoadingIndicator {
    // UIScrollView 的缩放比例必须为正数；0 会触发
    // _clampedZoomScale:allowRubberbanding: 的系统警告。
    self.minimumZoomScale = 1;
    self.maximumZoomScale = 1;
    self.zoomScale = 1;
    if ([_loadingIndicator respondsToSelector:@selector(setProgress:)]) {
        [(id<MWPhotoBrowserLoadingView>)_loadingIndicator setProgress:0];
    }
    _loadingIndicator.hidden = NO;
    // 立即摆到中心，不能依赖 layoutSubviews：
    // 上面设置 zoomScale 会同步触发一次布局，那时指示器还是 hidden 状态会被跳过；
    // 之后再把 hidden 置为 NO 已经没有新的布局机会，指示器会停在 (0,0) 左上角，
    // 视觉上等同于"没有显示"。这里主动居中，保证一显示就在正确位置。
    [self centerLoadingIndicator];
    [self hideImageFailure];
}

- (void)centerLoadingIndicator {
    if (!_loadingIndicator || _loadingIndicator.hidden) return;
    CGSize boundsSize = self.bounds.size;
    CGSize indicatorSize = _loadingIndicator.frame.size;
    if (indicatorSize.width <= 0.0f || indicatorSize.height <= 0.0f) return;
    // bounds 尚未生效时不去计算，避免算出负坐标把指示器推到可视区外，
    // 交给下一次 layoutSubviews 处理即可
    if (boundsSize.width <= 0.0f || boundsSize.height <= 0.0f) return;
    _loadingIndicator.frame = CGRectMake(floorf((boundsSize.width - indicatorSize.width) / 2.0f),
                                         floorf((boundsSize.height - indicatorSize.height) / 2.0f),
                                         indicatorSize.width,
                                         indicatorSize.height);
}

#pragma mark - Setup

- (CGFloat)initialZoomScaleWithMinScale {
    CGFloat zoomScale = self.minimumZoomScale;
    if (_photoImageView && _photoBrowser.zoomPhotosToFill) {
        // 长宽比接近时按填充放大
        CGSize boundsSize = self.bounds.size;
        CGSize imageSize = _photoImageView.image.size;
        if (boundsSize.width <= 0 || boundsSize.height <= 0 || imageSize.width <= 0 || imageSize.height <= 0) return zoomScale;
        CGFloat boundsAR = boundsSize.width / boundsSize.height;
        CGFloat imageAR = imageSize.width / imageSize.height;
        CGFloat xScale = boundsSize.width / imageSize.width;
        CGFloat yScale = boundsSize.height / imageSize.height;
        // 仅在比例接近时放大，避免长图被过度拉伸
        if (ABS(boundsAR - imageAR) < 0.17) {
            zoomScale = MAX(xScale, yScale);
            // 限制在 min/max 区间内
            zoomScale = MIN(MAX(self.minimumZoomScale, zoomScale), self.maximumZoomScale);
        }
    }
    return zoomScale;
}

/// 按当前 bounds 重算最小/最大缩放与初始缩放
- (void)setMaxMinZoomScalesForCurrentBounds {

    // 先重置缩放
    self.minimumZoomScale = 1;
    self.maximumZoomScale = 1;
    self.zoomScale = 1;

    // 无图直接返回
    if (_photoImageView.image == nil) return;

    // 复位图片视图位置
    _photoImageView.frame = CGRectMake(0, 0, _photoImageView.frame.size.width, _photoImageView.frame.size.height);

    // 取容器与图片尺寸
    CGSize boundsSize = self.bounds.size;
    CGSize imageSize = _photoImageView.image.size;
    // 首次布局或旋转过程中 bounds 可能暂时为零，保留上面的 1 倍安全值。
    if (boundsSize.width <= 0 || boundsSize.height <= 0 || imageSize.width <= 0 || imageSize.height <= 0) return;

    // 最小缩放：取宽高适配的较小值，保证整图可见
    CGFloat xScale = boundsSize.width / imageSize.width;
    CGFloat yScale = boundsSize.height / imageSize.height;
    CGFloat minScale = MIN(xScale, yScale);

    // 最大缩放
    CGFloat maxScale = 3;
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
        // iPad 允许更大倍数
        maxScale = 4;
    }

    // 图片小于屏幕时不需放大，最小缩放归 1
    if (xScale >= 1 && yScale >= 1) {
        minScale = 1.0;
    }

    // 应用 min/max 缩放
    self.maximumZoomScale = maxScale;
    self.minimumZoomScale = minScale;

    // 初始缩放
    self.zoomScale = [self initialZoomScaleWithMinScale];

    // 填充放大时居中
    if (self.zoomScale != minScale) {

        self.contentOffset = CGPointMake((imageSize.width * self.zoomScale - boundsSize.width) / 2.0,
                                         (imageSize.height * self.zoomScale - boundsSize.height) / 2.0);

    }

    // 首次捏合前禁用滚动，避免初始放大态被误滑
    self.scrollEnabled = NO;

	[self setNeedsLayout];

}

#pragma mark - Layout

- (void)layoutSubviews {

	// 背景点击视图铺满
	_tapView.frame = self.bounds;

	// 居中摆放指示器与失败图
	if (!_loadingIndicator.hidden)
        [self centerLoadingIndicator];
	if (_loadingError)
        _loadingError.frame = CGRectMake(floorf((self.bounds.size.width - _loadingError.frame.size.width) / 2.),
                                         floorf((self.bounds.size.height - _loadingError.frame.size.height) / 2),
                                         _loadingError.frame.size.width,
                                         _loadingError.frame.size.height);

	[super layoutSubviews];

    // 图片小于屏幕时居中显示
    CGSize boundsSize = self.bounds.size;
    CGRect frameToCenter = _photoImageView.frame;

    // 水平居中
    if (frameToCenter.size.width < boundsSize.width) {
        frameToCenter.origin.x = floorf((boundsSize.width - frameToCenter.size.width) / 2.0);
	} else {
        frameToCenter.origin.x = 0;
	}

    // 垂直居中
    if (frameToCenter.size.height < boundsSize.height) {
        frameToCenter.origin.y = floorf((boundsSize.height - frameToCenter.size.height) / 2.0);
	} else {
        frameToCenter.origin.y = 0;
	}

	if (!CGRectEqualToRect(_photoImageView.frame, frameToCenter))
		_photoImageView.frame = frameToCenter;

}

#pragma mark - UIScrollViewDelegate

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
	return _photoImageView;
}

- (MWPhotoBrowser *)photoBrowser {
    return _photoBrowser;
}

- (UIView *)photoImageViewForTransition {
    return _photoImageView;
}

- (void)setBackgroundAlpha:(CGFloat)alpha {
    // 仅改变各层黑色背景，图片（photoImageView.image）不受影响
    UIColor *background = [UIColor colorWithWhite:0 alpha:alpha];
    self.backgroundColor = background;
    self.opaque = NO;
    _tapView.backgroundColor = background;
    _photoImageView.backgroundColor = background;
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    [_photoBrowser cancelPendingTapToggle]; // 开始横向拖动，排队中的单击不应再切换显隐
	[_photoBrowser cancelControlHiding];
}

- (void)scrollViewWillBeginZooming:(UIScrollView *)scrollView withView:(UIView *)view {
    self.scrollEnabled = YES; // reset
    [_photoBrowser cancelPendingTapToggle]; // 捏合缩放同理
	[_photoBrowser cancelControlHiding];
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
	[_photoBrowser hideControlsAfterDelay];
}

- (void)scrollViewDidZoom:(UIScrollView *)scrollView {
    [self setNeedsLayout];
    [self layoutIfNeeded];
}

#pragma mark - Tap Detection

- (void)handleSingleTap:(CGPoint)touchPoint {
    // 单击 / 双击的时序统一交给 browser 调度：延迟 0.2 秒切换控件显隐，
    // 双击时由 handleDoubleTap 取消这次排队，避免缩放后工具栏再闪一下
    [_photoBrowser scheduleToggleControlsFromTap];
}

- (void)handleDoubleTap:(CGPoint)touchPoint {
    
	
	// 取消排队中的单击切换显隐（双击缩放后不应再闪一次工具栏）
	[_photoBrowser cancelPendingTapToggle];
	
	// 双击切换缩放
	if (self.zoomScale != self.minimumZoomScale && self.zoomScale != [self initialZoomScaleWithMinScale]) {

		// 已放大则缩回最小
		[self setZoomScale:self.minimumZoomScale animated:YES];
		
	} else {
		
		// 未放大则取居中倍率，把触点放大到屏幕中心
        CGFloat newZoomScale = ((self.maximumZoomScale + self.minimumZoomScale) / 2);
        CGFloat xsize = self.bounds.size.width / newZoomScale;
        CGFloat ysize = self.bounds.size.height / newZoomScale;
        [self zoomToRect:CGRectMake(touchPoint.x - xsize/2, touchPoint.y - ysize/2, xsize, ysize) animated:YES];

	}
	
	// 重置控件隐藏计时
	[_photoBrowser hideControlsAfterDelay];
	
}

// 图片视图点击回调
- (void)imageView:(UIImageView *)imageView singleTapDetected:(UITouch *)touch {
    [self handleSingleTap:[touch locationInView:imageView]];
}
- (void)imageView:(UIImageView *)imageView doubleTapDetected:(UITouch *)touch {
    [self handleDoubleTap:[touch locationInView:imageView]];
}

// 背景视图点击回调
- (void)view:(UIView *)view singleTapDetected:(UITouch *)touch {
    // 把点击点换算到图片坐标（考虑缩放与内容偏移）
    CGFloat touchX = [touch locationInView:view].x;
    CGFloat touchY = [touch locationInView:view].y;
    touchX *= 1/self.zoomScale;
    touchY *= 1/self.zoomScale;
    touchX += self.contentOffset.x;
    touchY += self.contentOffset.y;
    [self handleSingleTap:CGPointMake(touchX, touchY)];
}
- (void)view:(UIView *)view doubleTapDetected:(UITouch *)touch {
    // 把点击点换算到图片坐标（考虑缩放与内容偏移）
    CGFloat touchX = [touch locationInView:view].x;
    CGFloat touchY = [touch locationInView:view].y;
    touchX *= 1/self.zoomScale;
    touchY *= 1/self.zoomScale;
    touchX += self.contentOffset.x;
    touchY += self.contentOffset.y;
    [self handleDoubleTap:CGPointMake(touchX, touchY)];
}

@end
