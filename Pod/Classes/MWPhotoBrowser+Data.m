//
//  MWPhotoBrowser+Data.m
//  MWPhotoBrowser
//
//  数据源与图片加载：照片取数、缓存、相邻预加载、底层图片释放、加载完成通知
//

#import "MWPhotoBrowser.h"
#import "MWPhotoBrowserPrivate.h"
#import "MWPhotoInteractiveTransition.h"

@implementation MWPhotoBrowser (Data)

- (NSUInteger)currentIndex {
    return _currentPageIndex;
}

- (void)reloadData {

    // 拖拽交互期间挂起重载，等快照恢复或关闭完成后再执行，避免新页盖在快照上
    if (self.interactiveTransition.transitionInProgress) {
        _pendingReloadData = YES;
        return;
    }

    NSUInteger previousIndex = _currentPageIndex;
    MWZoomingScrollView *currentPage = [self pageDisplayedAtIndex:previousIndex];

    // 重置计数
    _photoCount = NSNotFound;

    // 取数并清空旧数组，用 NSNull 占位
    NSUInteger numberOfPhotos = [self numberOfPhotos];
    [self releaseAllUnderlyingPhotos:YES];
    [_photos removeAllObjects];
    [_thumbPhotos removeAllObjects];
    for (int i = 0; i < numberOfPhotos; i++) {
        [_photos addObject:[NSNull null]];
        [_thumbPhotos addObject:[NSNull null]];
    }

    // 收敛当前页码到合法区间
    if (numberOfPhotos > 0) {
        _currentPageIndex = MAX(0, MIN(_currentPageIndex, numberOfPhotos - 1));
    } else {
        _currentPageIndex = 0;
    }

    // 视图已加载时按需保留当前页
    if ([self isViewLoaded]) {
        BOOL canKeepCurrentPage = currentPage && numberOfPhotos > 0 && previousIndex == _currentPageIndex;
        if (canKeepCurrentPage) {
            _performingLayout = YES;
            for (MWZoomingScrollView *page in [_visiblePages copy]) {
                if (page != currentPage) {
                    [page prepareForReuse];
                    [page removeFromSuperview];
                }
            }
            [_visiblePages removeAllObjects];
            [_recycledPages removeAllObjects];
            [_visiblePages addObject:currentPage];

            currentPage.index = _currentPageIndex;
            currentPage.frame = [self frameForPageAtIndex:_currentPageIndex];
            [currentPage reloadPhotoKeepingDisplayedImage:[self photoAtIndex:_currentPageIndex]];

            _pagingScrollView.contentSize = [self contentSizeForPagingScrollView];
            _pagingScrollView.contentOffset = [self contentOffsetForPageAtIndex:_currentPageIndex];
            [self tilePages];
            _performingLayout = NO;
            [self layoutVisiblePages];
        } else {
            while (_pagingScrollView.subviews.count) {
                [[_pagingScrollView.subviews lastObject] removeFromSuperview];
            }
            [self performLayout];
            [self.view setNeedsLayout];
        }
    }

}

- (NSUInteger)numberOfPhotos {
    if (_photoCount == NSNotFound) {
        if ([self.delegate respondsToSelector:@selector(numberOfPhotosInPhotoBrowser:)]) {
            _photoCount = [self.delegate numberOfPhotosInPhotoBrowser:self];
        } else if (_fixedPhotosArray) {
            _photoCount = _fixedPhotosArray.count;
        }
    }
    if (_photoCount == NSNotFound) _photoCount = 0;
    return _photoCount;
}

- (id<MWPhoto>)photoAtIndex:(NSUInteger)index {
    id <MWPhoto> photo = nil;
    if (index < _photos.count) {
        if ([_photos objectAtIndex:index] == [NSNull null]) {
            if ([self.delegate respondsToSelector:@selector(photoBrowser:photoAtIndex:)]) {
                photo = [self.delegate photoBrowser:self photoAtIndex:index];
            } else if (_fixedPhotosArray && index < _fixedPhotosArray.count) {
                photo = [_fixedPhotosArray objectAtIndex:index];
            }
            if (photo) [_photos replaceObjectAtIndex:index withObject:photo];
        } else {
            photo = [_photos objectAtIndex:index];
        }
    }
    return photo;
}

- (id<MWPhoto>)thumbPhotoAtIndex:(NSUInteger)index {
    id <MWPhoto> photo = nil;
    if (index < _thumbPhotos.count) {
        if ([_thumbPhotos objectAtIndex:index] == [NSNull null]) {
            if ([self.delegate respondsToSelector:@selector(photoBrowser:thumbPhotoAtIndex:)]) {
                photo = [self.delegate photoBrowser:self thumbPhotoAtIndex:index];
            }
            if (photo) [_thumbPhotos replaceObjectAtIndex:index withObject:photo];
        } else {
            photo = [_thumbPhotos objectAtIndex:index];
        }
    }
    return photo;
}

- (UIImage *)imageForPhoto:(id<MWPhoto>)photo {
    if (photo) {
        // 已就绪直接返回，否则触发后台加载
        if ([photo underlyingImage]) {
            return [photo underlyingImage];
        } else {
            [photo loadUnderlyingImageAndNotify];
        }
    }
    return nil;
}

- (void)loadAdjacentPhotosIfNecessary:(id<MWPhoto>)photo {
    MWZoomingScrollView *page = [self pageDisplayingPhoto:photo];
    if (page) {
        // 仅当前页预加载前后相邻页
        NSUInteger pageIndex = page.index;
        if (_currentPageIndex == pageIndex) {
            if (pageIndex > 0) {
                id <MWPhoto> photo = [self photoAtIndex:pageIndex-1];
                if (![photo underlyingImage]) {
                    [photo loadUnderlyingImageAndNotify];
                    MWLog(@"Pre-loading image at index %lu", (unsigned long)pageIndex-1);
                }
            }
            if (pageIndex < [self numberOfPhotos] - 1) {
                id <MWPhoto> photo = [self photoAtIndex:pageIndex+1];
                if (![photo underlyingImage]) {
                    [photo loadUnderlyingImageAndNotify];
                    MWLog(@"Pre-loading image at index %lu", (unsigned long)pageIndex+1);
                }
            }
        }
    }
}

- (void)releaseAllUnderlyingPhotos:(BOOL)preserveCurrent {
    // 先拷贝数组避免遍历中被修改；释放大图，可保留当前页
    NSArray *copy = [_photos copy];
    for (id p in copy) {
        if (p != [NSNull null]) {
            if (preserveCurrent && p == [self photoAtIndex:self.currentIndex]) {
                continue;
            }
            [p unloadUnderlyingImage];
        }
    }
    // 释放缩略图
    copy = [_thumbPhotos copy];
    for (id p in copy) {
        if (p != [NSNull null]) {
            [p unloadUnderlyingImage];
        }
    }
}

- (void)handleMWPhotoLoadingDidEndNotification:(NSNotification *)notification {
    id <MWPhoto> photo = [notification object];
    MWZoomingScrollView *page = [self pageDisplayingPhoto:photo];
    if (page) {
        if ([photo underlyingImage]) {
            // 加载成功，刷新页面并预加载相邻
            [page displayImage];
            [self loadAdjacentPhotosIfNecessary:photo];
        } else if ([photo respondsToSelector:@selector(gridThumbnailImage)] && [photo gridThumbnailImage]) {
            // 仅网格缩略图完成，非大图加载失败，保留大图加载态
        } else {

            // 大图加载失败，显示失败占位
            UIImageView *displayedImageView = (UIImageView *)[page photoImageViewForTransition];
            if (!displayedImageView.image) [page displayImageFailure];
        }
        // 更新导航
        [self updateNavigation];
    }
}

@end
