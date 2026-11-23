//
//  MWPhotoBrowser+NavBar.m
//  MWPhotoBrowser
//
//  导航栏外观：进入时样式设置、进入前状态保存、退出时恢复
//

#import "MWPhotoBrowser.h"
#import "MWPhotoBrowserPrivate.h"

@implementation MWPhotoBrowser (NavBar)

- (void)setNavBarAppearance:(BOOL)animated {
    [self.navigationController setNavigationBarHidden:NO animated:animated];
    UINavigationBar *navBar = self.navigationController.navigationBar;
    navBar.tintColor = [UIColor whiteColor];
    navBar.barTintColor = nil;
    navBar.translucent = YES;
//    navBar.barStyle = UIBarStyleBlack;

    // iOS 13+ 导航栏背景由 UINavigationBarAppearance 控制，仅设置老 API
    // （backgroundImage / barTintColor）会被系统默认外观的磨砂黑色渐变覆盖。
    // 这里显式配置无背景、无磨砂、无阴影的透明外观，标题保持白色。
    UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
    [appearance configureWithTransparentBackground];
    appearance.backgroundColor = [UIColor clearColor];
    appearance.backgroundImage = nil;
    appearance.backgroundEffect = nil;
    appearance.shadowColor = [UIColor clearColor];
    appearance.shadowImage = nil;
    appearance.titleTextAttributes = @{NSFontAttributeName:[UIFont systemFontOfSize:15],NSForegroundColorAttributeName:[UIColor whiteColor]};
    navBar.standardAppearance = appearance;
    navBar.scrollEdgeAppearance = appearance;
    navBar.compactAppearance = appearance;
    if (@available(iOS 15.0, *)) {
        navBar.compactScrollEdgeAppearance = appearance;
    }

    // 兼容老 API：清空背景图与阴影，背景色置透明
    [navBar setBackgroundImage:[UIImage new] forBarMetrics:UIBarMetricsDefault];
    navBar.shadowImage = [UIImage new];
    navBar.backgroundColor = [UIColor clearColor];
}

- (void)storePreviousNavBarAppearance {
    _didSavePreviousStateOfNavBar = YES;
    UINavigationBar *navBar = self.navigationController.navigationBar;
    _previousNavBarBarTintColor = navBar.barTintColor;
    _previousNavBarTranslucent = navBar.translucent;
    _previousNavBarTintColor = navBar.tintColor;
    _previousNavBarHidden = self.navigationController.navigationBarHidden;
    _previousNavBarStyle = navBar.barStyle;
    _previousNavigationBarBackgroundImageDefault = [navBar backgroundImageForBarMetrics:UIBarMetricsDefault];
    _previousNavBarStandardAppearance = navBar.standardAppearance;
    _previousNavBarScrollEdgeAppearance = navBar.scrollEdgeAppearance;
    _previousNavBarCompactAppearance = navBar.compactAppearance;
    if (@available(iOS 15.0, *)) {
        _previousNavBarCompactScrollEdgeAppearance = navBar.compactScrollEdgeAppearance;
    }
}

- (void)restorePreviousNavBarAppearance:(BOOL)animated {
    if (_didSavePreviousStateOfNavBar) {
        [self.navigationController setNavigationBarHidden:_previousNavBarHidden animated:animated];
        UINavigationBar *navBar = self.navigationController.navigationBar;
        navBar.tintColor = _previousNavBarTintColor;
        navBar.translucent = _previousNavBarTranslucent;
        navBar.barTintColor = _previousNavBarBarTintColor;
        navBar.barStyle = _previousNavBarStyle;
        [navBar setBackgroundImage:_previousNavigationBarBackgroundImageDefault forBarMetrics:UIBarMetricsDefault];
        if (_previousNavBarStandardAppearance) navBar.standardAppearance = _previousNavBarStandardAppearance;
        if (_previousNavBarScrollEdgeAppearance) navBar.scrollEdgeAppearance = _previousNavBarScrollEdgeAppearance;
        navBar.compactAppearance = _previousNavBarCompactAppearance;
        if (@available(iOS 15.0, *)) {
            navBar.compactScrollEdgeAppearance = _previousNavBarCompactScrollEdgeAppearance;
        }
    }
}

@end
