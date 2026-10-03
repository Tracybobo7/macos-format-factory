#import <AppKit/AppKit.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import "FFConversionEngine.h"

@interface FFFileItem : NSObject
@property(nonatomic, strong) NSUUID *identifier;
@property(nonatomic, strong) NSURL *url;
@property(nonatomic) FFSourceKind kind;
@property(nonatomic, copy) NSString *sizeText;
@property(nonatomic, copy) NSString *status;
@property(nonatomic, copy, nullable) NSString *errorMessage;
@property(nonatomic, strong, nullable) FFCropSpec *crop;
@property(nonatomic, copy) NSArray<NSURL *> *outputURLs;
@end

@implementation FFFileItem
@end

@interface FFDropView : NSView <NSDraggingDestination>
@property(nonatomic, copy) void (^filesDropped)(NSArray<NSURL *> *urls);
@property(nonatomic) BOOL highlighted;
@end

@implementation FFDropView

- (instancetype)initWithFrame:(NSRect)frameRect {
    self = [super initWithFrame:frameRect];
    if (self) {
        [self registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
        self.wantsLayer = YES;
    }
    return self;
}

- (BOOL)isFlipped { return YES; }

- (void)drawRect:(NSRect)dirtyRect {
    [super drawRect:dirtyRect];
    NSColor *fill = self.highlighted ? [NSColor.controlAccentColor colorWithAlphaComponent:0.10] : [NSColor.secondaryLabelColor colorWithAlphaComponent:0.05];
    [fill setFill];
    NSBezierPath *background = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(self.bounds, 1, 1) xRadius:10 yRadius:10];
    [background fill];
    CGFloat dash[] = {6, 4};
    [background setLineDash:dash count:2 phase:0];
    background.lineWidth = 1;
    [(self.highlighted ? NSColor.controlAccentColor : [NSColor.secondaryLabelColor colorWithAlphaComponent:0.45]) setStroke];
    [background stroke];

    NSString *message = @"将 HEIC、JPG、PNG 或 PDF 文件拖到这里";
    NSDictionary *attributes = @{
        NSFontAttributeName: [NSFont systemFontOfSize:14],
        NSForegroundColorAttributeName: self.highlighted ? NSColor.labelColor : NSColor.secondaryLabelColor
    };
    NSSize size = [message sizeWithAttributes:attributes];
    [message drawAtPoint:NSMakePoint((NSWidth(self.bounds) - size.width) / 2,
                                     (NSHeight(self.bounds) - size.height) / 2)
          withAttributes:attributes];
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
    self.highlighted = YES;
    [self setNeedsDisplay:YES];
    return NSDragOperationCopy;
}

- (void)draggingExited:(nullable id<NSDraggingInfo>)sender {
    self.highlighted = NO;
    [self setNeedsDisplay:YES];
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
    self.highlighted = NO;
    [self setNeedsDisplay:YES];
    NSArray<NSURL *> *urls = [sender.draggingPasteboard readObjectsForClasses:@[NSURL.class]
                                                                      options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
    if (urls.count && self.filesDropped) self.filesDropped(urls);
    return urls.count > 0;
}

@end

typedef NS_ENUM(NSInteger, FFCropDragMode) {
    FFCropDragNone,
    FFCropDragMove,
    FFCropDragTopLeft,
    FFCropDragTopRight,
    FFCropDragBottomLeft,
    FFCropDragBottomRight
};

@interface FFCropView : NSView
@property(nonatomic) CGImageRef image;
@property(nonatomic, strong) FFCropSpec *crop;
@property(nonatomic) CGFloat targetAspect;
@property(nonatomic) NSPoint dragStartPoint;
@property(nonatomic, strong) FFCropSpec *dragStartCrop;
@property(nonatomic) FFCropDragMode dragMode;
- (instancetype)initWithImage:(CGImageRef)image crop:(nullable FFCropSpec *)crop;
- (void)resetForTargetAspect:(CGFloat)targetAspect;
@end

@implementation FFCropView

- (instancetype)initWithImage:(CGImageRef)image crop:(FFCropSpec *)crop {
    self = [super initWithFrame:NSZeroRect];
    if (self) {
        _image = CGImageRetain(image);
        _crop = crop ? crop.copy : [FFCropSpec cropWithX:0.1 y:0.1 width:0.8 height:0.8];
        _targetAspect = 0;
        self.wantsLayer = YES;
        self.layer.backgroundColor = NSColor.blackColor.CGColor;
    }
    return self;
}

- (void)dealloc {
    if (_image) CGImageRelease(_image);
}

- (BOOL)isFlipped { return YES; }

- (CGFloat)imageAspect {
    return (CGFloat)CGImageGetWidth(self.image) / MAX((CGFloat)CGImageGetHeight(self.image), 1);
}

- (NSRect)imageRect {
    CGFloat imageAspect = self.imageAspect;
    CGFloat containerAspect = NSWidth(self.bounds) / MAX(NSHeight(self.bounds), 1);
    NSSize size;
    if (containerAspect > imageAspect) {
        size = NSMakeSize(NSHeight(self.bounds) * imageAspect, NSHeight(self.bounds));
    } else {
        size = NSMakeSize(NSWidth(self.bounds), NSWidth(self.bounds) / imageAspect);
    }
    return NSMakeRect((NSWidth(self.bounds) - size.width) / 2,
                      (NSHeight(self.bounds) - size.height) / 2,
                      size.width,
                      size.height);
}

- (NSRect)cropRect {
    NSRect imageRect = self.imageRect;
    return NSMakeRect(NSMinX(imageRect) + self.crop.x * NSWidth(imageRect),
                      NSMinY(imageRect) + self.crop.y * NSHeight(imageRect),
                      self.crop.width * NSWidth(imageRect),
                      self.crop.height * NSHeight(imageRect));
}

- (void)drawRect:(NSRect)dirtyRect {
    [NSColor.blackColor setFill];
    NSRectFill(self.bounds);
    NSRect imageRect = self.imageRect;
    CGContextRef context = NSGraphicsContext.currentContext.CGContext;
    CGContextSaveGState(context);
    CGContextTranslateCTM(context, NSMinX(imageRect), NSMaxY(imageRect));
    CGContextScaleCTM(context, 1, -1);
    CGContextDrawImage(context, CGRectMake(0, 0, NSWidth(imageRect), NSHeight(imageRect)), self.image);
    CGContextRestoreGState(context);

    NSRect cropRect = self.cropRect;
    CGContextSaveGState(context);
    CGContextSetRGBFillColor(context, 0, 0, 0, 0.58);
    CGContextAddRect(context, NSRectToCGRect(imageRect));
    CGContextAddRect(context, NSRectToCGRect(cropRect));
    CGContextEOFillPath(context);
    CGContextRestoreGState(context);

    [NSColor.whiteColor setStroke];
    NSBezierPath *border = [NSBezierPath bezierPathWithRect:cropRect];
    border.lineWidth = 2;
    [border stroke];

    [[NSColor.whiteColor colorWithAlphaComponent:0.42] setStroke];
    NSBezierPath *grid = [NSBezierPath bezierPath];
    for (NSInteger index = 1; index <= 2; index++) {
        CGFloat x = NSMinX(cropRect) + NSWidth(cropRect) * index / 3.0;
        [grid moveToPoint:NSMakePoint(x, NSMinY(cropRect))];
        [grid lineToPoint:NSMakePoint(x, NSMaxY(cropRect))];
        CGFloat y = NSMinY(cropRect) + NSHeight(cropRect) * index / 3.0;
        [grid moveToPoint:NSMakePoint(NSMinX(cropRect), y)];
        [grid lineToPoint:NSMakePoint(NSMaxX(cropRect), y)];
    }
    grid.lineWidth = 0.7;
    [grid stroke];

    [NSColor.whiteColor setFill];
    NSArray<NSValue *> *points = @[
        [NSValue valueWithPoint:NSMakePoint(NSMinX(cropRect), NSMinY(cropRect))],
        [NSValue valueWithPoint:NSMakePoint(NSMaxX(cropRect), NSMinY(cropRect))],
        [NSValue valueWithPoint:NSMakePoint(NSMinX(cropRect), NSMaxY(cropRect))],
        [NSValue valueWithPoint:NSMakePoint(NSMaxX(cropRect), NSMaxY(cropRect))]
    ];
    for (NSValue *value in points) {
        NSPoint point = value.pointValue;
        [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(point.x - 7, point.y - 7, 14, 14)] fill];
    }
}

- (FFCropDragMode)modeAtPoint:(NSPoint)point {
    NSRect rect = self.cropRect;
    NSArray<NSValue *> *points = @[
        [NSValue valueWithPoint:NSMakePoint(NSMinX(rect), NSMinY(rect))],
        [NSValue valueWithPoint:NSMakePoint(NSMaxX(rect), NSMinY(rect))],
        [NSValue valueWithPoint:NSMakePoint(NSMinX(rect), NSMaxY(rect))],
        [NSValue valueWithPoint:NSMakePoint(NSMaxX(rect), NSMaxY(rect))]
    ];
    FFCropDragMode modes[] = {FFCropDragTopLeft, FFCropDragTopRight, FFCropDragBottomLeft, FFCropDragBottomRight};
    for (NSInteger index = 0; index < points.count; index++) {
        NSPoint handle = points[index].pointValue;
        if (hypot(point.x - handle.x, point.y - handle.y) <= 16) return modes[index];
    }
    return NSPointInRect(point, rect) ? FFCropDragMove : FFCropDragNone;
}

- (void)mouseDown:(NSEvent *)event {
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    self.dragMode = [self modeAtPoint:point];
    self.dragStartPoint = point;
    self.dragStartCrop = self.crop.copy;
}

- (void)mouseDragged:(NSEvent *)event {
    if (self.dragMode == FFCropDragNone) return;
    NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
    NSRect imageRect = self.imageRect;
    double dx = (point.x - self.dragStartPoint.x) / MAX(NSWidth(imageRect), 1);
    double dy = (point.y - self.dragStartPoint.y) / MAX(NSHeight(imageRect), 1);
    FFCropSpec *start = self.dragStartCrop;
    if (self.dragMode == FFCropDragMove) {
        self.crop.x = fmin(fmax(start.x + dx, 0), 1 - start.width);
        self.crop.y = fmin(fmax(start.y + dy, 0), 1 - start.height);
        [self setNeedsDisplay:YES];
        return;
    }

    BOOL movingRight = self.dragMode == FFCropDragTopRight || self.dragMode == FFCropDragBottomRight;
    BOOL movingBottom = self.dragMode == FFCropDragBottomLeft || self.dragMode == FFCropDragBottomRight;
    double fixedX = movingRight ? start.x : start.x + start.width;
    double fixedY = movingBottom ? start.y : start.y + start.height;
    double movingX = movingRight ? start.x + start.width + dx : start.x + dx;
    double movingY = movingBottom ? start.y + start.height + dy : start.y + dy;
    movingX = fmin(fmax(movingX, 0), 1);
    movingY = fmin(fmax(movingY, 0), 1);
    double minimum = 0.03;

    if (self.targetAspect > 0) {
        double width = fmax(fabs(movingX - fixedX), minimum);
        double height = width * self.imageAspect / self.targetAspect;
        double maxWidth = movingRight ? 1 - fixedX : fixedX;
        double maxHeight = movingBottom ? 1 - fixedY : fixedY;
        if (height > maxHeight) {
            height = maxHeight;
            width = height * self.targetAspect / self.imageAspect;
        }
        width = fmin(width, maxWidth);
        height = fmin(height, maxHeight);
        self.crop = [[FFCropSpec cropWithX:(movingRight ? fixedX : fixedX - width)
                                         y:(movingBottom ? fixedY : fixedY - height)
                                     width:width
                                    height:height] clamped];
    } else {
        self.crop = [[FFCropSpec cropWithX:fmin(fixedX, movingX)
                                         y:fmin(fixedY, movingY)
                                     width:fmax(fabs(movingX - fixedX), minimum)
                                    height:fmax(fabs(movingY - fixedY), minimum)] clamped];
    }
    [self setNeedsDisplay:YES];
}

- (void)mouseUp:(NSEvent *)event {
    self.dragMode = FFCropDragNone;
    self.dragStartCrop = nil;
}

- (void)resetForTargetAspect:(CGFloat)targetAspect {
    self.targetAspect = targetAspect;
    if (targetAspect <= 0) {
        self.crop = [FFCropSpec cropWithX:0.1 y:0.1 width:0.8 height:0.8];
    } else {
        CGFloat width = 0.84;
        CGFloat height = width * self.imageAspect / targetAspect;
        if (height > 0.84) {
            height = 0.84;
            width = height * targetAspect / self.imageAspect;
        }
        self.crop = [FFCropSpec cropWithX:(1 - width) / 2
                                       y:(1 - height) / 2
                                   width:width
                                  height:height];
    }
    [self setNeedsDisplay:YES];
}

@end

@interface FFCropWindowController : NSWindowController
@property(nonatomic, strong) FFCropView *cropView;
@property(nonatomic, strong) NSPopUpButton *ratioPopup;
@property(nonatomic, copy) void (^completion)(FFCropSpec * _Nullable crop);
- (instancetype)initWithImage:(CGImageRef)image
                          crop:(nullable FFCropSpec *)crop
                    completion:(void (^)(FFCropSpec * _Nullable crop))completion;
@end


@implementation FFCropWindowController

- (instancetype)initWithImage:(CGImageRef)image
                          crop:(FFCropSpec *)crop
                    completion:(void (^)(FFCropSpec * _Nullable))completion {
    NSWindow *window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 820, 640)
                                                   styleMask:NSWindowStyleMaskTitled
                                                     backing:NSBackingStoreBuffered
                                                       defer:NO];
    window.title = @"裁切图片";
    self = [super initWithWindow:window];
    if (self) {
        _completion = [completion copy];
        [self buildUIWithImage:image crop:crop];
    }
    return self;
}

- (void)buildUIWithImage:(CGImageRef)image crop:(FFCropSpec *)crop {
    NSView *content = self.window.contentView;
    self.cropView = [[FFCropView alloc] initWithImage:image crop:crop];
    self.cropView.translatesAutoresizingMaskIntoConstraints = NO;
    [content addSubview:self.cropView];

    NSTextField *ratioLabel = [NSTextField labelWithString:@"比例"];
    self.ratioPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [self.ratioPopup addItemsWithTitles:@[@"自由", @"原始比例", @"1:1", @"4:3", @"3:4", @"16:9", @"9:16"]];
    self.ratioPopup.target = self;
    self.ratioPopup.action = @selector(ratioChanged:);

    NSButton *reset = [NSButton buttonWithTitle:@"重置裁切" target:self action:@selector(resetCrop:)];
    NSButton *cancel = [NSButton buttonWithTitle:@"取消" target:self action:@selector(cancel:)];
    NSButton *done = [NSButton buttonWithTitle:@"完成" target:self action:@selector(done:)];
    done.keyEquivalent = @"\r";
    done.bezelColor = NSColor.controlAccentColor;
    NSStackView *controls = [NSStackView stackViewWithViews:@[ratioLabel, self.ratioPopup, reset, [NSView new], cancel, done]];
    controls.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    controls.spacing = 10;
    controls.translatesAutoresizingMaskIntoConstraints = NO;
    [controls.views[3] setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [content addSubview:controls];

    [NSLayoutConstraint activateConstraints:@[
        [self.cropView.topAnchor constraintEqualToAnchor:content.topAnchor constant:18],
        [self.cropView.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:18],
        [self.cropView.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-18],
        [self.cropView.bottomAnchor constraintEqualToAnchor:controls.topAnchor constant:-14],
        [controls.leadingAnchor constraintEqualToAnchor:content.leadingAnchor constant:18],
        [controls.trailingAnchor constraintEqualToAnchor:content.trailingAnchor constant:-18],
        [controls.bottomAnchor constraintEqualToAnchor:content.bottomAnchor constant:-16],
        [controls.heightAnchor constraintEqualToConstant:30]
    ]];
}

- (void)ratioChanged:(id)sender {
    CGFloat imageAspect = self.cropView.imageAspect;
    CGFloat ratios[] = {0, imageAspect, 1, 4.0/3.0, 3.0/4.0, 16.0/9.0, 9.0/16.0};
    [self.cropView resetForTargetAspect:ratios[self.ratioPopup.indexOfSelectedItem]];
}

- (void)resetCrop:(id)sender {
    [self.ratioPopup selectItemAtIndex:0];
    [self.cropView resetForTargetAspect:0];
}

- (void)cancel:(id)sender {
    if (self.completion) self.completion(nil);
    [self.window.sheetParent endSheet:self.window];
}

- (void)done:(id)sender {
    if (self.completion) self.completion(self.cropView.crop.clamped);
    [self.window.sheetParent endSheet:self.window];
}

@end

@interface FFMainViewController : NSViewController <NSTableViewDataSource, NSTableViewDelegate>
@property(nonatomic, strong) NSMutableArray<FFFileItem *> *files;
@property(nonatomic, strong) NSTableView *tableView;
@property(nonatomic, strong) NSPopUpButton *formatPopup;
@property(nonatomic, strong) NSSlider *qualitySlider;
@property(nonatomic, strong) NSTextField *qualityValue;
@property(nonatomic, strong) NSPopUpButton *dpiPopup;
@property(nonatomic, strong) NSPopUpButton *outputPopup;
@property(nonatomic, strong) NSTextField *outputPathLabel;
@property(nonatomic, strong) NSButton *startButton;
@property(nonatomic, strong) NSButton *cropButton;
@property(nonatomic, strong) NSButton *deleteButton;
@property(nonatomic, strong) NSButton *openOutputButton;
@property(nonatomic, strong) NSProgressIndicator *progress;
@property(nonatomic, strong) NSTextField *progressLabel;
@property(nonatomic, strong) NSTextField *currentLabel;
@property(nonatomic, strong) NSTextField *summaryLabel;
@property(nonatomic, strong) NSURL *customOutputDirectory;
@property(nonatomic, strong) NSMutableArray<NSURL *> *lastOutputs;
@property(nonatomic, strong) NSOperationQueue *conversionQueue;
@property(nonatomic, strong) FFCropWindowController *cropController;
@property(nonatomic) NSInteger totalJobs;
@property(nonatomic) NSInteger completedJobs;
@property(nonatomic) NSInteger successfulJobs;
@property(nonatomic) NSInteger failedJobs;
@property(nonatomic) BOOL converting;
@end

@implementation FFMainViewController

- (instancetype)init {
    self = [super init];
    if (self) {
        _files = [NSMutableArray array];
        _lastOutputs = [NSMutableArray array];
        _conversionQueue = [NSOperationQueue new];
        _conversionQueue.qualityOfService = NSQualityOfServiceUserInitiated;
        _conversionQueue.maxConcurrentOperationCount = MAX(1, MIN(NSProcessInfo.processInfo.activeProcessorCount, 6));
    }
    return self;
}

- (void)loadView {
    self.view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 940, 700)];
    [self buildUI];
}

- (NSTextField *)secondaryLabel:(NSString *)text {
    NSTextField *label = [NSTextField labelWithString:text];
    label.textColor = NSColor.secondaryLabelColor;
    return label;
}

- (void)buildUI {
    NSTextField *title = [NSTextField labelWithString:@"格式工厂"];
    title.font = [NSFont systemFontOfSize:26 weight:NSFontWeightSemibold];
    NSTextField *subtitle = [self secondaryLabel:@"本地批量转换 · 文件不会上传"];
    NSStackView *titleStack = [NSStackView stackViewWithViews:@[title, subtitle]];
    titleStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    titleStack.alignment = NSLayoutAttributeLeading;
    titleStack.spacing = 3;
    NSButton *choose = [NSButton buttonWithTitle:@"选择文件" target:self action:@selector(chooseFiles:)];
    choose.bezelStyle = NSBezelStyleRounded;
    NSButton *clear = [NSButton buttonWithTitle:@"清空列表" target:self action:@selector(clearFiles:)];
    NSStackView *header = [NSStackView stackViewWithViews:@[titleStack, [NSView new], choose, clear]];
    header.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    header.alignment = NSLayoutAttributeCenterY;
    header.spacing = 10;
    [header.views[1] setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];

    FFDropView *drop = [[FFDropView alloc] initWithFrame:NSZeroRect];
    __weak typeof(self) weakSelf = self;
    drop.filesDropped = ^(NSArray<NSURL *> *urls) { [weakSelf addURLs:urls]; };
    [drop.heightAnchor constraintEqualToConstant:58].active = YES;

    self.tableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.allowsMultipleSelection = YES;
    self.tableView.usesAlternatingRowBackgroundColors = YES;
    NSArray *columns = @[
        @[@"name", @"文件名", @420],
        @[@"type", @"类型", @70],
        @[@"size", @"大小", @90],
        @[@"status", @"状态", @250]
    ];
    for (NSArray *definition in columns) {
        NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:definition[0]];
        column.title = definition[1];
        column.width = [definition[2] doubleValue];
        if ([definition[0] isEqual:@"name"] || [definition[0] isEqual:@"status"]) column.resizingMask = NSTableColumnAutoresizingMask;
        [self.tableView addTableColumn:column];
    }
    NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
    scroll.documentView = self.tableView;
    scroll.hasVerticalScroller = YES;
    scroll.borderType = NSBezelBorder;
    [scroll.heightAnchor constraintGreaterThanOrEqualToConstant:230].active = YES;

    self.cropButton = [NSButton buttonWithTitle:@"裁切选中图片" target:self action:@selector(cropSelected:)];
    self.deleteButton = [NSButton buttonWithTitle:@"删除选中" target:self action:@selector(deleteSelected:)];
    NSButton *reveal = [NSButton buttonWithTitle:@"在 Finder 中显示源文件" target:self action:@selector(revealSelected:)];
    NSStackView *fileActions = [NSStackView stackViewWithViews:@[self.cropButton, self.deleteButton, reveal, [NSView new]]];
    fileActions.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    fileActions.spacing = 8;
    [fileActions.views.lastObject setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];

    self.formatPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [self.formatPopup addItemsWithTitles:@[@"JPG", @"PNG"]];
    self.qualitySlider = [NSSlider sliderWithValue:90 minValue:60 maxValue:100 target:self action:@selector(qualityChanged:)];
    self.qualitySlider.continuous = YES;
    self.qualityValue = [NSTextField labelWithString:@"90%"];
    self.qualityValue.alignment = NSTextAlignmentRight;
    [self.qualityValue.widthAnchor constraintEqualToConstant:44].active = YES;
    NSStackView *qualityRow = [NSStackView stackViewWithViews:@[[NSTextField labelWithString:@"JPG 质量"], self.qualitySlider, self.qualityValue]];
    qualityRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    qualityRow.spacing = 8;
    NSStackView *imageSettings = [NSStackView stackViewWithViews:@[[NSTextField labelWithString:@"图片输出格式"], self.formatPopup, qualityRow]];
    imageSettings.orientation = NSUserInterfaceLayoutOrientationVertical;
    imageSettings.alignment = NSLayoutAttributeLeading;
    imageSettings.spacing = 8;
    [qualityRow.widthAnchor constraintEqualToConstant:260].active = YES;

    self.dpiPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [self.dpiPopup addItemsWithTitles:@[@"标准 150 DPI", @"高清 200 DPI", @"超清 300 DPI"]];
    NSInteger savedDPI = [NSUserDefaults.standardUserDefaults integerForKey:@"pdfDPI"];
    [self.dpiPopup selectItemAtIndex:savedDPI == 150 ? 0 : savedDPI == 300 ? 2 : 1];
    NSStackView *pdfSettings = [NSStackView stackViewWithViews:@[[NSTextField labelWithString:@"PDF 清晰度"], self.dpiPopup]];
    pdfSettings.orientation = NSUserInterfaceLayoutOrientationVertical;
    pdfSettings.alignment = NSLayoutAttributeLeading;
    pdfSettings.spacing = 8;

    self.outputPopup = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    [self.outputPopup addItemsWithTitles:@[@"原文件所在目录", @"新建“转换结果”文件夹", @"自定义目录"]];
    self.outputPopup.target = self;
    self.outputPopup.action = @selector(outputModeChanged:);
    NSButton *selectOutput = [NSButton buttonWithTitle:@"选择目录…" target:self action:@selector(chooseOutputDirectory:)];
    self.outputPathLabel = [self secondaryLabel:@"默认：直接输出到每个源文件所在目录"];
    self.outputPathLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    NSStackView *outputSettings = [NSStackView stackViewWithViews:@[[NSTextField labelWithString:@"输出位置"], self.outputPopup, selectOutput, self.outputPathLabel]];
    outputSettings.orientation = NSUserInterfaceLayoutOrientationVertical;
    outputSettings.alignment = NSLayoutAttributeLeading;
    outputSettings.spacing = 7;
    [self.outputPathLabel.widthAnchor constraintLessThanOrEqualToConstant:280].active = YES;

    NSStackView *settingsContent = [NSStackView stackViewWithViews:@[imageSettings, pdfSettings, outputSettings]];
    settingsContent.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    settingsContent.alignment = NSLayoutAttributeTop;
    settingsContent.distribution = NSStackViewDistributionFillEqually;
    settingsContent.spacing = 16;
    settingsContent.edgeInsets = NSEdgeInsetsMake(12, 12, 12, 12);
    NSBox *settingsBox = [NSBox new];
    settingsBox.title = @"转换设置";
    settingsBox.contentView = settingsContent;
    [settingsBox.heightAnchor constraintEqualToConstant:155].active = YES;

    self.progress = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
    self.progress.indeterminate = NO;
    self.progress.minValue = 0;
    self.progress.maxValue = 1;
    self.progress.doubleValue = 0;
    self.progressLabel = [NSTextField labelWithString:@"0 / 0"];
    self.progressLabel.font = [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightRegular];
    self.currentLabel = [self secondaryLabel:@""];
    self.currentLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
    self.summaryLabel = [NSTextField labelWithString:@"成功 0  失败 0"];
    self.summaryLabel.font = [NSFont monospacedDigitSystemFontOfSize:12 weight:NSFontWeightRegular];
    NSStackView *progressRow = [NSStackView stackViewWithViews:@[self.progress, self.progressLabel, self.currentLabel, [NSView new], self.summaryLabel]];
    progressRow.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    progressRow.spacing = 9;
    [self.progress.widthAnchor constraintGreaterThanOrEqualToConstant:280].active = YES;
    [progressRow.views[3] setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];

    self.openOutputButton = [NSButton buttonWithTitle:@"打开输出文件夹" target:self action:@selector(openOutput:)];
    self.startButton = [NSButton buttonWithTitle:@"开始转换" target:self action:@selector(startConversion:)];
    self.startButton.bezelStyle = NSBezelStyleRounded;
    self.startButton.keyEquivalent = @"\r";
    self.startButton.bezelColor = NSColor.controlAccentColor;
    NSStackView *bottom = [NSStackView stackViewWithViews:@[self.openOutputButton, [NSView new], self.startButton]];
    bottom.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    [bottom.views[1] setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self.startButton.widthAnchor constraintGreaterThanOrEqualToConstant:150].active = YES;

    NSStackView *root = [NSStackView stackViewWithViews:@[header, drop, scroll, fileActions, settingsBox, progressRow, bottom]];
    root.orientation = NSUserInterfaceLayoutOrientationVertical;
    root.alignment = NSLayoutAttributeLeading;
    root.spacing = 12;
    root.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:root];
    for (NSView *view in root.views) [view.widthAnchor constraintEqualToAnchor:root.widthAnchor].active = YES;
    [NSLayoutConstraint activateConstraints:@[
        [root.topAnchor constraintEqualToAnchor:self.view.topAnchor constant:18],
        [root.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:18],
        [root.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-18],
        [root.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor constant:-18]
    ]];

    double savedQuality = [NSUserDefaults.standardUserDefaults doubleForKey:@"jpegQuality"];
    if (savedQuality >= 60 && savedQuality <= 100) self.qualitySlider.doubleValue = savedQuality;
    [self qualityChanged:self.qualitySlider];
    [self updateControls];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView { return self.files.count; }

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
    NSString *identifier = tableColumn.identifier;
    NSTextField *field = [tableView makeViewWithIdentifier:identifier owner:self];
    if (!field) {
        field = [NSTextField labelWithString:@""];
        field.identifier = identifier;
        field.lineBreakMode = NSLineBreakByTruncatingMiddle;
    }
    FFFileItem *item = self.files[row];
    if ([identifier isEqualToString:@"name"]) field.stringValue = item.url.lastPathComponent;
    else if ([identifier isEqualToString:@"type"]) field.stringValue = [FFConversionEngine displayNameForSourceKind:item.kind];
    else if ([identifier isEqualToString:@"size"]) field.stringValue = item.sizeText;
    else {
        field.stringValue = item.errorMessage.length ? [NSString stringWithFormat:@"%@ · %@", item.status, item.errorMessage] : item.status;
        field.textColor = [item.status isEqualToString:@"失败"] ? NSColor.systemRedColor :
                          [item.status isEqualToString:@"已完成"] ? NSColor.systemGreenColor :
                          [item.status isEqualToString:@"已裁切"] ? NSColor.systemOrangeColor : NSColor.labelColor;
    }
    field.toolTip = item.url.path;
    return field;
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification { [self updateControls]; }

- (void)addURLs:(NSArray<NSURL *> *)urls {
    NSMutableSet<NSString *> *existing = [NSMutableSet set];
    for (FFFileItem *item in self.files) [existing addObject:item.url.standardizedURL.path];
    for (NSURL *url in urls) {
        NSNumber *isRegular = nil;
        [url getResourceValue:&isRegular forKey:NSURLIsRegularFileKey error:nil];
        if (!isRegular.boolValue || [existing containsObject:url.standardizedURL.path]) continue;
        [existing addObject:url.standardizedURL.path];
        FFFileItem *item = [FFFileItem new];
        item.identifier = [NSUUID UUID];
        item.url = url.standardizedURL;
        item.kind = [FFConversionEngine sourceKindForURL:url];
        NSNumber *size = nil;
        [url getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
        item.sizeText = [NSByteCountFormatter stringFromByteCount:size.longLongValue countStyle:NSByteCountFormatterCountStyleFile];
        item.status = item.kind == FFSourceKindUnsupported ? @"失败" : @"等待转换";
        item.errorMessage = item.kind == FFSourceKindUnsupported ? @"不支持的文件格式" : nil;
        item.outputURLs = @[];
        [self.files addObject:item];
    }
    [self.tableView reloadData];
    [self updateControls];
}

- (void)chooseFiles:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.title = @"选择要转换的文件";
    panel.prompt = @"加入列表";
    panel.canChooseFiles = YES;
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = YES;
    panel.allowedContentTypes = @[UTTypeHEIC, UTTypeHEIF, UTTypeJPEG, UTTypePNG, UTTypePDF];
    if ([panel runModal] == NSModalResponseOK) [self addURLs:panel.URLs];
}

- (void)clearFiles:(id)sender {
    if (self.converting) return;
    [self.files removeAllObjects];
    [self.tableView reloadData];
    [self resetProgress];
    [self updateControls];
}

- (void)deleteSelected:(id)sender {
    if (self.converting) return;
    NSIndexSet *indexes = self.tableView.selectedRowIndexes;
    if (indexes.count) [self.files removeObjectsAtIndexes:indexes];
    [self.tableView reloadData];
    [self updateControls];
}

- (FFFileItem *)singleSelectedItem {
    NSInteger row = self.tableView.selectedRow;
    return row >= 0 && row < self.files.count ? self.files[row] : nil;
}

- (void)revealSelected:(id)sender {
    FFFileItem *item = self.singleSelectedItem;
    if (item) [NSWorkspace.sharedWorkspace activateFileViewerSelectingURLs:@[item.url]];
}

- (void)cropSelected:(id)sender {
    FFFileItem *item = self.singleSelectedItem;
    if (!item || item.kind == FFSourceKindPDF || item.kind == FFSourceKindUnsupported || self.converting) return;
    self.currentLabel.stringValue = @"正在生成裁切预览…";
    NSURL *url = item.url;
    FFCropSpec *existingCrop = item.crop.copy;
    NSError *error = nil;
    CGImageRef preview = [FFConversionEngine newPreviewImageForURL:url maxPixelSize:1600 error:&error];
    self.currentLabel.stringValue = @"";
    if (!preview) {
        [self showError:error.localizedDescription ?: @"无法生成图片预览"];
        return;
    }
    self.cropController = [[FFCropWindowController alloc] initWithImage:preview crop:existingCrop completion:^(FFCropSpec *crop) {
        if (crop) {
            item.crop = crop;
            item.status = @"已裁切";
            item.errorMessage = nil;
            [self.tableView reloadData];
        }
    }];
    CGImageRelease(preview);
    [self.view.window beginSheet:self.cropController.window completionHandler:^(NSModalResponse returnCode) {
        self.cropController = nil;
    }];
}

- (void)qualityChanged:(NSSlider *)sender {
    self.qualityValue.stringValue = [NSString stringWithFormat:@"%.0f%%", sender.doubleValue];
    [NSUserDefaults.standardUserDefaults setDouble:sender.doubleValue forKey:@"jpegQuality"];
}

- (void)outputModeChanged:(id)sender {
    if (self.outputPopup.indexOfSelectedItem == 0) {
        self.outputPathLabel.stringValue = @"默认：直接输出到每个源文件所在目录";
    } else if (self.outputPopup.indexOfSelectedItem == 1) {
        self.outputPathLabel.stringValue = @"在每个源文件目录下建立“转换结果”";
    } else if (!self.customOutputDirectory) {
        [self chooseOutputDirectory:nil];
    } else {
        self.outputPathLabel.stringValue = self.customOutputDirectory.path;
    }
    [self updateControls];
}

- (void)chooseOutputDirectory:(id)sender {
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.title = @"选择输出目录";
    panel.prompt = @"选择";
    panel.canChooseFiles = NO;
    panel.canChooseDirectories = YES;
    panel.canCreateDirectories = YES;
    if ([panel runModal] == NSModalResponseOK) {
        self.customOutputDirectory = panel.URL;
        [self.outputPopup selectItemAtIndex:2];
        self.outputPathLabel.stringValue = panel.URL.path;
    } else if (!self.customOutputDirectory) {
        [self.outputPopup selectItemAtIndex:0];
        self.outputPathLabel.stringValue = @"默认：直接输出到每个源文件所在目录";
    }
    [self updateControls];
}

- (NSInteger)selectedDPI {
    NSInteger values[] = {150, 200, 300};
    NSInteger value = values[self.dpiPopup.indexOfSelectedItem];
    [NSUserDefaults.standardUserDefaults setInteger:value forKey:@"pdfDPI"];
    return value;
}

- (void)startConversion:(id)sender {
    if (self.converting) return;
    NSMutableArray<FFFileItem *> *jobs = [NSMutableArray array];
    for (FFFileItem *item in self.files) {
        if (item.kind != FFSourceKindUnsupported) [jobs addObject:item];
    }
    if (!jobs.count) return;
    if (self.outputPopup.indexOfSelectedItem == 2 && !self.customOutputDirectory) {
        [self chooseOutputDirectory:nil];
        if (!self.customOutputDirectory) return;
    }

    [self resetProgress];
    self.converting = YES;
    self.totalJobs = jobs.count;
    self.progress.maxValue = jobs.count;
    self.startButton.title = @"正在转换…";
    [self updateControls];
    FFOutputFormat outputFormat = self.formatPopup.indexOfSelectedItem == 0 ? FFOutputFormatJPEG : FFOutputFormatPNG;
    double quality = self.qualitySlider.doubleValue / 100.0;
    NSInteger dpi = self.selectedDPI;
    NSURL *custom = self.customOutputDirectory;
    NSInteger outputMode = self.outputPopup.indexOfSelectedItem;
    __weak typeof(self) weakSelf = self;

    for (FFFileItem *item in jobs) {
        item.status = @"等待转换";
        item.errorMessage = nil;
        item.outputURLs = @[];
        FFConversionRequest *request = [FFConversionRequest new];
        request.identifier = item.identifier;
        request.inputURL = item.url;
        request.sourceKind = item.kind;
        request.outputFormat = item.kind == FFSourceKindPDF ? FFOutputFormatJPEG : outputFormat;
        request.jpegQuality = quality;
        request.pdfDPI = dpi;
        request.crop = item.crop.copy;
        if (outputMode == 2) {
            request.outputDirectory = custom;
        } else if (outputMode == 1) {
            request.outputDirectory = [FFConversionEngine resultFolderOutputDirectoryForInputURL:item.url];
        } else {
            request.outputDirectory = [FFConversionEngine defaultOutputDirectoryForInputURL:item.url];
        }

        [self.conversionQueue addOperationWithBlock:^{
            @autoreleasepool {
                [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    item.status = @"转换中";
                    weakSelf.currentLabel.stringValue = item.url.lastPathComponent;
                    [weakSelf.tableView reloadData];
                }];
                NSError *error = nil;
                FFConversionResult *result = [FFConversionEngine convertRequest:request error:&error];
                [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    __strong typeof(weakSelf) self = weakSelf;
                    if (!self) return;
                    self.completedJobs += 1;
                    if (result) {
                        item.status = @"已完成";
                        item.outputURLs = result.outputURLs;
                        [self.lastOutputs addObjectsFromArray:result.outputURLs];
                        self.successfulJobs += 1;
                    } else {
                        item.status = @"失败";
                        item.errorMessage = error.localizedDescription ?: @"转换失败";
                        self.failedJobs += 1;
                    }
                    self.progress.doubleValue = self.completedJobs;
                    self.progressLabel.stringValue = [NSString stringWithFormat:@"%ld / %ld", (long)self.completedJobs, (long)self.totalJobs];
                    self.summaryLabel.stringValue = [NSString stringWithFormat:@"成功 %ld  失败 %ld", (long)self.successfulJobs, (long)self.failedJobs];
                    [self.tableView reloadData];
                    if (self.completedJobs == self.totalJobs) [self conversionFinished];
                }];
            }
        }];
    }
    [self.tableView reloadData];
}

- (void)conversionFinished {
    self.converting = NO;
    self.currentLabel.stringValue = @"转换完成";
    self.startButton.title = @"开始转换";
    [[NSSound soundNamed:@"Glass"] play];
    [self updateControls];
}

- (void)openOutput:(id)sender {
    NSURL *directory = nil;
    if (self.outputPopup.indexOfSelectedItem == 2) directory = self.customOutputDirectory;
    if (!directory && self.lastOutputs.count) directory = self.lastOutputs.firstObject.URLByDeletingLastPathComponent;
    if (directory) [NSWorkspace.sharedWorkspace openURL:directory];
}

- (void)resetProgress {
    self.completedJobs = 0;
    self.successfulJobs = 0;
    self.failedJobs = 0;
    self.totalJobs = 0;
    self.progress.doubleValue = 0;
    self.progress.maxValue = 1;
    self.progressLabel.stringValue = @"0 / 0";
    self.summaryLabel.stringValue = @"成功 0  失败 0";
    self.currentLabel.stringValue = @"";
    [self.lastOutputs removeAllObjects];
}

- (void)updateControls {
    FFFileItem *selected = self.singleSelectedItem;
    BOOL hasConvertible = NO;
    for (FFFileItem *item in self.files) if (item.kind != FFSourceKindUnsupported) { hasConvertible = YES; break; }
    self.cropButton.enabled = !self.converting && selected && selected.kind != FFSourceKindPDF && selected.kind != FFSourceKindUnsupported && self.tableView.selectedRowIndexes.count == 1;
    self.deleteButton.enabled = !self.converting && self.tableView.selectedRowIndexes.count > 0;
    self.startButton.enabled = !self.converting && hasConvertible && (self.outputPopup.indexOfSelectedItem != 2 || self.customOutputDirectory != nil);
    self.openOutputButton.enabled = self.lastOutputs.count > 0 || self.customOutputDirectory != nil;
}

- (void)showError:(NSString *)message {
    NSAlert *alert = [NSAlert new];
    alert.messageText = @"操作失败";
    alert.informativeText = message;
    [alert beginSheetModalForWindow:self.view.window completionHandler:nil];
}

@end

@interface FFAppDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) FFMainViewController *mainController;
@end

@implementation FFAppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    FFMainViewController *controller = [FFMainViewController new];
    self.mainController = controller;
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 940, 700)
                                              styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
                                                backing:NSBackingStoreBuffered
                                                  defer:NO];
    self.window.title = @"格式工厂";
    self.window.contentViewController = controller;
    self.window.minSize = NSMakeSize(820, 620);
    self.window.restorable = YES;
    self.window.restorationClass = nil;
    [self.window setFrameAutosaveName:@"FormatFactoryMainWindow"];
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];

    NSArray<NSString *> *arguments = NSProcessInfo.processInfo.arguments;
    if (arguments.count > 1) {
        NSMutableArray<NSURL *> *urls = [NSMutableArray array];
        for (NSInteger index = 1; index < arguments.count; index++) {
            NSString *path = arguments[index];
            if ([NSFileManager.defaultManager fileExistsAtPath:path]) {
                [urls addObject:[NSURL fileURLWithPath:path]];
            }
        }
        [controller addURLs:urls];
    }
}

- (void)application:(NSApplication *)application openFiles:(NSArray<NSString *> *)filenames {
    NSMutableArray<NSURL *> *urls = [NSMutableArray arrayWithCapacity:filenames.count];
    for (NSString *path in filenames) [urls addObject:[NSURL fileURLWithPath:path]];
    [self.mainController addURLs:urls];
    [application replyToOpenOrPrint:NSApplicationDelegateReplySuccess];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { return YES; }

@end

static void FFInstallMainMenu(void) {
    NSMenu *mainMenu = [NSMenu new];
    NSMenuItem *appItem = [NSMenuItem new];
    [mainMenu addItem:appItem];
    NSMenu *appMenu = [NSMenu new];
    NSString *quitTitle = @"退出格式工厂";
    NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:quitTitle action:@selector(terminate:) keyEquivalent:@"q"];
    [appMenu addItem:quit];
    appItem.submenu = appMenu;
    NSApp.mainMenu = mainMenu;
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSApplication *application = NSApplication.sharedApplication;
        [application setActivationPolicy:NSApplicationActivationPolicyRegular];
        FFAppDelegate *delegate = [FFAppDelegate new];
        application.delegate = delegate;
        FFInstallMainMenu();
        [application run];
    }
    return 0;
}
