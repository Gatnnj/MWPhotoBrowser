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

+ (NSData *)mwCompressImageForThumbnail:(UIImage *)image {
    if (![image isKindOfClass:[UIImage class]] || image.size.width <= 0 || image.size.height <= 0) {
        return nil;
    }

    // 根据像素尺寸缩放，避免高 scale UIImage 被误当成低分辨率图片。
    CGFloat sourceScale = image.scale > 0 ? image.scale : 1.0;
    CGFloat sourcePixelWidth = image.size.width * sourceScale;
    CGFloat sourcePixelHeight = image.size.height * sourceScale;
    CGFloat maxPixelDimension = 1280.0;
    CGFloat resizeRatio = MIN(1.0, maxPixelDimension / MAX(sourcePixelWidth, sourcePixelHeight));
    CGSize outputSize = CGSizeMake(MAX(1.0, round(image.size.width * sourceScale * resizeRatio)),
                                   MAX(1.0, round(image.size.height * sourceScale * resizeRatio)));

    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = 1.0;
    format.opaque = YES; // JPEG 无透明通道；透明区域以白色为底。
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:outputSize format:format];
    UIImage *thumbnail = [renderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull context) {
        [[UIColor whiteColor] setFill];
        [context fillRect:(CGRect){CGPointZero, outputSize}];
        [image drawInRect:(CGRect){CGPointZero, outputSize}];
    }];
    if (!thumbnail) {
        return nil;
    }

    // 在固定缩略图尺寸上搜索尽可能高且不超过约 300 KB 的 JPEG 质量，限制编码次数。
    const NSUInteger targetBytes = 300 * 1024;
    CGFloat lowQuality = 0.35;
    CGFloat highQuality = 0.82;
    NSData *bestData = UIImageJPEGRepresentation(thumbnail, lowQuality);
    if (!bestData) {
        return nil;
    }
    NSData *highData = UIImageJPEGRepresentation(thumbnail, highQuality);
    if (!highData) {
        return bestData;
    }
    if (highData.length <= targetBytes) {
        return highData;
    }

    for (NSUInteger attempt = 0; attempt < 6; attempt++) {
        CGFloat quality = (lowQuality + highQuality) / 2.0;
        NSData *candidate = UIImageJPEGRepresentation(thumbnail, quality);
        if (!candidate) {
            break;
        }
        if (candidate.length <= targetBytes) {
            bestData = candidate;
            lowQuality = quality;
        } else {
            highQuality = quality;
        }
    }
    return bestData;
}

+ (NSData *)mwCompressImage:(UIImage *)image withMask:(NSString *)maskName {
    
    double size;
    NSData *imageData = UIImageJPEGRepresentation(image, 1);
    
//    NSLog(@"Luban-iOS image data size before compressed == %f Kb",imageData.length/1024.0);
    
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

+ (NSData *)mwCompressImage:(UIImage *)image withCustomImage:(NSString *)imageName {
    
    if (imageName) {
        objc_setAssociatedObject(self, &isCustomImage, @(1), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        objc_setAssociatedObject(self, &customImageName, imageName, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return [self mwCompressImage:image withMask:nil];
}

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
//    NSLog(@"Luban-iOS image data size after compressed ==%f kb",imageData.length/1024.0);
    return imageData;
}

// specify the size
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
    // keep one decimal
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

- (UIImage *)fixOrientation {
    
    // No-op if the orientation is already correct
    if (self.imageOrientation == UIImageOrientationUp) return self;
    
    // We need to calculate the proper transformation to make the image upright.
    // We do it in 2 steps: Rotate if Left/Right/Down, and then flip if Mirrored.
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
    
    // Now we draw the underlying CGImage into a new context, applying the transform
    // calculated above.
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
            // Grr...
            CGContextDrawImage(ctx, CGRectMake(0,0,self.size.height,self.size.width), self.CGImage);
            break;
            
        default:
            CGContextDrawImage(ctx, CGRectMake(0,0,self.size.width,self.size.height), self.CGImage);
            break;
    }
    
    // And now we just create a new UIImage from the drawing context
    CGImageRef cgimg = CGBitmapContextCreateImage(ctx);
    UIImage *img = [UIImage imageWithCGImage:cgimg];
    CGContextRelease(ctx);
    CGImageRelease(cgimg);
    return img;
}

- (void) drawMaskWithString:(NSString *)str context:(CGContextRef)context radius:(CGFloat)radius angle:(CGFloat)angle colour:(UIColor *)colour font:(UIFont *)font slantAngle:(CGFloat)slantAngle size:(CGSize)size{
    // *******************************************************
    // This draws the String str centred at the position
    // specified by the polar coordinates (r, theta)
    // i.e. the x= r * cos(theta) y= r * sin(theta)
    // and rotated by the angle slantAngle
    // *******************************************************
    
    // Set the text attributes
    NSDictionary *attributes = @{NSForegroundColorAttributeName:colour,
                                            NSFontAttributeName:font};
    // Save the context
    CGContextSaveGState(context);
    // Undo the inversion of the Y-axis (or the text goes backwards!)
    CGContextScaleCTM(context, 1, -1);
    // Move the origin to the centre of the text (negating the y-axis manually)
    CGContextTranslateCTM(context, radius * cos(angle), -(radius * sin(angle)));
    // Rotate the coordinate system
    CGContextRotateCTM(context, -slantAngle);
    // Calculate the width of the text
    CGSize offset = [str sizeWithAttributes:attributes];
    // Move the origin by half the size of the text
    CGContextTranslateCTM (context, -offset.width / 2, -offset.height / 2); // Move the origin to the centre of the text (negating the y-axis manually)
    // Draw the text
    
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
    
    // Restore the context
    CGContextRestoreGState(context);
}

@end
