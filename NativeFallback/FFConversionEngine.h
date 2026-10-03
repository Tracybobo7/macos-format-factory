#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, FFSourceKind) {
    FFSourceKindHEIC,
    FFSourceKindJPEG,
    FFSourceKindPNG,
    FFSourceKindPDF,
    FFSourceKindUnsupported
};

typedef NS_ENUM(NSInteger, FFOutputFormat) {
    FFOutputFormatJPEG,
    FFOutputFormatPNG
};

@interface FFCropSpec : NSObject <NSCopying>
@property(nonatomic) double x;
@property(nonatomic) double y;
@property(nonatomic) double width;
@property(nonatomic) double height;
+ (instancetype)fullCrop;
+ (instancetype)cropWithX:(double)x y:(double)y width:(double)width height:(double)height;
- (FFCropSpec *)clamped;
@end

@interface FFConversionRequest : NSObject
@property(nonatomic, strong) NSUUID *identifier;
@property(nonatomic, strong) NSURL *inputURL;
@property(nonatomic, strong) NSURL *outputDirectory;
@property(nonatomic) FFSourceKind sourceKind;
@property(nonatomic) FFOutputFormat outputFormat;
@property(nonatomic) double jpegQuality;
@property(nonatomic) NSInteger pdfDPI;
@property(nonatomic, strong, nullable) FFCropSpec *crop;
@end

@interface FFConversionResult : NSObject
@property(nonatomic, strong) NSUUID *identifier;
@property(nonatomic, copy) NSArray<NSURL *> *outputURLs;
@end

@interface FFConversionEngine : NSObject
+ (FFSourceKind)sourceKindForURL:(NSURL *)url;
+ (NSString *)displayNameForSourceKind:(FFSourceKind)kind;
+ (NSURL *)defaultOutputDirectoryForInputURL:(NSURL *)inputURL;
+ (NSURL *)resultFolderOutputDirectoryForInputURL:(NSURL *)inputURL;
+ (nullable CGImageRef)newPreviewImageForURL:(NSURL *)url
                                maxPixelSize:(NSInteger)maxPixelSize
                                       error:(NSError **)error CF_RETURNS_RETAINED;
+ (nullable FFConversionResult *)convertRequest:(FFConversionRequest *)request
                                          error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
