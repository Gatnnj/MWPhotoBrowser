//
//  UIImage+MWPhotoBrowser.h
//  Pods
//
//  Created by Michael Waterfall on 05/07/2015.
//
//

#import <Foundation/Foundation.h>

@interface UIImage (MWPhotoBrowser)

+ (UIImage *)imageForResourcePath:(NSString *)path ofType:(NSString *)type inBundle:(NSBundle *)bundle;
+ (UIImage *)clearImageWithSize:(CGSize)size;
+ (UIImage *)gaussianBlurWithImage:(UIImage *)originalImage ofRadius:(CGFloat)radius;


/// 压缩图片
+ (NSData *)mwCompressImage:(UIImage *)image;

/// @maskName 水印名
+ (NSData *)mwCompressImage:(UIImage *)image withMask:(NSString *)maskName;

/// @imageName 自定义图片水印 图片名
+ (NSData *)mwCompressImage:(UIImage *)image withCustomImage:(NSString *)imageName;

@end
