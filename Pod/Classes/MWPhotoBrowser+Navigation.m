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

    // Title
    NSUInteger numberOfPhotos = [self numberOfPhotos];
    if (_gridController) {
        {
            NSString *photosText;
            if (numberOfPhotos == 1) {
                photosText = NSLocalizedString(@"photo", @"Used in the context: '1 photo'");
            } else {
                photosText = NSLocalizedString(@"photos", @"Used in the context: '3 photos'");
            }
            self.navigationItem.title = [NSString stringWithFormat:@"%lu %@", (unsigned long)numberOfPhotos, photosText];
        }
    } else if (numberOfPhotos > 1) {
        if ([self.delegate respondsToSelector:@selector(photoBrowser:titleForPhotoAtIndex:)]) {
            self.navigationItem.title = [self.delegate photoBrowser:self titleForPhotoAtIndex:_currentPageIndex];
        } else {
            self.navigationItem.title = [NSString stringWithFormat:@"%lu %@ %lu", (unsigned long)(_currentPageIndex+1), NSLocalizedString(@"of", @"Used in the context: 'Showing 1 of 3 items'"), (unsigned long)numberOfPhotos];
        }
    } else {
        self.navigationItem.title = nil;
    }
}

- (void)jumpToPageAtIndex:(NSUInteger)index animated:(BOOL)animated {

    // Change page
    if (index < [self numberOfPhotos]) {
        CGRect pageFrame = [self frameForPageAtIndex:index];
        [_pagingScrollView setContentOffset:CGPointMake(pageFrame.origin.x - PADDING, 0) animated:animated];
        [self updateNavigation];
    }

    // Update timer to give more time
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
