import XCTest
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import FormatFactoryCore

final class ConversionTests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FormatFactoryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
    }

    func testHEICToJPGAndPNGAppliesEXIFOrientation() throws {
        let heic = temporaryDirectory.appendingPathComponent("iphone.HEIC")
        try writeImage(makeImage(width: 80, height: 40), to: heic, type: .heic, orientation: 6)

        let jpgDirectory = temporaryDirectory.appendingPathComponent("jpg", isDirectory: true)
        let jpgResult = try ConversionEngine.convert(ConversionRequest(
            inputURL: heic,
            outputDirectory: jpgDirectory,
            outputFormat: .jpeg,
            jpegQuality: 0.9
        ))
        XCTAssertEqual(jpgResult.outputURLs.count, 1)
        XCTAssertEqual(try pixelSize(of: jpgResult.outputURLs[0]), CGSize(width: 40, height: 80))

        let pngDirectory = temporaryDirectory.appendingPathComponent("png", isDirectory: true)
        let pngResult = try ConversionEngine.convert(ConversionRequest(
            inputURL: heic,
            outputDirectory: pngDirectory,
            outputFormat: .png
        ))
        XCTAssertEqual(pngResult.outputURLs.count, 1)
        XCTAssertEqual(try pixelSize(of: pngResult.outputURLs[0]), CGSize(width: 40, height: 80))
    }

    func testJPGAndPNGConversionAndCrop() throws {
        let sourceJPG = temporaryDirectory.appendingPathComponent("sample.jpg")
        let sourcePNG = temporaryDirectory.appendingPathComponent("sample.png")
        let image = makeImage(width: 120, height: 80)
        try writeImage(image, to: sourceJPG, type: .jpeg)
        try writeImage(image, to: sourcePNG, type: .png)

        let jpgToPNG = try ConversionEngine.convert(ConversionRequest(
            inputURL: sourceJPG,
            outputDirectory: temporaryDirectory.appendingPathComponent("from-jpg"),
            outputFormat: .png,
            crop: NormalizedCrop(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
        ))
        XCTAssertEqual(try pixelSize(of: jpgToPNG.outputURLs[0]), CGSize(width: 60, height: 40))

        let pngToJPG = try ConversionEngine.convert(ConversionRequest(
            inputURL: sourcePNG,
            outputDirectory: temporaryDirectory.appendingPathComponent("from-png"),
            outputFormat: .jpeg,
            jpegQuality: 0.75
        ))
        XCTAssertEqual(try pixelSize(of: pngToJPG.outputURLs[0]), CGSize(width: 120, height: 80))
    }

    func testPDFExportsEveryPageAtRequestedDPI() throws {
        let pdf = temporaryDirectory.appendingPathComponent("合同.pdf")
        try makePDF(at: pdf, pageCount: 3, pageSize: CGSize(width: 72, height: 36))

        let result = try ConversionEngine.convert(ConversionRequest(
            inputURL: pdf,
            outputDirectory: temporaryDirectory.appendingPathComponent("pdf-output"),
            outputFormat: .jpeg,
            jpegQuality: 0.9,
            pdfDPI: 150
        ))

        XCTAssertEqual(result.outputURLs.map(\.lastPathComponent), [
            "合同_001.jpg", "合同_002.jpg", "合同_003.jpg"
        ])
        for url in result.outputURLs {
            XCTAssertEqual(try pixelSize(of: url), CGSize(width: 150, height: 75))
        }
    }

    func testRotatedLandscapePDFUsesCompleteDisplayedPageBounds() throws {
        let source = temporaryDirectory.appendingPathComponent("rotated-source.pdf")
        let pdf = temporaryDirectory.appendingPathComponent("横版旋转页.pdf")
        try makePDF(at: source, pageCount: 1, pageSize: CGSize(width: 36, height: 72))
        guard let document = PDFDocument(url: source), let page = document.page(at: 0) else {
            throw ConversionError.cannotReadPDF
        }
        page.rotation = 90
        XCTAssertTrue(document.write(to: pdf))

        let result = try ConversionEngine.convert(ConversionRequest(
            inputURL: pdf,
            outputDirectory: temporaryDirectory.appendingPathComponent("rotated-output"),
            sourceKind: .pdf,
            outputFormat: .jpeg,
            pdfDPI: 150
        ))

        XCTAssertEqual(result.outputURLs.count, 1)
        XCTAssertEqual(try pixelSize(of: result.outputURLs[0]), CGSize(width: 150, height: 75))
    }

    func testExistingOutputIsNeverOverwritten() throws {
        let source = temporaryDirectory.appendingPathComponent("photo.png")
        try writeImage(makeImage(width: 32, height: 32), to: source, type: .png)
        let output = temporaryDirectory.appendingPathComponent("conflict", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try Data("existing".utf8).write(to: output.appendingPathComponent("photo.jpg"))

        let result = try ConversionEngine.convert(ConversionRequest(
            inputURL: source,
            outputDirectory: output,
            outputFormat: .jpeg
        ))
        XCTAssertEqual(result.outputURLs[0].lastPathComponent, "photo_2.jpg")
        XCTAssertEqual(try Data(contentsOf: output.appendingPathComponent("photo.jpg")), Data("existing".utf8))
    }

    func testDefaultOutputDirectoryIsSourceDirectory() throws {
        let source = temporaryDirectory
            .appendingPathComponent("相册", isDirectory: true)
            .appendingPathComponent("photo.png")
        XCTAssertEqual(
            ConversionEngine.defaultOutputDirectory(for: source),
            source.deletingLastPathComponent()
        )
        XCTAssertNotEqual(
            ConversionEngine.defaultOutputDirectory(for: source).lastPathComponent,
            "转换结果"
        )
    }

    func testResultFolderOutputDirectoryIsBesideSource() throws {
        let source = temporaryDirectory
            .appendingPathComponent("相册", isDirectory: true)
            .appendingPathComponent("photo.png")
        let output = ConversionEngine.resultFolderOutputDirectory(for: source)
        XCTAssertEqual(output, source.deletingLastPathComponent()
            .appendingPathComponent("转换结果", isDirectory: true))
    }

    private func makeImage(width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.15, green: 0.45, blue: 0.85, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0.95, green: 0.35, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height / 2))
        return context.makeImage()!
    }

    private func writeImage(
        _ image: CGImage,
        to url: URL,
        type: UTType,
        orientation: Int? = nil
    ) throws {
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            type.identifier as CFString,
            1,
            nil
        ) else {
            throw ConversionError.cannotEncodeImage
        }
        var properties: [CFString: Any] = [:]
        if let orientation { properties[kCGImagePropertyOrientation] = orientation }
        if type == .jpeg || type == .heic {
            properties[kCGImageDestinationLossyCompressionQuality] = 0.92
        }
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination), "Test image encoder unavailable for \(type.identifier)")
    }

    private func pixelSize(of url: URL) throws -> CGSize {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else {
            throw ConversionError.cannotReadImage
        }
        return CGSize(width: width.intValue, height: height.intValue)
    }

    private func makePDF(at url: URL, pageCount: Int, pageSize: CGSize) throws {
        guard let consumer = CGDataConsumer(url: url as CFURL) else {
            throw ConversionError.cannotWriteFile(url.path)
        }
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw ConversionError.cannotWriteFile(url.path)
        }
        for page in 0..<pageCount {
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(mediaBox)
            context.setFillColor(CGColor(red: CGFloat(page) / CGFloat(max(pageCount, 1)), green: 0.4, blue: 0.7, alpha: 1))
            context.fill(CGRect(x: 8, y: 8, width: 20, height: 12))
            context.endPDFPage()
        }
        context.closePDF()
    }
}
