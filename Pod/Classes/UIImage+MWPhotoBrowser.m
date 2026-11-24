//
//  UIImage+MWPhotoBrowser.m
//  Pods
//
//  Created by Michael Waterfall on 05/07/2015.
//
//

#import "UIImage+MWPhotoBrowser.h"
#import <objc/runtime.h>
#import <CoreImage/CoreImage.h>
#import <math.h>

/// resource bundle 基础名，与 podspec 中 s.resource_bundles 的 key 保持一致
static NSString * const kMWResourceBundleName = @"MWPhotoBrowser";

@implementation UIImage (MWPhotoBrowser)

#pragma mark - Resource Bundle

+ (NSBundle *)mw_resourceBundle {
    static NSBundle *resourceBundle = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // bundle 名在不同集成方式下不一样，按优先级枚举：
        // 1. CocoaPods / 手写 XCFramework：MWPhotoBrowser.bundle
        // 2. CocoaPods 早期版本会带 pod 名前缀：MWPhotoBrowser-MWPhotoBrowser.bundle
        // 3. SwiftPM 生成的是 <Package>_<Target>.bundle
        NSArray<NSString *> *candidateNames = @[
            kMWResourceBundleName,
            [NSString stringWithFormat:@"%@-%@", kMWResourceBundleName, kMWResourceBundleName],
            [NSString stringWithFormat:@"%@_%@", kMWResourceBundleName, kMWResourceBundleName]
        ];

        // 宿主 bundle：动态 framework / XCFramework 在自身 bundle 内找到内嵌的 resource bundle；
        // 静态库（use_frameworks! 未开启）位于 app 根目录，即 mainBundle。
        Class ownerClass = NSClassFromString(@"MWPhotoBrowser");
        NSMutableArray<NSBundle *> *hostBundles = [NSMutableArray array];
        if (ownerClass) {
            [hostBundles addObject:[NSBundle bundleForClass:ownerClass]];
        }
        [hostBundles addObject:[NSBundle mainBundle]];

        for (NSBundle *host in hostBundles) {
            for (NSString *candidate in candidateNames) {
                NSString *path = [host pathForResource:candidate ofType:@"bundle"];
                if (path.length == 0) continue;
                NSBundle *found = [NSBundle bundleWithPath:path];
                if (found) {
                    resourceBundle = found;
                    return;
                }
            }
        }

        // 兜底：源码与 xcassets 被宿主 target 直接引用（资源编进宿主 Assets.car）
        resourceBundle = [NSBundle mainBundle];
    });
    return resourceBundle;
}

+ (UIImage *)mw_imageNamed:(NSString *)name {
    if (name.length == 0) return nil;

    NSBundle *bundle = [self mw_resourceBundle];
    UIImage *image = [UIImage imageNamed:name inBundle:bundle compatibleWithTraitCollection:nil];
    if (image) return image;

    // 资源 bundle 缺失时回退宿主 mainBundle，避免图标整体空白
    if (![bundle isEqual:[NSBundle mainBundle]]) {
        image = [UIImage imageNamed:name inBundle:[NSBundle mainBundle] compatibleWithTraitCollection:nil];
    }
    return image;
}

+ (UIImage *)imageForResourcePath:(NSString *)path ofType:(NSString *)type inBundle:(NSBundle *)bundle {
    if (path.length == 0) return nil;

    // 兼容历史写法 "MWPhotoBrowser.bundle/ImageError"：只取最后一段作为资源名
    NSString *name = [path lastPathComponent];

    // 调用方显式传入 bundle 时沿用其语义；传入 mainBundle（老代码传 bundleForClass 的典型结果）
    // 或未传时，统一走库自己的资源 bundle。
    NSBundle *searchBundle = bundle;
    if (!searchBundle || [searchBundle isEqual:[NSBundle mainBundle]]) {
        searchBundle = [self mw_resourceBundle];
    }

    UIImage *image = [UIImage imageNamed:name inBundle:searchBundle compatibleWithTraitCollection:nil];
    if (image) return image;

    // 资源目录里仍是散装文件（未进 Assets.car）时按文件名兜底
    if (type.length > 0) {
        NSString *filePath = [searchBundle pathForResource:name ofType:type];
        if (filePath.length > 0) {
            image = [UIImage imageWithContentsOfFile:filePath];
        }
    }
    return image ?: [self mw_imageNamed:name];
}

+ (UIImage *)clearImageWithSize:(CGSize)size {
    UIGraphicsBeginImageContextWithOptions(size, NO, [UIScreen mainScreen].scale);
    UIImage *blank = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return blank;
}

+ (UIImage *)gaussianBlurWithImage:(UIImage *)originalImage ofRadius:(CGFloat)radius {
    if (!originalImage || !isfinite(radius) || radius <= 0) return originalImage;
    CIImage *inputImage = [[CIImage alloc] initWithImage:originalImage];
    if (!inputImage) return originalImage;

    // CIContext 创建成本较高且可安全复用；滤镜对象仍按次创建，避免跨线程共享状态。
    static CIContext *context;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        context = [CIContext contextWithOptions:nil];
    });

    // 先用 CIAffineClamp 拉伸边缘，避免模糊黑边
    CIFilter *clampFilter = [CIFilter filterWithName:@"CIAffineClamp"];
    if (!clampFilter) return originalImage;
    [clampFilter setValue:inputImage forKey:kCIInputImageKey];
    CIImage *clampResult = clampFilter.outputImage;

    // 高斯模糊
    CIFilter *gaussianBlur = [CIFilter filterWithName:@"CIGaussianBlur"];
    if (!gaussianBlur) return originalImage;
    [gaussianBlur setValue:clampResult forKey:kCIInputImageKey];
    [gaussianBlur setValue:@(radius) forKey:kCIInputRadiusKey];
    CIImage *blurResult = gaussianBlur.outputImage;

    // 再裁剪到原图大小，避免无限大 extent 崩溃
    CIFilter *cropFilter = [CIFilter filterWithName:@"CICrop"];
    if (!cropFilter) return originalImage;
    [cropFilter setValue:blurResult forKey:kCIInputImageKey];
    [cropFilter setValue:[CIVector vectorWithCGRect:inputImage.extent] forKey:@"inputRectangle"];
    CIImage *croppedImage = cropFilter.outputImage;
    if (!croppedImage) return originalImage;

    // 渲染为 CGImage
    CGImageRef cgImage = [context createCGImage:croppedImage fromRect:inputImage.extent];
    if (!cgImage) return originalImage;

    UIImage *blurredImage = [UIImage imageWithCGImage:cgImage scale:originalImage.scale orientation:originalImage.imageOrientation];
    CGImageRelease(cgImage);
    
    return blurredImage;
}

static char isCustomImage;
static char customImageName;

+ (NSData *)mwCompressImage:(UIImage *)image {
    return [self mwCompressImage:image withMask:nil];
}

/// 鲁班式分级压缩：按宽高比与像素高度选缩放倍数和目标大小，再交给压缩方法
+ (NSData *)mwCompressImage:(UIImage *)image withMask:(NSString *)maskName {
    
    double size;
    NSData *imageData = UIImageJPEGRepresentation(image, 1);

    int fixelW = (int)image.size.width;
    int fixelH = (int)image.size.height;
    int thumbW = fixelW % 2  == 1 ? fixelW + 1 : fixelW;
    int thumbH = fixelH % 2  == 1 ? fixelH + 1 : fixelH;
    
    double scale = ((double)fixelW/fixelH);
    
    if (scale <= 1 && scale > 0.5625) {
        
        if (fixelH < 1664) {
            if (imageData.length/1024.0 < 150) {
                return imageData;
            }
            size = (fixelW * fixelH) / pow(1664, 2) * 150;
            size = size < 60 ? 60 : size;
        }
        else if (fixelH >= 1664 && fixelH < 4990) {
            thumbW = fixelW / 2;
            thumbH = fixelH / 2;
            size   = (thumbH * thumbW) / pow(2495, 2) * 300;
            size = size < 60 ? 60 : size;
        }
        else if (fixelH >= 4990 && fixelH < 10240) {
            thumbW = fixelW / 4;
            thumbH = fixelH / 4;
            size = (thumbW * thumbH) / pow(2560, 2) * 300;
            size = size < 100 ? 100 : size;
        }
        else {
            int multiple = fixelH / 1280 == 0 ? 1 : fixelH / 1280;
            thumbW = fixelW / multiple;
            thumbH = fixelH / multiple;
            size = (thumbW * thumbH) / pow(2560, 2) * 300;
            size = size < 100 ? 100 : size;
        }
    }
    else if (scale <= 0.5625 && scale > 0.5) {
        
        if (fixelH < 1280 && imageData.length/1024 < 200) {
            
            return imageData;
        }
        int multiple = fixelH / 1280 == 0 ? 1 : fixelH / 1280;
        thumbW = fixelW / multiple;
        thumbH = fixelH / multiple;
        size = (thumbW * thumbH) / (1440.0 * 2560.0) * 400;
        size = size < 100 ? 100 : size;
    }
    else {
        int multiple = (int)ceil(fixelH / (1280.0 / scale));
        thumbW = fixelW / multiple;
        thumbH = fixelH / multiple;
        size = ((thumbW * thumbH) / (1280.0 * (1280 / scale))) * 500;
        size = size < 100 ? 100 : size;
    }
    return [self compressWithImage:image thumbW:thumbW thumbH:thumbH size:size withMask:maskName];
}

/// 记录自定义图片水印名后走默认压缩流程
+ (NSData *)mwCompressImage:(UIImage *)image withCustomImage:(NSString *)imageName {
    
    if (imageName) {
        objc_setAssociatedObject(self, &isCustomImage, @(1), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self, &customImageName, imageName, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return [self mwCompressImage:image withMask:nil];
}

/// 先缩放叠水印，再从低质量逐步提升 JPEG 质量直到达到目标大小
+ (NSData *)compressWithImage:(UIImage *)image thumbW:(int)width thumbH:(int)height size:(double)size withMask:(NSString *)maskName {
    
    UIImage *thumbImage = [image fixOrientation];
    thumbImage = [thumbImage resizeImage:image thumbWidth:width thumbHeight:height withMask:maskName];
    
    float qualityCompress = 0.0;
    NSData *imageData = UIImageJPEGRepresentation(thumbImage, qualityCompress);
    
    NSUInteger lenght = imageData.length;
    while (lenght / 1024 > size && qualityCompress <= (1-0.06)) {
        
        qualityCompress     += 0.06 ;
        int intCommpress   = (int)(qualityCompress*100);
        qualityCompress    = intCommpress/100.0;
        imageData    = UIImageJPEGRepresentation(thumbImage, qualityCompress);
        lenght       = imageData.length;
        thumbImage   = [UIImage imageWithData:imageData];
    }
    return imageData;
}

/// 按目标尺寸等比缩放，并叠加文字或图片水印
- (UIImage *)resizeImage:(UIImage *)image thumbWidth:(int)width thumbHeight:(int)height withMask:(NSString *)maskName {
    
    int outW = (int)image.size.width;
    int outH = (int)image.size.height;
    
    int inSampleSize = 1;
    
    if (outW > width || outH > height) {
        int halfW = outW / 2;
        int halfH = outH / 2;
        
        while ((halfH / inSampleSize) > height && (halfW / inSampleSize) > width) {
            inSampleSize *= 2;
        }
    }
    // 按宽高比取较大者修正采样率（保留一位小数）
    int outWith  = (int)((outW / (float) width)*10);
    int outHeiht = (int)((outH / (float) height)*10);
    float heightRatio = outHeiht/10.0;
    float widthRatio  = outWith/10.0;

    if (heightRatio > 1 || widthRatio > 1) {

        inSampleSize = heightRatio > widthRatio ? heightRatio : widthRatio;
    }
    CGSize thumbSize = CGSizeMake((NSUInteger)((CGFloat)(outW/inSampleSize)), (NSUInteger)((CGFloat)(outH/inSampleSize)));
    
    UIGraphicsBeginImageContext(thumbSize);
    
    CGContextRef context = UIGraphicsGetCurrentContext();
    
    [image drawInRect:CGRectMake(0, 0, thumbSize.width, thumbSize.height)];
    if (maskName) {
        
        CGContextTranslateCTM (context, thumbSize.width / 2, thumbSize.height / 2);
        CGContextScaleCTM (context, 1, -1);
        
        [self drawMaskWithString:maskName context:context radius:0 angle:0 colour:[UIColor colorWithRed:1.0  green:1.0 blue:1.0 alpha:0.5] font:[UIFont systemFontOfSize:38.0] slantAngle:(CGFloat)(M_PI/6) size:thumbSize];
    }
    else {
        NSNumber *iscustom = objc_getAssociatedObject(self, &isCustomImage);
        BOOL      isCustom = [iscustom boolValue];
        if (isCustom) {
            NSString *imageName = objc_getAssociatedObject(self, &customImageName);
            UIImage *imageMask = [UIImage imageNamed:imageName];
            if (imageMask) {
                [imageMask drawInRect:CGRectMake(0, 0, thumbSize.width, thumbSize.height)];
            }
        }
    }
    UIImage *resultImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    objc_setAssociatedObject(self, &isCustomImage, @(NO), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
    return resultImage;
}

/// 把带方向元数据的图片转正为 Up；方向已正确则原样返回
- (UIImage *)fixOrientation {

    if (self.imageOrientation == UIImageOrientationUp) return self;

    // 先按方向旋转，再按需镜像，得到正立的变换矩阵
    CGAffineTransform transform = CGAffineTransformIdentity;
    
    switch (self.imageOrientation) {
        case UIImageOrientationDown:
        case UIImageOrientationDownMirrored:
            transform = CGAffineTransformTranslate(transform, self.size.width, self.size.height);
            transform = CGAffineTransformRotate(transform, M_PI);
            break;
            
        case UIImageOrientationLeft:
        case UIImageOrientationLeftMirrored:
            transform = CGAffineTransformTranslate(transform, self.size.width, 0);
            transform = CGAffineTransformRotate(transform, M_PI_2);
            break;
            
        case UIImageOrientationRight:
        case UIImageOrientationRightMirrored:
            transform = CGAffineTransformTranslate(transform, 0, self.size.height);
            transform = CGAffineTransformRotate(transform, -M_PI_2);
            break;
        case UIImageOrientationUp:
        case UIImageOrientationUpMirrored:
            break;
    }
    
    switch (self.imageOrientation) {
        case UIImageOrientationUpMirrored:
        case UIImageOrientationDownMirrored:
            transform = CGAffineTransformTranslate(transform, self.size.width, 0);
            transform = CGAffineTransformScale(transform, -1, 1);
            break;
            
        case UIImageOrientationLeftMirrored:
        case UIImageOrientationRightMirrored:
            transform = CGAffineTransformTranslate(transform, self.size.height, 0);
            transform = CGAffineTransformScale(transform, -1, 1);
            break;
        case UIImageOrientationUp:
        case UIImageOrientationDown:
        case UIImageOrientationLeft:
        case UIImageOrientationRight:
            break;
    }
    
    // 把 CGImage 按变换画进新位图上下文
    CGContextRef ctx = CGBitmapContextCreate(NULL, self.size.width, self.size.height,
                                             CGImageGetBitsPerComponent(self.CGImage), 0,
                                             CGImageGetColorSpace(self.CGImage),
                                             CGImageGetBitmapInfo(self.CGImage));
    CGContextConcatCTM(ctx, transform);
    switch (self.imageOrientation) {
        case UIImageOrientationLeft:
        case UIImageOrientationLeftMirrored:
        case UIImageOrientationRight:
        case UIImageOrientationRightMirrored:
            CGContextDrawImage(ctx, CGRectMake(0,0,self.size.height,self.size.width), self.CGImage);
            break;
            
        default:
            CGContextDrawImage(ctx, CGRectMake(0,0,self.size.width,self.size.height), self.CGImage);
            break;
    }
    
    // 从位图上下文生成新 UIImage
    CGImageRef cgimg = CGBitmapContextCreateImage(ctx);
    UIImage *img = [UIImage imageWithCGImage:cgimg];
    CGContextRelease(ctx);
    CGImageRelease(cgimg);
    return img;
}

/// 按错位网格平铺绘制斜向文字水印
- (void) drawMaskWithString:(NSString *)str context:(CGContextRef)context radius:(CGFloat)radius angle:(CGFloat)angle colour:(UIColor *)colour font:(UIFont *)font slantAngle:(CGFloat)slantAngle size:(CGSize)size{

    // 文字属性与上下文状态
    NSDictionary *attributes = @{NSForegroundColorAttributeName:colour,
                                            NSFontAttributeName:font};
    CGContextSaveGState(context);
    // 翻转 Y 轴并把原点移到文字中心，再旋转坐标系
    CGContextScaleCTM(context, 1, -1);
    CGContextTranslateCTM(context, radius * cos(angle), -(radius * sin(angle)));
    CGContextRotateCTM(context, -slantAngle);
    CGSize offset = [str sizeWithAttributes:attributes];
    CGContextTranslateCTM (context, -offset.width / 2, -offset.height / 2);
    
    NSInteger width  = ceil(cos(slantAngle)*offset.width);
    NSInteger height = ceil(sin(slantAngle)*offset.width);
    
    NSInteger row    = size.height/(height+100.0);
    NSInteger coloum = size.width/(width+100.0)>6?:6;
    CGFloat xPoint   = 0;
    CGFloat yPoint   = 0;
    for (NSInteger index = 0; index < row*coloum; index++) {
        
        // 以当前输出图尺寸（size）为错位基准。原先取 [UIScreen mainScreen].bounds，
        // 在 iPad 分屏、Stage Manager、外接屏等场景下拿到的是整屏尺寸而非本次绘制区域，
        // 会导致水印平铺错位。
        xPoint = (index%coloum) *(width+100.0)-size.width;
        yPoint = (index/coloum) *(height+100.0);
        [str drawAtPoint:CGPointMake(xPoint, yPoint) withAttributes:attributes];
        xPoint -= size.width;
        yPoint -= size.height;
        [str drawAtPoint:CGPointMake(xPoint, yPoint) withAttributes:attributes];
    }
    
    // 恢复上下文状态
    CGContextRestoreGState(context);
}

@end
