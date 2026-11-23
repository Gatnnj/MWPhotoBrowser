//
//  MWPhotoBrowser+Data.m
//  MWPhotoBrowser
//
//  数据源与图片加载：照片取数、缓存、相邻预加载、底层图片释放、加载完成通知
//

#import "MWCommon.h"
#import "MWPhotoBrowser.h"
#import "MWPhotoBrowserPrivate.h"
#import "MWPhotoInteractiveTransition.h"

@implementation MWPhotoBrowser (Data)

- (NSUInteger)currentIndex {
    return _currentPageIndex;
}

- (void)reloadData {

    // Rebuilding pages while the interactive drag snapshot is on screen can
    // leave the snapshot over a newly-created page. Coalesce reload requests
    // until the drag has either restored its source view or finished dismissing.
    if (self.interactiveTransition.transitionInProgress) {
        _pendingReloadData = YES;
        return;
    }

    NSUInteger previousIndex = _currentPageIndex;
    MWZoomingScrollView *currentPage = [self pageDisplayedAtIndex:previousIndex];

    // Reset
    _photoCount = NSNotFound;

    // Get data
    NSUInteger numberOfPhotos = [self numberOfPhotos];
    [self releaseAllUnderlyingPhotos:YES];
    [_photos removeAllObjects];
    [_thumbPhotos removeAllObjects];
    for (int i = 0; i < numberOfPhotos; i++) {
        [_photos addObject:[NSNull null]];
        [_thumbPhotos addObject:[NSNull null]];
    }

    // Update current page index
    if (numberOfPhotos > 0) {
        _currentPageIndex = MAX(0, MIN(_currentPageIndex, numberOfPhotos - 1));
    } else {
        _currentPageIndex = 0;
    }

    // Update layout
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
        // Get image or obtain in background
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
        // If page is current page then initiate loading of previous and next pages
        NSUInteger pageIndex = page.index;
        if (_currentPageIndex == pageIndex) {
            if (pageIndex > 0) {
                // Preload index - 1
                id <MWPhoto> photo = [self photoAtIndex:pageIndex-1];
                if (![photo underlyingImage]) {
                    [photo loadUnderlyingImageAndNotify];
                    MWLog(@"Pre-loading image at index %lu", (unsigned long)pageIndex-1);
                }
            }
            if (pageIndex < [self numberOfPhotos] - 1) {
                // Preload index + 1
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
    // Create a copy in case this array is modified while we are looping through
    // Release photos
    NSArray *copy = [_photos copy];
    for (id p in copy) {
        if (p != [NSNull null]) {
            if (preserveCurrent && p == [self photoAtIndex:self.currentIndex]) {
                continue; // skip current
            }
            [p unloadUnderlyingImage];
        }
    }
    // Release thumbs
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
            // Successful load
            [page displayImage];
            [self loadAdjacentPhotosIfNecessary:photo];
        } else if ([photo respondsToSelector:@selector(gridThumbnailImage)] && [photo gridThumbnailImage]) {
            // A grid-only downsample completed. It is not a failed full-size
            // photo load, so leave the page's full-size loading state alone.
        } else {

            // Failed to load
            UIImageView *displayedImageView = (UIImageView *)[page photoImageViewForTransition];
            if (!displayedImageView.image) [page displayImageFailure];
        }
        // Update nav
        [self updateNavigation];
    }
}

@end
