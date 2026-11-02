//
//  MWPreprocessor.h
//  MWPhotoBrowser
//
//  Created by Michael Waterfall on 01/10/2013.
//
//  系统版本判断工具。
//  旧实现基于已废弃的 [UIDevice systemVersion]（iOS 15 废弃），
//  现改为基于 NSProcessInfo 的 operatingSystemVersion 进行比较，
//  宏名与参数格式（形如 @"15.2"）保持不变，便于原有调用点无缝替换。

#import <Foundation/Foundation.h>

/// 将形如 @"15.2.1" 的版本字符串与当前系统版本进行比较
/// @param version 目标版本字符串，缺省的版本段按 0 处理
/// @return 系统版本高于目标版本返回 NSOrderedDescending，相等返回 NSOrderedSame，低于返回 NSOrderedAscending
static inline NSComparisonResult MWCompareSystemVersion(NSString *version) {

    // 当前系统的三段式版本号
    NSOperatingSystemVersion current = NSProcessInfo.processInfo.operatingSystemVersion;
    NSInteger currentParts[3] = {
        current.majorVersion,
        current.minorVersion,
        current.patchVersion
    };

    // 解析目标版本字符串，最多取主、次、补丁三段
    NSArray<NSString *> *parts = [version componentsSeparatedByString:@"."];
    NSInteger targetParts[3] = {0, 0, 0};
    for (NSUInteger i = 0; i < parts.count && i < 3; i++) {
        targetParts[i] = parts[i].integerValue;
    }

    // 从主版本开始逐段比较，第一段不同即得出结论
    for (NSUInteger i = 0; i < 3; i++) {
        if (currentParts[i] > targetParts[i]) return NSOrderedDescending;
        if (currentParts[i] < targetParts[i]) return NSOrderedAscending;
    }
    return NSOrderedSame;
}

/// 系统版本是否等于指定版本
#define SYSTEM_VERSION_EQUAL_TO(v)                  (MWCompareSystemVersion(v) == NSOrderedSame)
/// 系统版本是否高于指定版本
#define SYSTEM_VERSION_GREATER_THAN(v)              (MWCompareSystemVersion(v) == NSOrderedDescending)
/// 系统版本是否高于或等于指定版本
#define SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(v)  (MWCompareSystemVersion(v) != NSOrderedAscending)
/// 系统版本是否低于指定版本
#define SYSTEM_VERSION_LESS_THAN(v)                 (MWCompareSystemVersion(v) == NSOrderedAscending)
/// 系统版本是否低于或等于指定版本
#define SYSTEM_VERSION_LESS_THAN_OR_EQUAL_TO(v)     (MWCompareSystemVersion(v) != NSOrderedDescending)
