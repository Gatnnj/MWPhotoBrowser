//
//  YBIBUtilities.m
//  YBImageBrowserDemo
//
//  Created by 杨少 on 2018/4/11.
//  Copyright © 2018年 波儿菜. All rights reserved.
//

#import "YBIBUtilities.h"
#import <sys/utsname.h>


UIWindow * _Nullable YBIBNormalWindow(void) {
    UIWindow *normalWindow = nil;
    UIWindow *fallbackKeyWindow = nil;
    
    NSSet<UIScene *> *scenes = [UIApplication sharedApplication].connectedScenes;
    
    for (UIScene *scene in scenes) {
        // 过滤掉非 WindowScene 的情况 (例如某些后台任务 scene)
        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }
        
        UIWindowScene *windowScene = (UIWindowScene *)scene;
        // 判断当前 Scene 是否处于前台激活状态
        BOOL isActive = (windowScene.activationState == UISceneActivationStateForegroundActive);
        
        for (UIWindow *window in windowScene.windows) {
            // 1. 寻找 UIWindowLevelNormal 的窗口
            if (window.windowLevel == UIWindowLevelNormal) {
                // 如果是前台激活 Scene 的 Normal Window，直接返回，效率最高
                if (isActive) {
                    return window;
                }
                // 否则记录为备选
                if (!normalWindow) {
                    normalWindow = window;
                }
            }
            
            // 2. 顺便记录当前激活 Scene 的 KeyWindow 作为最终兜底
            if (isActive && window.isKeyWindow && !fallbackKeyWindow) {
                fallbackKeyWindow = window;
            }
        }
    }
    
    // 优先返回 NormalWindow，如果没有则返回 KeyWindow 兜底（保持与你原代码逻辑一致）
    return normalWindow ?: fallbackKeyWindow;
}

UIWindow * _Nullable YBMainWindow(void) {
    for (UIWindowScene* windowScene in [UIApplication sharedApplication].connectedScenes) {
        if (windowScene.activationState == UISceneActivationStateForegroundActive) {
            for (UIWindow *window in windowScene.windows) {
                if (window.isKeyWindow) {
                    return window;
                }
            }
            // 如果当前激活场景没有 keyWindow，返回该场景的第一个 window 兜底
            return windowScene.windows.firstObject;
        }
    }
    
    // 兜底：如果没有激活的场景，遍历所有场景找 keyWindow
    for (UIWindowScene* windowScene in [UIApplication sharedApplication].connectedScenes) {
        for (UIWindow *window in windowScene.windows) {
            if (window.isKeyWindow) {
                return window;
            }
        }
    }
    
    // iOS 13 以下的老系统兜底
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    return [UIApplication sharedApplication].keyWindow;
#pragma clang diagnostic pop
}

UIViewController * _Nullable YBIBTopController(void) {
    return YBIBTopControllerByWindow(YBIBNormalWindow());
}

UIViewController * _Nullable YBIBTopControllerByWindow(UIWindow *window) {
    if (!window) return nil;
        
    UIViewController *top = nil;
    id nextResponder;
    if (window.subviews.count > 0) {
        UIView *frontView = [window.subviews objectAtIndex:0];
        nextResponder = frontView.nextResponder;
    }
    if (nextResponder && [nextResponder isKindOfClass:UIViewController.class]) {
        top = nextResponder;
    } else {
        top = window.rootViewController;
    }
    
    while ([top isKindOfClass:UITabBarController.class] || [top isKindOfClass:UINavigationController.class] || top.presentedViewController) {
        if ([top isKindOfClass:UITabBarController.class]) {
            top = ((UITabBarController *)top).selectedViewController;
        } else if ([top isKindOfClass:UINavigationController.class]) {
            top = ((UINavigationController *)top).topViewController;
        } else if (top.presentedViewController) {
            top = top.presentedViewController;
        }
    }
    return top;
}

BOOL YBIBLowMemory(void) {
    static BOOL lowMemory = NO;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        unsigned long long physicalMemory = [[NSProcessInfo processInfo] physicalMemory];
        lowMemory = physicalMemory > 0 && physicalMemory < 1024 * 1024 * 1500;
    });
    return lowMemory;
}

BOOL YBIBIsIphoneXSeries(void) {
    return YBIBStatusbarHeight() > 20;
}

CGFloat YBIBStatusbarHeight(void) {
    CGFloat height = YBMainWindow().safeAreaInsets.top;
    if (height <= 0) {
        height = 20;
    }
    return height;
}

CGFloat YBIBSafeAreaBottomHeight(void) {
    CGFloat bottom = YBMainWindow().safeAreaInsets.bottom;
    return bottom;
}



UIImage *YBIBSnapshotView(UIView *view) {
//    UIGraphicsBeginImageContextWithOptions(view.bounds.size, YES, [UIScreen mainScreen].scale);
//    [view drawViewHierarchyInRect:view.bounds afterScreenUpdates:NO];
//    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
//    UIGraphicsEndImageContext();
    UIGraphicsImageRendererFormat *format = [[UIGraphicsImageRendererFormat alloc] init];
    format.opaque = YES;
    format.scale = [UIScreen mainScreen].scale;
    
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:view.bounds.size format:format];
    UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull rendererContext) {
            [view drawViewHierarchyInRect:view.bounds afterScreenUpdates:NO];
    }];
    return image;
}

UIInterfaceOrientation YBCurrentInterfaceOrientation(void) {
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }

        UIWindowScene *windowScene = (UIWindowScene *)scene;

        if (windowScene.activationState == UISceneActivationStateForegroundActive) {
            return windowScene.interfaceOrientation;
        }
    }

    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }

        UIWindowScene *windowScene = (UIWindowScene *)scene;
        return windowScene.interfaceOrientation;
    }

    return UIInterfaceOrientationUnknown;
}

UIEdgeInsets YBIBPaddingByBrowserOrientation(UIDeviceOrientation orientation) {
    UIEdgeInsets padding = UIEdgeInsetsZero;
    if (!YBIBIsIphoneXSeries()) return padding;
    
//    UIDeviceOrientation barOrientation = (UIDeviceOrientation)UIApplication.sharedApplication.statusBarOrientation;
    UIDeviceOrientation barOrientation = (UIDeviceOrientation)YBCurrentInterfaceOrientation();
    
    if (UIDeviceOrientationIsLandscape(orientation)) {
        BOOL same = orientation == barOrientation;
        BOOL reverse = !same && UIDeviceOrientationIsLandscape(barOrientation);
        if (same) {
            padding.bottom = YBIBSafeAreaBottomHeight();
            padding.top = 0;
        } else if (reverse) {
            padding.top = YBIBSafeAreaBottomHeight();
            padding.bottom = 0;
        }
        padding.left = padding.right = MAX(YBIBSafeAreaBottomHeight(), YBIBStatusbarHeight());
    } else {
        if (orientation == UIDeviceOrientationPortrait) {
            padding.top = YBIBStatusbarHeight();
            padding.bottom = barOrientation == UIDeviceOrientationPortrait ? YBIBSafeAreaBottomHeight() : 0;
        } else {
            padding.bottom = YBIBStatusbarHeight();
            padding.top = barOrientation == UIDeviceOrientationPortrait ? YBIBSafeAreaBottomHeight() : 0;
        }
        padding.left = padding.right = UIDeviceOrientationIsLandscape(barOrientation) ? YBIBSafeAreaBottomHeight() : 0 ;
    }
    return padding;
}


@implementation YBIBUtilities

@end
