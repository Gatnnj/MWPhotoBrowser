//
//  MWPhotoImageCache.m
//  MWPhotoBrowser
//
#import "MWPhotoImageCache.h"
#import <CommonCrypto/CommonDigest.h>
#import <QuartzCore/QuartzCore.h>

dispatch_queue_t MWPhotoBlurQueue(void) {
    static dispatch_queue_t queue;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        queue = dispatch_queue_create("com.mwphotobrowser.image-blur", DISPATCH_QUEUE_SERIAL);
    });
    return queue;
}

/// 模糊图缓存目录。
static NSString *MWPhotoImageCacheDirectory(void) {
    static NSString *directory;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
        NSString *caches = paths.firstObject;
        directory = [[caches stringByAppendingPathComponent:@"MWPhotoBrowserImageCache"] copy];

        // 旧实现分别使用 MWPhotoBrowserBlurCache / MWPhotoBrowserZoomCache 两个目录，
        // 这里一次性清理，避免遗留数据继续占用空间（两者都是可重建的缓存）
        NSFileManager *fileManager = [NSFileManager defaultManager];
        for (NSString *legacyName in @[@"MWPhotoBrowserBlurCache", @"MWPhotoBrowserZoomCache"]) {
            NSString *legacyPath = [caches stringByAppendingPathComponent:legacyName];
            if ([fileManager fileExistsAtPath:legacyPath]) {
                [fileManager removeItemAtPath:legacyPath error:nil];
            }
        }
    });
    return directory;
}

static NSString *MWPhotoBlurCacheDirectory(void) {
    return MWPhotoImageCacheDirectory();
}

/// 只取 URL 路径作为缓存键，忽略可能含轮换凭证的 query 参数
static NSString *MWPhotoCanonicalBlurCacheURL(NSURL *url) {
    if (!url) return nil;
    return [url.absoluteString componentsSeparatedByString:@"?"].firstObject;
}

static NSString *MWPhotoBlurCachePrefix(NSURL *url) {
    if (!url) return nil;
    NSData *data = [MWPhotoCanonicalBlurCacheURL(url) dataUsingEncoding:NSUTF8StringEncoding];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", digest[i]];
    return hex;
}

NSString *MWPhotoBlurCachePath(NSURL *url, CGFloat radius) {
    NSString *prefix = MWPhotoBlurCachePrefix(url);
    if (!prefix) return nil;
    NSString *radiusKey = [NSString stringWithFormat:@"%.3f", radius];
    // blur_ 前缀用于标记生成的模糊图缓存。
    return [[MWPhotoBlurCacheDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"blur_%@_%@.jpg", prefix, radiusKey]] copy];
}

/// 读取模糊缓存图，并按配套 plist 恢复 scale 与方向
UIImage *MWPhotoReadBlurCache(NSString *path) {
    UIImage *decoded = [UIImage imageWithContentsOfFile:path];
    if (!decoded.CGImage) return nil;
    NSDictionary *metadata = [NSDictionary dictionaryWithContentsOfFile:[path stringByAppendingPathExtension:@"plist"]];
    CGFloat scale = [metadata[@"scale"] doubleValue];
    UIImageOrientation orientation = metadata ? [metadata[@"orientation"] integerValue] : decoded.imageOrientation;
    if (scale <= 0) scale = decoded.scale;
    return [UIImage imageWithCGImage:decoded.CGImage scale:scale orientation:orientation];
}

#pragma mark - Cache Size Control

/// 缓存目录总容量上限
static const unsigned long long MWPhotoImageCacheLimitBytes = 400ULL * 1024ULL * 1024ULL;
/// 淘汰目标：删除到上限的 70%，避免每次写入都触发一轮删除
static const double MWPhotoImageCacheTrimRatio = 0.7;
/// 两次容量检查之间的最小间隔（秒）
static const CFTimeInterval MWPhotoImageCacheCheckInterval = 60.0;
/// 单次最多删除的文件数，避免长时间占用串行队列
static const NSUInteger MWPhotoImageCacheMaxDeletionsPerPass = 200;

static BOOL MWPhotoCacheFileIsBlurJPEG(NSString *fileName) {
    return [fileName hasPrefix:@"blur_"] && [fileName hasSuffix:@".jpg"];
}

/// 目录总大小超过上限时，按修改时间从旧到新删除，直到降到目标容量。
/// 内部派发到模糊缓存所用的串行队列，与写入、清理操作保持顺序一致。
static void MWPhotoEnforceImageCacheLimitIfNeeded(void) {
    dispatch_async(MWPhotoBlurQueue(), ^{
        // 节流：避免每写一张图都全量扫描一次目录
        static CFTimeInterval lastCheck = 0;
        CFTimeInterval now = CFAbsoluteTimeGetCurrent();
        if (lastCheck > 0 && (now - lastCheck) < MWPhotoImageCacheCheckInterval) {
            return;
        }
        lastCheck = now;

        NSString *directory = MWPhotoImageCacheDirectory();
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSArray<NSString *> *fileNames = [fileManager contentsOfDirectoryAtPath:directory error:nil];
        if (!fileNames.count) return;

        unsigned long long totalBytes = 0;
        NSMutableArray<NSDictionary *> *entries = [NSMutableArray arrayWithCapacity:fileNames.count];
        for (NSString *fileName in fileNames) {
            NSString *path = [directory stringByAppendingPathComponent:fileName];
            NSDictionary *attributes = [fileManager attributesOfItemAtPath:path error:nil];
            if (!attributes) continue;
            unsigned long long size = [attributes[NSFileSize] unsignedLongLongValue];
            totalBytes += size;
            [entries addObject:@{
                @"path": path,
                @"size": @(size),
                @"date": attributes[NSFileModificationDate] ?: [NSDate distantPast],
                @"name": fileName
            }];
        }
        if (totalBytes <= MWPhotoImageCacheLimitBytes) return;

        // 修改时间升序：最旧的排在前面，优先删除
        [entries sortUsingComparator:^NSComparisonResult(NSDictionary *lhs, NSDictionary *rhs) {
            return [lhs[@"date"] compare:rhs[@"date"]];
        }];

        unsigned long long targetBytes = (unsigned long long)(MWPhotoImageCacheLimitBytes * MWPhotoImageCacheTrimRatio);
        unsigned long long removedBytes = 0;
        NSUInteger removedCount = 0;
        for (NSDictionary *entry in entries) {
            if (totalBytes - removedBytes <= targetBytes) break;
            if (removedCount >= MWPhotoImageCacheMaxDeletionsPerPass) break;

            NSString *path = entry[@"path"];
            // 删除模糊图 JPEG 时同步清理配套的 .plist，避免产生孤儿文件
            if (MWPhotoCacheFileIsBlurJPEG(entry[@"name"])) {
                [fileManager removeItemAtPath:[path stringByAppendingPathExtension:@"plist"] error:nil];
            }
            if ([fileManager removeItemAtPath:path error:nil]) {
                removedBytes += [entry[@"size"] unsignedLongLongValue];
                removedCount++;
            }
        }
    });
}

/// 写入模糊图 JPEG 与配套元数据 plist，并触发容量淘汰
void MWPhotoWriteBlurCache(UIImage *image, NSString *path) {
    if (!image || !path) return;
    NSString *directory = [path stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
    NSData *data = UIImageJPEGRepresentation(image, 0.94);
    if (!data || ![data writeToFile:path options:NSDataWritingAtomic error:nil]) return;
    NSDictionary *metadata = @{@"scale": @(image.scale), @"orientation": @(image.imageOrientation)};
    [metadata writeToFile:[path stringByAppendingPathExtension:@"plist"] atomically:YES];
    MWPhotoEnforceImageCacheLimitIfNeeded();
}


void MWPhotoClearBlurCache(void (^completion)(void)) {
    dispatch_async(MWPhotoBlurQueue(), ^{
        NSString *directory = MWPhotoImageCacheDirectory();
        NSFileManager *fileManager = [NSFileManager defaultManager];
        for (NSString *fileName in [fileManager contentsOfDirectoryAtPath:directory error:nil]) {
            if ([fileName hasPrefix:@"blur_"]) {
                [fileManager removeItemAtPath:[directory stringByAppendingPathComponent:fileName] error:nil];
            }
        }
        if (completion) dispatch_async(dispatch_get_main_queue(), completion);
    });
}

void MWPhotoClearBlurCacheForURL(NSURL *url, void (^completion)(void)) {
    NSString *prefix = MWPhotoBlurCachePrefix(url);
    if (!prefix) {
        if (completion) dispatch_async(dispatch_get_main_queue(), completion);
        return;
    }
    dispatch_async(MWPhotoBlurQueue(), ^{
        NSString *directory = MWPhotoBlurCacheDirectory();
        NSArray *files = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:directory error:nil];
        NSString *filePrefix = [NSString stringWithFormat:@"blur_%@_", prefix];
        for (NSString *file in files) {
            if ([file hasPrefix:filePrefix]) {
                [[NSFileManager defaultManager] removeItemAtPath:[directory stringByAppendingPathComponent:file] error:nil];
            }
        }
        if (completion) dispatch_async(dispatch_get_main_queue(), completion);
    });
}
