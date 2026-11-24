//
//  MWPhotoBrowser+Navigation.m
//  MWPhotoBrowser
//
//  导航与翻页：标题页码更新、指定页跳转、上一页/下一页
//

#import "MWPhotoBrowser.h"
#import "MWPhotoBrowserPrivate.h"

@implementation MWPhotoBrowser (Navigation)

- (void)updateNavigation {

    NSUInteger numberOfPhotos = [self numberOfPhotos];
    if (_gridController) {
        {
            self.navigationItem.title = @"全部图片";
        }
    } else if (numberOfPhotos > 1) {
        if ([self.delegate respondsToSelector:@selector(photoBrowser:titleForPhotoAtIndex:)]) {
            self.navigationItem.title = [self.delegate photoBrowser:self titleForPhotoAtIndex:_currentPageIndex];
        } else {
            self.navigationItem.title = [NSString stringWithFormat:@"%lu/%lu", (unsigned long)(_currentPageIndex+1), (unsigned long)numberOfPhotos];
        }
    } else {
        self.navigationItem.title = nil;
    }
}

- (void)jumpToPageAtIndex:(NSUInteger)index animated:(BOOL)animated {

    // 越界则不跳转
    if (index < [self numberOfPhotos]) {
        CGRect pageFrame = [self frameForPageAtIndex:index];
        [_pagingScrollView setContentOffset:CGPointMake(pageFrame.origin.x - PADDING, 0) animated:animated];
        [self updateNavigation];
    }

    // 翻页后重置控件自动隐藏计时，给用户更多停留时间
    [self hideControlsAfterDelay];

}

- (void)gotoPreviousPage {
    [self showPreviousPhotoAnimated:NO];
}
- (void)gotoNextPage {
    [self showNextPhotoAnimated:NO];
}

- (void)showPreviousPhotoAnimated:(BOOL)animated {
    [self jumpToPageAtIndex:_currentPageIndex-1 animated:animated];
}

- (void)showNextPhotoAnimated:(BOOL)animated {
    [self jumpToPageAtIndex:_currentPageIndex+1 animated:animated];
}

@end
