#import "FFConversionEngine.h"
#import <ImageIO/ImageIO.h>
#import <PDFKit/PDFKit.h>

static NSString * const FFErrorDomain = @"com.tracy.formatfactory";

static NSError *FFMakeError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:FFErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

@implementation FFCropSpec

+ (instancetype)fullCrop {
    return [self cropWithX:0 y:0 width:1 height:1];
}

+ (instancetype)cropWithX:(double)x y:(double)y width:(double)width height:(double)height {
    FFCropSpec *crop = [FFCropSpec new];
    crop.x = x;
    crop.y = y;
    crop.width = width;
    crop.height = height;
    return crop;
}

- (id)copyWithZone:(NSZone *)zone {
    return [FFCropSpec cropWithX:self.x y:self.y width:self.width height:self.height];
}

- (FFCropSpec *)clamped {
    double x = fmin(fmax(self.x, 0), 1);
    double y = fmin(fmax(self.y, 0), 1);
    double width = fmin(fmax(self.width, 0.001), 1 - x);
    double height = fmin(fmax(self.height, 0.001), 1 - y);
    return [FFCropSpec cropWithX:x y:y width:width height:height];
}

@end

@implementation FFConversionRequest
- (instancetype)init {
    self = [super init];
    if (self) {
        _identifier = [NSUUID UUID];
        _jpegQuality = 0.9;
        _pdfDPI = 200;
        _outputFormat = FFOutputFormatJPEG;
    }
    return self;
}
@end

@implementation FFConversionResult
@end

@implementation FFConversionEngine

+ (FFSourceKind)sourceKindForURL:(NSURL *)url {
    NSString *extension = url.pathExtension.lowercaseString;
    if ([extension isEqualToString:@"heic"] || [extension isEqualToString:@"heif"]) return FFSourceKindHEIC;
    if ([extension isEqualToString:@"jpg"] || [extension isEqualToString:@"jpeg"]) return FFSourceKindJPEG;
    if ([extension isEqualToString:@"png"]) return FFSourceKindPNG;
    if ([extension isEqualToString:@"pdf"]) return FFSourceKindPDF;
    return FFSourceKindUnsupported;
}

+ (NSString *)displayNameForSourceKind:(FFSourceKind)kind {
    switch (kind) {
        case FFSourceKindHEIC: return @"HEIC";
        case FFSourceKindJPEG: return @"JPG";
        case FFSourceKindPNG: return @"PNG";
        case FFSourceKindPDF: return @"PDF";
        default: return @"不支持";
    }
}

+ (NSURL *)defaultOutputDirectoryForInputURL:(NSURL *)inputURL {
    return inputURL.URLByDeletingLastPathComponent;
}

+ (NSURL *)resultFolderOutputDirectoryForInputURL:(NSURL *)inputURL {
    return [[self defaultOutputDirectoryForInputURL:inputURL]
        URLByAppendingPathComponent:@"转换结果" isDirectory:YES];
}

+ (CGImageRef)newPreviewImageForURL:(NSURL *)url
                       maxPixelSize:(NSInteger)maxPixelSize
                              error:(NSError **)error {
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (!source) {
        if (error) *error = FFMakeError(100, @"图片损坏或无法读取");
        return NULL;
    }
    NSDictionary *options = @{
        (__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
        (__bridge NSString *)kCGImageSourceCreateThumbnailWithTransform: @YES,
        (__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize: @(MAX(256, maxPixelSize)),
        (__bridge NSString *)kCGImageSourceShouldCacheImmediately: @YES
    };
    CGImageRef thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)options);
    CFRelease(source);
    if (!thumbnail && error) *error = FFMakeError(101, @"无法生成图片预览");
    return thumbnail;
}

+ (CGImageRef)newOrientedImageForURL:(NSURL *)url error:(NSError **)error CF_RETURNS_RETAINED {
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (!source) {
        if (error) *error = FFMakeError(110, @"图片损坏或无法读取");
        return NULL;
    }
    NSDictionary *properties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL));
    NSInteger width = [properties[(__bridge NSString *)kCGImagePropertyPixelWidth] integerValue];
    NSInteger height = [properties[(__bridge NSString *)kCGImagePropertyPixelHeight] integerValue];
    NSInteger maxPixel = MAX(width, height);
    NSDictionary *decodeOptions = @{
        (__bridge NSString *)kCGImageSourceCreateThumbnailFromImageAlways: @YES,
        (__bridge NSString *)kCGImageSourceCreateThumbnailWithTransform: @YES,
        (__bridge NSString *)kCGImageSourceThumbnailMaxPixelSize: @(MAX(maxPixel, 1)),
        (__bridge NSString *)kCGImageSourceShouldCacheImmediately: @YES
    };
    CGImageRef result = CGImageSourceCreateThumbnailAtIndex(source, 0, (__bridge CFDictionaryRef)decodeOptions);
    CFRelease(source);
    if (!result && error) *error = FFMakeError(112, @"无法生成方向正确的图片");
    return result;
}

+ (CGImageRef)newImageByCropping:(CGImageRef)image
                            crop:(FFCropSpec *)crop
                           error:(NSError **)error CF_RETURNS_RETAINED {
    FFCropSpec *safe = crop.clamped;
    CGFloat width = CGImageGetWidth(image);
    CGFloat height = CGImageGetHeight(image);
    CGRect rect = CGRectMake(safe.x * width,
                             safe.y * height,
                             safe.width * width,
                             safe.height * height);
    rect = CGRectIntersection(CGRectIntegral(rect), CGRectMake(0, 0, width, height));
    if (rect.size.width < 1 || rect.size.height < 1) {
        if (error) *error = FFMakeError(120, @"裁切范围无效");
        return NULL;
    }
    CGImageRef result = CGImageCreateWithImageInRect(image, rect);
    if (!result && error) *error = FFMakeError(121, @"裁切图片失败");
    return result;
}

+ (NSURL *)uniqueURLInDirectory:(NSURL *)directory baseName:(NSString *)base extension:(NSString *)extension {
    static NSMutableSet<NSString *> *reserved;
    static NSObject *lock;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        reserved = [NSMutableSet set];
        lock = [NSObject new];
    });
    @synchronized (lock) {
        NSFileManager *manager = NSFileManager.defaultManager;
        NSInteger suffix = 1;
        while (YES) {
            NSString *name = suffix == 1 ? base : [NSString stringWithFormat:@"%@_%ld", base, (long)suffix];
            NSURL *candidate = [[directory URLByAppendingPathComponent:name] URLByAppendingPathExtension:extension];
            NSString *path = candidate.standardizedURL.path;
            if (![manager fileExistsAtPath:path] && ![reserved containsObject:path]) {
                [reserved addObject:path];
                return candidate;
            }
            suffix += 1;
        }
    }
}

+ (void)releaseReservationForURL:(NSURL *)url {
    static NSObject *releaseLock;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ releaseLock = [NSObject new]; });
    // Reservations are intentionally retained for this short-lived app session.
    // This prevents a failed concurrent job from racing another job to the same path.
    (void)releaseLock;
    (void)url;
}

+ (CGImageRef)newNormalizedImage:(CGImageRef)image opaque:(BOOL)opaque error:(NSError **)error CF_RETURNS_RETAINED {
    size_t width = CGImageGetWidth(image);
    size_t height = CGImageGetHeight(image);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGBitmapInfo bitmapInfo = opaque ? (CGBitmapInfo)kCGImageAlphaNoneSkipLast : (CGBitmapInfo)kCGImageAlphaPremultipliedLast;
    CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, 0, space, bitmapInfo);
    CGColorSpaceRelease(space);
    if (!context) {
        if (error) *error = FFMakeError(130, @"无法创建标准图片画布");
        return NULL;
    }
    if (opaque) {
        CGContextSetRGBFillColor(context, 1, 1, 1, 1);
        CGContextFillRect(context, CGRectMake(0, 0, width, height));
    } else {
        CGContextClearRect(context, CGRectMake(0, 0, width, height));
    }
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
    CGImageRef result = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    return result;
}

+ (BOOL)encodeImage:(CGImageRef)image
               toURL:(NSURL *)url
              format:(FFOutputFormat)format
             quality:(double)quality
               error:(NSError **)error {
    CGImageRef normalized = [self newNormalizedImage:image opaque:(format == FFOutputFormatJPEG) error:error];
    if (!normalized) return NO;

    CFStringRef type = format == FFOutputFormatJPEG ? CFSTR("public.jpeg") : CFSTR("public.png");
    CGImageDestinationRef destination = CGImageDestinationCreateWithURL((__bridge CFURLRef)url, type, 1, NULL);
    if (!destination) {
        CFRelease(normalized);
        if (error) *error = FFMakeError(140, [NSString stringWithFormat:@"无法写入：%@", url.path]);
        return NO;
    }
    NSMutableDictionary *properties = [@{(__bridge NSString *)kCGImagePropertyOrientation: @1} mutableCopy];
    if (format == FFOutputFormatJPEG) {
        properties[(__bridge NSString *)kCGImageDestinationLossyCompressionQuality] = @(fmin(fmax(quality, 0.6), 1.0));
    }
    CGImageDestinationAddImage(destination, normalized, (__bridge CFDictionaryRef)properties);
    BOOL success = CGImageDestinationFinalize(destination);
    CFRelease(destination);
    CFRelease(normalized);
    if (!success) {
        [NSFileManager.defaultManager removeItemAtURL:url error:nil];
        if (error) *error = FFMakeError(141, @"图片编码失败");
    }
    return success;
}

+ (NSArray<NSURL *> *)convertPDFRequest:(FFConversionRequest *)request error:(NSError **)error {
    PDFDocument *document = [[PDFDocument alloc] initWithURL:request.inputURL];
    if (!document) {
        if (error) *error = FFMakeError(150, @"PDF 损坏或无法读取");
        return nil;
    }
    if ([document isLocked]) {
        if (error) *error = FFMakeError(151, @"PDF 已加密，暂不支持转换");
        return nil;
    }
    if (document.pageCount == 0) {
        if (error) *error = FFMakeError(152, @"PDF 没有可转换的页面");
        return nil;
    }

    NSString *base = request.inputURL.URLByDeletingPathExtension.lastPathComponent;
    NSInteger digits = MAX(3, [@(document.pageCount).stringValue length]);
    NSMutableArray<NSURL *> *outputs = [NSMutableArray arrayWithCapacity:document.pageCount];
    CGFloat scale = request.pdfDPI / 72.0;

    for (NSInteger index = 0; index < document.pageCount; index++) {
        @autoreleasepool {
            PDFPage *page = [document pageAtIndex:index];
            if (!page) {
                if (error) *error = FFMakeError(153, [NSString stringWithFormat:@"PDF 第 %ld 页无法读取", (long)index + 1]);
                return nil;
            }
            CGPDFPageRef pageRef = page.pageRef;
            if (!pageRef) {
                if (error) *error = FFMakeError(153, [NSString stringWithFormat:@"PDF 第 %ld 页无法读取", (long)index + 1]);
                return nil;
            }
            CGRect pageBox = CGPDFPageGetBoxRect(pageRef, kCGPDFMediaBox);
            NSInteger rotation = CGPDFPageGetRotationAngle(pageRef) % 360;
            if (rotation < 0) rotation += 360;
            BOOL swapsDimensions = rotation == 90 || rotation == 270;
            CGFloat displayedWidth = swapsDimensions ? pageBox.size.height : pageBox.size.width;
            CGFloat displayedHeight = swapsDimensions ? pageBox.size.width : pageBox.size.height;
            size_t width = MAX(1, (size_t)ceil(displayedWidth * scale));
            size_t height = MAX(1, (size_t)ceil(displayedHeight * scale));
            CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
            CGContextRef bitmap = CGBitmapContextCreate(NULL, width, height, 8, 0, space, (CGBitmapInfo)kCGImageAlphaNoneSkipLast);
            CGColorSpaceRelease(space);
            if (!bitmap) {
                if (error) *error = FFMakeError(154, [NSString stringWithFormat:@"PDF 第 %ld 页渲染失败", (long)index + 1]);
                return nil;
            }
            CGContextSetRGBFillColor(bitmap, 1, 1, 1, 1);
            CGContextFillRect(bitmap, CGRectMake(0, 0, width, height));
            CGContextSaveGState(bitmap);
            CGContextScaleCTM(bitmap, scale, scale);
            CGRect destinationRect = CGRectMake(0, 0, displayedWidth, displayedHeight);
            CGAffineTransform pageTransform = CGPDFPageGetDrawingTransform(
                pageRef,
                kCGPDFMediaBox,
                destinationRect,
                0,
                true
            );
            CGContextConcatCTM(bitmap, pageTransform);
            CGContextDrawPDFPage(bitmap, pageRef);
            CGContextRestoreGState(bitmap);
            CGImageRef image = CGBitmapContextCreateImage(bitmap);
            CGContextRelease(bitmap);
            if (!image) {
                if (error) *error = FFMakeError(155, [NSString stringWithFormat:@"PDF 第 %ld 页渲染失败", (long)index + 1]);
                return nil;
            }

            NSString *pageNumber = [NSString stringWithFormat:@"%0*ld", (int)digits, (long)index + 1];
            NSString *pageBase = [NSString stringWithFormat:@"%@_%@", base, pageNumber];
            NSURL *destination = [self uniqueURLInDirectory:request.outputDirectory baseName:pageBase extension:@"jpg"];
            BOOL success = [self encodeImage:image toURL:destination format:FFOutputFormatJPEG quality:request.jpegQuality error:error];
            CFRelease(image);
            if (!success) return nil;
            [outputs addObject:destination];
        }
    }
    return outputs;
}

+ (FFConversionResult *)convertRequest:(FFConversionRequest *)request error:(NSError **)error {
    if (request.sourceKind == FFSourceKindUnsupported) {
        if (error) *error = FFMakeError(160, @"不支持的文件格式");
        return nil;
    }
    NSError *directoryError = nil;
    [NSFileManager.defaultManager createDirectoryAtURL:request.outputDirectory
                           withIntermediateDirectories:YES
                                            attributes:nil
                                                 error:&directoryError];
    if (directoryError) {
        if (error) *error = FFMakeError(161, [NSString stringWithFormat:@"无法创建输出目录：%@", request.outputDirectory.path]);
        return nil;
    }

    NSArray<NSURL *> *outputs;
    if (request.sourceKind == FFSourceKindPDF) {
        outputs = [self convertPDFRequest:request error:error];
        if (!outputs) return nil;
    } else {
        CGImageRef image = [self newOrientedImageForURL:request.inputURL error:error];
        if (!image) return nil;
        CGImageRef finalImage = image;
        if (request.crop && !(request.crop.x == 0 && request.crop.y == 0 && request.crop.width == 1 && request.crop.height == 1)) {
            finalImage = [self newImageByCropping:image crop:request.crop error:error];
            CFRelease(image);
            if (!finalImage) return nil;
        }
        NSString *base = request.inputURL.URLByDeletingPathExtension.lastPathComponent;
        NSString *extension = request.outputFormat == FFOutputFormatJPEG ? @"jpg" : @"png";
        NSURL *destination = [self uniqueURLInDirectory:request.outputDirectory baseName:base extension:extension];
        BOOL success = [self encodeImage:finalImage toURL:destination format:request.outputFormat quality:request.jpegQuality error:error];
        CFRelease(finalImage);
        if (!success) return nil;
        outputs = @[destination];
    }

    FFConversionResult *result = [FFConversionResult new];
    result.identifier = request.identifier;
    result.outputURLs = outputs;
    return result;
}

@end
