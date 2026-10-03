#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>
#import <PDFKit/PDFKit.h>
#import "FFConversionEngine.h"

static NSInteger failures = 0;

static void FFCheck(BOOL condition, NSString *message) {
    if (condition) {
        printf("PASS  %s\n", message.UTF8String);
    } else {
        fprintf(stderr, "FAIL  %s\n", message.UTF8String);
        failures += 1;
    }
}

static CGImageRef FFCreateImage(size_t width, size_t height) CF_RETURNS_RETAINED {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, width, height, 8, 0, space, (CGBitmapInfo)kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    CGContextSetRGBFillColor(context, 0.12, 0.44, 0.88, 1);
    CGContextFillRect(context, CGRectMake(0, 0, width, height));
    CGContextSetRGBFillColor(context, 0.95, 0.3, 0.18, 1);
    CGContextFillRect(context, CGRectMake(0, 0, width / 2.0, height / 2.0));
    CGImageRef image = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    return image;
}

static BOOL FFWriteImage(CGImageRef image, NSURL *url, CFStringRef type, NSInteger orientation) {
    CGImageDestinationRef destination = CGImageDestinationCreateWithURL((__bridge CFURLRef)url, type, 1, NULL);
    if (!destination) return NO;
    NSMutableDictionary *properties = [NSMutableDictionary dictionary];
    if (orientation > 0) properties[(__bridge NSString *)kCGImagePropertyOrientation] = @(orientation);
    if ([(__bridge NSString *)type isEqualToString:@"public.jpeg"] || [(__bridge NSString *)type isEqualToString:@"public.heic"]) {
        properties[(__bridge NSString *)kCGImageDestinationLossyCompressionQuality] = @0.92;
    }
    CGImageDestinationAddImage(destination, image, (__bridge CFDictionaryRef)properties);
    BOOL result = CGImageDestinationFinalize(destination);
    CFRelease(destination);
    return result;
}

static CGSize FFPixelSize(NSURL *url) {
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (!source) return CGSizeZero;
    NSDictionary *properties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL));
    CFRelease(source);
    return CGSizeMake([properties[(__bridge NSString *)kCGImagePropertyPixelWidth] doubleValue],
                      [properties[(__bridge NSString *)kCGImagePropertyPixelHeight] doubleValue]);
}

static CGSize FFExpectedOrientedSize(NSURL *url) {
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (!source) return CGSizeZero;
    NSDictionary *properties = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, NULL));
    CFRelease(source);
    CGFloat width = [properties[(__bridge NSString *)kCGImagePropertyPixelWidth] doubleValue];
    CGFloat height = [properties[(__bridge NSString *)kCGImagePropertyPixelHeight] doubleValue];
    NSInteger orientation = [properties[(__bridge NSString *)kCGImagePropertyOrientation] integerValue];
    if (orientation >= 5 && orientation <= 8) return CGSizeMake(height, width);
    return CGSizeMake(width, height);
}

static BOOL FFPixelIsNotWhite(NSURL *url, CGFloat normalizedX, CGFloat normalizedY) {
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (!source) return NO;
    CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
    CFRelease(source);
    if (!image) return NO;

    uint8_t pixel[4] = {255, 255, 255, 255};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixel, 1, 1, 8, 4, space,
                                                  kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Big);
    CGColorSpaceRelease(space);
    if (!context) {
        CGImageRelease(image);
        return NO;
    }

    CGFloat width = CGImageGetWidth(image);
    CGFloat height = CGImageGetHeight(image);
    CGContextSetInterpolationQuality(context, kCGInterpolationNone);
    CGContextTranslateCTM(context, -floor(normalizedX * (width - 1)), -floor(normalizedY * (height - 1)));
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);
    CGContextRelease(context);
    CGImageRelease(image);
    return pixel[0] < 240 || pixel[1] < 240 || pixel[2] < 240;
}

static BOOL FFCreatePDF(NSURL *url, NSInteger pageCount) {
    CGDataConsumerRef consumer = CGDataConsumerCreateWithURL((__bridge CFURLRef)url);
    if (!consumer) return NO;
    CGRect mediaBox = CGRectMake(0, 0, 72, 36);
    CGContextRef context = CGPDFContextCreate(consumer, &mediaBox, NULL);
    CGDataConsumerRelease(consumer);
    if (!context) return NO;
    for (NSInteger page = 0; page < pageCount; page++) {
        CGPDFContextBeginPage(context, NULL);
        CGContextSetRGBFillColor(context, 1, 1, 1, 1);
        CGContextFillRect(context, mediaBox);
        CGContextSetRGBFillColor(context, page / (double)MAX(pageCount, 1), 0.4, 0.7, 1);
        CGContextFillRect(context, CGRectMake(8, 8, 20, 12));
        CGPDFContextEndPage(context);
    }
    CGPDFContextClose(context);
    CGContextRelease(context);
    return YES;
}

static BOOL FFCreateRotatedLandscapePDF(NSURL *url) {
    NSURL *baseURL = [[url URLByDeletingLastPathComponent] URLByAppendingPathComponent:@"rotated-source.pdf"];
    CGDataConsumerRef consumer = CGDataConsumerCreateWithURL((__bridge CFURLRef)baseURL);
    if (!consumer) return NO;
    CGRect mediaBox = CGRectMake(12, 18, 36, 72);
    CGContextRef context = CGPDFContextCreate(consumer, &mediaBox, NULL);
    CGDataConsumerRelease(consumer);
    if (!context) return NO;

    CGPDFContextBeginPage(context, NULL);
    CGContextSetRGBFillColor(context, 1, 1, 1, 1);
    CGContextFillRect(context, mediaBox);
    CGContextSetRGBFillColor(context, 0.9, 0.1, 0.1, 1);
    CGContextFillRect(context, CGRectMake(CGRectGetMinX(mediaBox), CGRectGetMinY(mediaBox), 18, 36));
    CGContextSetRGBFillColor(context, 0.1, 0.7, 0.2, 1);
    CGContextFillRect(context, CGRectMake(CGRectGetMidX(mediaBox), CGRectGetMinY(mediaBox), 18, 36));
    CGContextSetRGBFillColor(context, 0.1, 0.3, 0.9, 1);
    CGContextFillRect(context, CGRectMake(CGRectGetMinX(mediaBox), CGRectGetMidY(mediaBox), 18, 36));
    CGContextSetRGBFillColor(context, 0.95, 0.75, 0.05, 1);
    CGContextFillRect(context, CGRectMake(CGRectGetMidX(mediaBox), CGRectGetMidY(mediaBox), 18, 36));
    CGPDFContextEndPage(context);
    CGPDFContextClose(context);
    CGContextRelease(context);

    PDFDocument *document = [[PDFDocument alloc] initWithURL:baseURL];
    PDFPage *page = [document pageAtIndex:0];
    if (!document || !page) return NO;
    page.rotation = 90;
    BOOL result = [document writeToURL:url];
    [NSFileManager.defaultManager removeItemAtURL:baseURL error:nil];
    return result;
}

static FFConversionResult *FFConvert(NSURL *input,
                                     NSURL *output,
                                     FFOutputFormat format,
                                     NSInteger dpi,
                                     FFCropSpec *crop) {
    FFConversionRequest *request = [FFConversionRequest new];
    request.inputURL = input;
    request.outputDirectory = output;
    request.sourceKind = [FFConversionEngine sourceKindForURL:input];
    request.outputFormat = format;
    request.jpegQuality = 0.9;
    request.pdfDPI = dpi;
    request.crop = crop;
    NSError *error = nil;
    FFConversionResult *result = [FFConversionEngine convertRequest:request error:&error];
    if (!result) fprintf(stderr, "Conversion error: %s\n", error.localizedDescription.UTF8String);
    return result;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSURL *root = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:[NSString stringWithFormat:@"FormatFactoryIntegration-%@", NSUUID.UUID.UUIDString]] isDirectory:YES];
        [NSFileManager.defaultManager createDirectoryAtURL:root withIntermediateDirectories:YES attributes:nil error:nil];

        CGImageRef image = FFCreateImage(120, 80);
        NSURL *heic = nil;
        if (argc > 1) {
            heic = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]];
        } else {
            NSURL *generatedHEIC = [root URLByAppendingPathComponent:@"iphone.HEIC"];
            if (FFWriteImage(image, generatedHEIC, CFSTR("public.heic"), 6)) heic = generatedHEIC;
        }
        if (heic && [NSFileManager.defaultManager fileExistsAtPath:heic.path]) {
            FFCheck(YES, @"HEIC 测试样本可读");
            CGSize expectedHEICSize = FFExpectedOrientedSize(heic);
            __block CGImageRef preview = NULL;
            dispatch_semaphore_t previewSemaphore = dispatch_semaphore_create(0);
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                NSError *previewError = nil;
                preview = [FFConversionEngine newPreviewImageForURL:heic maxPixelSize:1600 error:&previewError];
                dispatch_semaphore_signal(previewSemaphore);
            });
            long previewWait = dispatch_semaphore_wait(previewSemaphore, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
            FFCheck(previewWait == 0 && preview != NULL && MAX(CGImageGetWidth(preview), CGImageGetHeight(preview)) <= 1600, @"HEIC 后台低分辨率裁切预览可生成");
            if (preview) CGImageRelease(preview);

            FFConversionResult *heicJPG = FFConvert(heic, [root URLByAppendingPathComponent:@"heic-jpg"], FFOutputFormatJPEG, 200, nil);
            FFCheck(heicJPG.outputURLs.count == 1, @"HEIC → JPG 生成一个文件");
            FFCheck(CGSizeEqualToSize(FFPixelSize(heicJPG.outputURLs.firstObject), expectedHEICSize), @"HEIC → JPG 正确应用 EXIF Orientation");

            FFConversionResult *heicPNG = FFConvert(heic, [root URLByAppendingPathComponent:@"heic-png"], FFOutputFormatPNG, 200, nil);
            FFCheck(heicPNG.outputURLs.count == 1, @"HEIC → PNG 生成一个文件");
            FFCheck(CGSizeEqualToSize(FFPixelSize(heicPNG.outputURLs.firstObject), expectedHEICSize), @"HEIC → PNG 保持方向后分辨率");
        } else {
            printf("SKIP  当前受限环境无法生成 HEIC；传入真实 HEIC 路径可启用 HEIC 集成测试\n");
        }

        NSURL *jpg = [root URLByAppendingPathComponent:@"sample.jpg"];
        NSURL *png = [root URLByAppendingPathComponent:@"sample.png"];
        FFCheck(FFWriteImage(image, jpg, CFSTR("public.jpeg"), 1), @"生成 JPG 测试样本");
        FFCheck(FFWriteImage(image, png, CFSTR("public.png"), 1), @"生成 PNG 测试样本");
        CGImageRelease(image);

        FFCropSpec *halfCrop = [FFCropSpec cropWithX:0.25 y:0.25 width:0.5 height:0.5];
        FFConversionResult *jpgPNG = FFConvert(jpg, [root URLByAppendingPathComponent:@"jpg-png"], FFOutputFormatPNG, 200, halfCrop);
        FFCheck(CGSizeEqualToSize(FFPixelSize(jpgPNG.outputURLs.firstObject), CGSizeMake(60, 40)), @"JPG → 裁切 → PNG 使用原始像素导出");

        FFConversionResult *pngJPG = FFConvert(png, [root URLByAppendingPathComponent:@"png-jpg"], FFOutputFormatJPEG, 200, nil);
        FFCheck(CGSizeEqualToSize(FFPixelSize(pngJPG.outputURLs.firstObject), CGSizeMake(120, 80)), @"PNG → JPG 保持原始分辨率");

        NSURL *defaultOutputDirectory = [FFConversionEngine defaultOutputDirectoryForInputURL:png];
        FFCheck([defaultOutputDirectory isEqual:root], @"默认输出目录就是源文件所在目录");
        NSURL *directSource = [root URLByAppendingPathComponent:@"direct-output.png"];
        CGImageRef directImage = FFCreateImage(48, 32);
        FFCheck(FFWriteImage(directImage, directSource, CFSTR("public.png"), 1), @"生成源目录直出测试样本");
        CGImageRelease(directImage);
        FFConversionResult *directResult = FFConvert(directSource, defaultOutputDirectory, FFOutputFormatJPEG, 200, nil);
        BOOL directOutputCorrect = [directResult.outputURLs.firstObject.URLByDeletingLastPathComponent isEqual:root]
            && ![NSFileManager.defaultManager fileExistsAtPath:[root URLByAppendingPathComponent:@"转换结果"].path];
        FFCheck(directOutputCorrect, @"默认转换结果直接写入源目录且不创建“转换结果”文件夹");
        NSURL *resultFolder = [FFConversionEngine resultFolderOutputDirectoryForInputURL:directSource];
        FFCheck([resultFolder.lastPathComponent isEqualToString:@"转换结果"]
            && [resultFolder.URLByDeletingLastPathComponent isEqual:root],
            @"新文件夹选项定位到源目录下的“转换结果”");
        FFConversionResult *folderResult = FFConvert(directSource, resultFolder, FFOutputFormatJPEG, 200, nil);
        FFCheck([folderResult.outputURLs.firstObject.URLByDeletingLastPathComponent isEqual:resultFolder]
            && [NSFileManager.defaultManager fileExistsAtPath:folderResult.outputURLs.firstObject.path],
            @"新文件夹选项创建目录并写入转换文件");

        NSURL *pdf = [root URLByAppendingPathComponent:@"合同.pdf"];
        FFCheck(FFCreatePDF(pdf, 3), @"生成三页 PDF 测试样本");
        FFConversionResult *pdfResult = FFConvert(pdf, [root URLByAppendingPathComponent:@"pdf-jpg"], FFOutputFormatJPEG, 150, nil);
        NSArray *expectedNames = @[@"合同_001.jpg", @"合同_002.jpg", @"合同_003.jpg"];
        NSArray *actualNames = [pdfResult.outputURLs valueForKey:@"lastPathComponent"];
        FFCheck([actualNames isEqualToArray:expectedNames], @"PDF 每页按三位页码顺序输出");
        BOOL dpiCorrect = YES;
        for (NSURL *url in pdfResult.outputURLs) {
            if (!CGSizeEqualToSize(FFPixelSize(url), CGSizeMake(150, 75))) dpiCorrect = NO;
        }
        FFCheck(dpiCorrect, @"PDF 150 DPI 输出像素尺寸正确");

        FFConversionResult *pdf200 = FFConvert(pdf, [root URLByAppendingPathComponent:@"pdf-200"], FFOutputFormatJPEG, 200, nil);
        FFCheck(CGSizeEqualToSize(FFPixelSize(pdf200.outputURLs.firstObject), CGSizeMake(200, 100)), @"PDF 200 DPI 输出像素尺寸正确");
        FFConversionResult *pdf300 = FFConvert(pdf, [root URLByAppendingPathComponent:@"pdf-300"], FFOutputFormatJPEG, 300, nil);
        FFCheck(CGSizeEqualToSize(FFPixelSize(pdf300.outputURLs.firstObject), CGSizeMake(300, 150)), @"PDF 300 DPI 输出像素尺寸正确");

        NSURL *rotatedPDF = [root URLByAppendingPathComponent:@"横版旋转页.pdf"];
        FFCheck(FFCreateRotatedLandscapePDF(rotatedPDF), @"生成带 90 度旋转及偏移页框的横版 PDF");
        FFConversionResult *rotatedResult = FFConvert(rotatedPDF, [root URLByAppendingPathComponent:@"pdf-rotated"], FFOutputFormatJPEG, 150, nil);
        CGSize rotatedSize = FFPixelSize(rotatedResult.outputURLs.firstObject);
        FFCheck(CGSizeEqualToSize(rotatedSize, CGSizeMake(150, 75)), @"横版旋转 PDF 输出完整画布且方向正确");
        NSURL *rotatedJPG = rotatedResult.outputURLs.firstObject;
        BOOL allCornersHaveContent = FFPixelIsNotWhite(rotatedJPG, 0.1, 0.1)
            && FFPixelIsNotWhite(rotatedJPG, 0.9, 0.1)
            && FFPixelIsNotWhite(rotatedJPG, 0.1, 0.9)
            && FFPixelIsNotWhite(rotatedJPG, 0.9, 0.9);
        FFCheck(allCornersHaveContent, @"横版旋转 PDF 四角内容均完整、没有被裁切或缩在中央");

        NSURL *conflictDirectory = [root URLByAppendingPathComponent:@"conflict"];
        [NSFileManager.defaultManager createDirectoryAtURL:conflictDirectory withIntermediateDirectories:YES attributes:nil error:nil];
        NSURL *existing = [conflictDirectory URLByAppendingPathComponent:@"sample.jpg"];
        [@"existing" writeToURL:existing atomically:YES encoding:NSUTF8StringEncoding error:nil];
        FFConversionResult *conflict = FFConvert(png, conflictDirectory, FFOutputFormatJPEG, 200, nil);
        FFCheck([conflict.outputURLs.firstObject.lastPathComponent isEqualToString:@"sample_2.jpg"], @"已有文件时自动使用 _2，不覆盖原文件");
        NSString *existingText = [NSString stringWithContentsOfURL:existing encoding:NSUTF8StringEncoding error:nil];
        FFCheck([existingText isEqualToString:@"existing"], @"冲突文件内容未被覆盖");

        printf("\nRESULT %ld failures\n", (long)failures);
        if ([NSProcessInfo.processInfo.environment[@"FORMAT_FACTORY_KEEP_TEST_OUTPUT"] boolValue]) {
            printf("ARTIFACT_DIR %s\n", root.path.UTF8String);
        } else {
            [NSFileManager.defaultManager removeItemAtURL:root error:nil];
        }
        return failures == 0 ? 0 : 1;
    }
}
