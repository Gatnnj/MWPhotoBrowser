//
//  MWPhotoBrowser+Paging.m
//  MWPhotoBrowser
//
//  分页管理：可见页计算、页面复用、页面切换回调、UIScrollView 代理
//

#import "MWPhotoBrowser.h"
#import "MWPhotoBrowserPrivate.h"

@implementation MWPhotoBrowser (Paging)

- (void)tilePages {

    // 计算可见页范围；忽略 padding，防止回弹越界导致误加载
    CGRect visibleBounds = _pagingScrollView.bounds;
    NSInteger iFirstIndex = (NSInteger)floorf((CGRectGetMinX(visibleBounds)+PADDING*2) / CGRectGetWidth(visibleBounds));
    NSInteger iLastIndex  = (NSInteger)floorf((CGRectGetMaxX(visibleBounds)-PADDING*2-1) / CGRectGetWidth(visibleBounds));
    if (iFirstIndex < 0) iFirstIndex = 0;
    if (iFirstIndex > [self numberOfPhotos] - 1) iFirstIndex = [self numberOfPhotos] - 1;
    if (iLastIndex < 0) iLastIndex = 0;
    if (iLastIndex > [self numberOfPhotos] - 1) iLastIndex = [self numberOfPhotos] - 1;

    // 回收不可见页
    NSInteger pageIndex;
    for (MWZoomingScrollView *page in _visiblePages) {
        pageIndex = page.index;
        if (pageIndex < (NSUInteger)iFirstIndex || pageIndex > (NSUInteger)iLastIndex) {
            [_recycledPages addObject:page];
            [page prepareForReuse];
            [page removeFromSuperview];
            MWLog(@"Removed page at index %lu", (unsigned long)pageIndex);
        }
    }
    [_visiblePages minusSet:_recycledPages];
    while (_recycledPages.count > 2) // 复用池只保留 2 页
        [_recycledPages removeObject:[_recycledPages anyObject]];

    // 补齐缺失页
    for (NSUInteger index = (NSUInteger)iFirstIndex; index <= (NSUInteger)iLastIndex; index++) {
        if (![self isDisplayingPageForIndex:index]) {

            MWZoomingScrollView *page = [self dequeueRecycledPage];
            if (!page) {
                page = [[MWZoomingScrollView alloc] initWithPhotoBrowser:self];
            }
            [_visiblePages addObject:page];
            [self configurePage:page forIndex:index];

            [_pagingScrollView addSubview:page];
            MWLog(@"Added page at index %lu", (unsigned long)index);

        }
    }

}

- (BOOL)isDisplayingPageForIndex:(NSUInteger)index {
    for (MWZoomingScrollView *page in _visiblePages)
        if (page.index == index) return YES;
    return NO;
}

- (MWZoomingScrollView *)pageDisplayedAtIndex:(NSUInteger)index {
    MWZoomingScrollView *thePage = nil;
    for (MWZoomingScrollView *page in _visiblePages) {
        if (page.index == index) {
            thePage = page; break;
        }
    }
    return thePage;
}

- (MWZoomingScrollView *)pageDisplayingPhoto:(id<MWPhoto>)photo {
    MWZoomingScrollView *thePage = nil;
    for (MWZoomingScrollView *page in _visiblePages) {
        if (page.photo == photo) {
            thePage = page; break;
        }
    }
    return thePage;
}

- (void)configurePage:(MWZoomingScrollView *)page forIndex:(NSUInteger)index {
    page.frame = [self frameForPageAtIndex:index];
    page.index = index;
    page.photo = [self photoAtIndex:index];
}

- (MWZoomingScrollView *)dequeueRecycledPage {
    MWZoomingScrollView *page = [_recycledPages anyObject];
    if (page) {
        [_recycledPages removeObject:page];
    }
    return page;
}

/// 某页开始显示：释放远端大图、预加载相邻页、通知代理并更新导航
- (void)didStartViewingPageAtIndex:(NSUInteger)index {

    // 无照片时直接显示控件
    if (![self numberOfPhotos]) {
        [self setControlsHidden:NO animated:YES permanent:YES];
        return;
    }

    // 释放当前页 ±1 之外的大图
    NSUInteger i;
    if (index > 0) {
        for (i = 0; i < index-1; i++) {
            id photo = [_photos objectAtIndex:i];
            if (photo != [NSNull null]) {
                [photo unloadUnderlyingImage];
                [_photos replaceObjectAtIndex:i withObject:[NSNull null]];
                MWLog(@"Released underlying image at index %lu", (unsigned long)i);
            }
        }
    }
    if (index < [self numberOfPhotos] - 1) {
        for (i = index + 2; i < _photos.count; i++) {
            id photo = [_photos objectAtIndex:i];
            if (photo != [NSNull null]) {
                [photo unloadUnderlyingImage];
                [_photos replaceObjectAtIndex:i withObject:[NSNull null]];
                MWLog(@"Released underlying image at index %lu", (unsigned long)i);
            }
        }
    }

    // 当前图已就绪时预加载相邻页（后台加载完成后也会回调到此）
    id <MWPhoto> currentPhoto = [self photoAtIndex:index];
    if ([currentPhoto underlyingImage]) {
        [self loadAdjacentPhotosIfNecessary:currentPhoto];
    }

    // 页码变化时通知代理
    if (index != _previousPageIndex) {
        if ([self.delegate respondsToSelector:@selector(photoBrowser:didDisplayPhotoAtIndex:)])
            [self.delegate photoBrowser:self didDisplayPhotoAtIndex:index];
        _previousPageIndex = index;
    }

    // 更新导航
    [self updateNavigation];

}

#pragma mark - UIScrollView Delegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {

    // 视图未激活 / 布局中 / 旋转中不处理
    if (!_viewIsActive || _performingLayout || _rotating) return;

    // 按需铺页
    [self tilePages];

    // 计算当前页
    CGRect visibleBounds = _pagingScrollView.bounds;
    NSInteger index = (NSInteger)(floorf(CGRectGetMidX(visibleBounds) / CGRectGetWidth(visibleBounds)));
    if (index < 0) index = 0;
    if (index > [self numberOfPhotos] - 1) index = [self numberOfPhotos] - 1;
    NSUInteger previousCurrentPage = _currentPageIndex;
    _currentPageIndex = index;
    if (_currentPageIndex != previousCurrentPage) {
        [self didStartViewingPageAtIndex:index];
    }

}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    // 开始拖拽即隐藏控件
    [self setControlsHidden:YES animated:YES permanent:NO];
}

- (void)scrollViewDidEndDecelerating:(UIScrollView *)scrollView {
    // 减速停止、页面切换后更新导航
    [self updateNavigation];
}

@end
