//
//  MWPhotoBrowser+Controls.m
//  MWPhotoBrowser
//
//  控件显隐：工具栏/导航栏/状态栏显隐、自动隐藏计时、单击切换调度
//

#import "MWPhotoBrowser.h"
#import "MWPhotoBrowserPrivate.h"

@implementation MWPhotoBrowser (Controls)

- (BOOL)presentingViewControllerPrefersStatusBarHidden {
    UIViewController *presenting = self.presentingViewController;
    if (presenting) {
        if ([presenting isKindOfClass:[UINavigationController class]]) {
            presenting = [(UINavigationController *)presenting topViewController];
        }
    } else {
        // We're in a navigation controller so get previous one!
        if (self.navigationController && self.navigationController.viewControllers.count > 1) {
            presenting = [self.navigationController.viewControllers objectAtIndex:self.navigationController.viewControllers.count-2];
        }
    }
    if (presenting) {
        return [presenting prefersStatusBarHidden];
    } else {
        return NO;
    }
}

// If permanent then we don't set timers to hide again
// Fades all controls on iOS 5 & 6, and iOS 7 controls slide and fade
- (void)setControlsHidden:(BOOL)hidden animated:(BOOL)animated permanent:(BOOL)permanent {

    // Force visible
    if (![self numberOfPhotos] || _gridController || self.alwaysShowControls)
        hidden = NO;

    // Cancel any timers
    [self cancelControlHiding];

    // Animations & positions
    CGFloat animatonOffset = 20;
    CGFloat animationDuration = (animated ? 0.35 : 0);

    // Status bar
    // 非 VC based 分支已删除，统一通过 VC 机制更新状态栏显隐，
    // prefersStatusBarHidden 读取 _statusBarShouldBeHidden，动画样式由
    // preferredStatusBarUpdateAnimation 指定为 slide，与旧效果一致
    if (!_leaveStatusBarAlone) {
        _statusBarShouldBeHidden = hidden;
        [UIView animateWithDuration:animationDuration animations:^(void) {
            [self setNeedsStatusBarAppearanceUpdate];
        } completion:^(BOOL finished) {}];
    }

    // Toolbar and nav bar
    // Pre-appear animation positions for sliding
    if ([self areControlsHidden] && !hidden && animated) {

        // Toolbar
        _toolbar.frame = CGRectOffset([self frameForToolbarAtOrientation:[self mw_currentInterfaceOrientation]], 0, animatonOffset);

    }
    [UIView animateWithDuration:animationDuration animations:^(void) {

        CGFloat alpha = hidden ? 0 : 1;

        // Nav bar slides up on it's own on iOS 7+
        [self.navigationController.navigationBar setAlpha:alpha];

        // Toolbar
        // 显式 self 消除 block 隐式 retain 警告
        self->_toolbar.frame = [self frameForToolbarAtOrientation:[self mw_currentInterfaceOrientation]];
        if (hidden) self->_toolbar.frame = CGRectOffset(self->_toolbar.frame, 0, animatonOffset);
        self->_toolbar.alpha = alpha;

    } completion:^(BOOL finished) {}];

    // Control hiding timer
    // Will cancel existing timer but only begin hiding if
    // they are visible
    if (!permanent) [self hideControlsAfterDelay];

}

- (BOOL)prefersStatusBarHidden {
    if (!_leaveStatusBarAlone) {
        return _statusBarShouldBeHidden;
    } else {
        return [self presentingViewControllerPrefersStatusBarHidden];
    }
}

- (UIStatusBarStyle)preferredStatusBarStyle {
    return UIStatusBarStyleLightContent;
}

- (UIStatusBarAnimation)preferredStatusBarUpdateAnimation {
    return UIStatusBarAnimationSlide;
}

- (void)cancelControlHiding {
    // If a timer exists then cancel and release
    if (_controlVisibilityTimer) {
        [_controlVisibilityTimer invalidate];
        _controlVisibilityTimer = nil;
    }
}

// Enable/disable control visiblity timer
- (void)hideControlsAfterDelay {
    if (![self areControlsHidden]) {
        [self cancelControlHiding];
        // 换成 block 版定时器 + weak self：timer 不再强持有 self，
        // 控制器被 dismiss 时能立即释放，不必等这一次触发完
        __weak typeof(self) weakSelf = self;
        _controlVisibilityTimer = [NSTimer scheduledTimerWithTimeInterval:self.delayToHideElements
                                                                 repeats:NO
                                                                   block:^(NSTimer * _Nonnull timer) {
            [weakSelf hideControls];
        }];
    }
}

- (BOOL)areControlsHidden { return (_toolbar.alpha == 0); }
- (void)hideControls { [self setControlsHidden:YES animated:YES permanent:NO]; }
- (void)showControls { [self setControlsHidden:NO animated:YES permanent:NO]; }
- (void)toggleControls { [self setControlsHidden:![self areControlsHidden] animated:YES permanent:NO]; }

#pragma mark - Single Tap Scheduling

- (void)scheduleToggleControlsFromTap {
    // 单击延迟 0.2 秒切换控件显隐，给双击留出判定窗口。
    // 使用可取消的 dispatch block：双击、开始拖拽或退出页面时能真正撤销这次排队，
    // 避免缩放 / 返回后控件又闪一下。
    [self cancelPendingTapToggle];

    __weak typeof(self) weakSelf = self;
    dispatch_block_t block = dispatch_block_create(DISPATCH_BLOCK_INHERIT_QOS_CLASS, ^{
        typeof(self) strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf->_pendingTapToggleBlock = nil;
        [strongSelf toggleControls];
    });
    _pendingTapToggleBlock = block;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), block);
}

- (void)cancelPendingTapToggle {
    if (_pendingTapToggleBlock) {
        dispatch_block_cancel(_pendingTapToggleBlock);
        _pendingTapToggleBlock = nil;
    }
}

@end
