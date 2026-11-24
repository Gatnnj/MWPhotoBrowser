//
//  MWPhotoBrowser+Data.m
//  MWPhotoBrowser
//
//  数据源与图片加载：照片取数、缓存、相邻预加载、底层图片释放、加载完成通知
//

#import "MWPhotoBrowser.h"
#import "MWPhotoBrowserPrivate.h"
#import "MWPhotoInteractiveTransition.h"
#import <os/proc.h>

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

    // 先收敛当前页码再释放：释放循环按 currentIndex 保留当前页，
    // 原顺序先释放后收敛，旧索引越界时保留目标为空，当前页会被一并清掉。
    if (numberOfPhotos > 0) {
        _currentPageIndex = MAX(0, MIN(_currentPageIndex, numberOfPhotos - 1));
    } else {
        _currentPageIndex = 0;
    }
    [self releaseAllUnderlyingPhotos:YES];
    [_photos removeAllObjects];
    [_thumbPhotos removeAllObjects];
    for (int i = 0; i < numberOfPhotos; i++) {
        [_photos addObject:[NSNull null]];
        [_thumbPhotos addObject:[NSNull null]];
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

/// 按当前进程可用内存决定每侧预加载页数（0~2）。
/// 读数为瞬时估算：字节预算决定理想档位，滞回决定实际档位，避免在阈值边界反复升降档。
- (NSUInteger)adjacentPhotoPreloadCount {

    // 内存警告冷却期内停止预载，避免刚释放又被立刻填满
    NSTimeInterval now = CACurrentMediaTime();
    if (_preloadSuppressedUntil > now) return 0;

    size_t availableBytes = [self mw_availableProcessMemory];
    const size_t mebibyte = 1024ULL * 1024ULL;
    const size_t reserveBytes = 256ULL * mebibyte;   // UI 与解码峰值余量
    const size_t perNeighborBytes = 48ULL << 20;     // 单张邻图保守解码预算（4032×3024×4 ≈ 48MiB）

    // 理想档位：可用预算扣除余量后，按每张邻图预算两侧均摊；每侧硬上限 2 张
    size_t budget = availableBytes > reserveBytes ? availableBytes - reserveBytes : 0;
    NSUInteger ideal = 0;
    if (budget >= perNeighborBytes * 2) {
        ideal = MIN(2, (budget / perNeighborBytes) / 2);
    }

    // 滞回：升档阈值（768/900MiB）高于降档阈值（700/512MiB），读数在中间带波动时保持当前档位
    NSUInteger next = _preloadCountCache;
    if (ideal > _preloadCountCache) {
        if (ideal >= 2 && availableBytes >= 900ULL * mebibyte) next = 2;
        else if (ideal >= 1 && availableBytes >= 768ULL * mebibyte) next = MAX(next, 1);
    } else if (ideal < _preloadCountCache) {
        if (ideal == 0 && availableBytes < 512ULL * mebibyte) next = 0;
        else if (ideal <= 1 && availableBytes < 700ULL * mebibyte) next = 1;
    }
    _preloadCountCache = next;
    return next;
}

/// 读取进程可用内存；API 在不支持的平台（Simulator / Mac Catalyst 等）返回 0，
/// 此时按物理内存比例兜底估算，而不是误判为“内存极低”永久关闭预载。
- (size_t)mw_availableProcessMemory {
    size_t available = os_proc_available_memory();
    if (available == 0) {
        static BOOL fallbackLogged = NO;
        available = [NSProcessInfo processInfo].physicalMemory / 8; // ≈12.5%，保守估计
        if (!fallbackLogged) {
            fallbackLogged = YES;
            MWLog(@"[Preload] os_proc_available_memory unavailable, fallback %.0f MiB",
                  available / (1024.0 * 1024.0));
        }
    }
    return available;
}

- (void)loadAdjacentPhotosIfNecessary:(id<MWPhoto>)photo {
    [self loadAdjacentPhotosIfNecessary:photo preloadCount:[self adjacentPhotoPreloadCount]];
}

/// 按给定档位预加载当前页相邻图片；前向优先，深层邻页由浅层完成通知链式触发，
/// 避免多张全分辨率图同时解码造成内存尖峰。
- (void)loadAdjacentPhotosIfNecessary:(id<MWPhoto>)photo preloadCount:(NSUInteger)preloadCount {
    MWZoomingScrollView *page = [self pageDisplayingPhoto:photo];
    // 可见页已切走则不预载；无可见页（邻页预载完成的回调链）以 _currentPageIndex 为基准继续
    if (page && _currentPageIndex != page.index) return;

    NSUInteger photoCount = [self numberOfPhotos];
    NSUInteger currentIndex = page ? page.index : _currentPageIndex;

    for (NSUInteger distance = 1; distance <= preloadCount; distance++) {
        // 前向（下一屏）优先，用户最可能继续向前浏览
        if (currentIndex + distance < photoCount) {
            [self mw_requestPreloadPhotoAtIndex:currentIndex + distance
                                   previousIndex:distance > 1 ? currentIndex + distance - 1 : NSNotFound];
        }
        if (currentIndex >= distance) {
            [self mw_requestPreloadPhotoAtIndex:currentIndex - distance
                                   previousIndex:distance > 1 ? currentIndex - distance + 1 : NSNotFound];
        }
    }
}

/// 请求指定索引图片进入后台加载；深层邻页等待浅层就绪后再发起，
/// 浅层在途时由其完成通知再次进入本方法，不会重复发起（loadUnderlyingImageAndNotify 内部有在途保护）。
- (void)mw_requestPreloadPhotoAtIndex:(NSUInteger)index previousIndex:(NSUInteger)previousIndex {
    id<MWPhoto> adjacentPhoto = [self photoAtIndex:index];
    if (!adjacentPhoto || [adjacentPhoto underlyingImage]) return;
    if (previousIndex != NSNotFound && ![[self photoAtIndex:previousIndex] underlyingImage]) return;

    [adjacentPhoto loadUnderlyingImageAndNotify];
    MWLog(@"Pre-loading image at index %lu", (unsigned long)index);
}

- (void)releaseAllUnderlyingPhotos:(BOOL)preserveCurrent {
    // 先解析一次要保留的图片对象，避免循环内反复调用 photoAtIndex: 触发委托查询；
    // 按对象身份比较，delegate 每次返回新对象时也不会误保留错对象。
    id<MWPhoto> preserved = preserveCurrent ? [self photoAtIndex:self.currentIndex] : nil;

    // 先拷贝数组避免遍历中被修改；释放大图，可保留当前页
    NSArray *copy = [_photos copy];
    for (id p in copy) {
        if (p == [NSNull null] || p == preserved) continue;
        [p unloadUnderlyingImage];
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
            // 加载成功，刷新页面
            [page displayImage];
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
    // 大图加载成功即链式推进深层预载：邻页完成时 page 为 nil，
    // 不能放在 if (page) 内，否则深层邻页永远等不到触发。
    if ([photo underlyingImage]) {
        [self loadAdjacentPhotosIfNecessary:photo];
    }
}

@end
