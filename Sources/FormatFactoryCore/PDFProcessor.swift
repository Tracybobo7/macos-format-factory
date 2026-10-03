import Foundation
import CoreGraphics
import PDFKit

public enum PDFProcessor {
    public static func convert(
        url: URL,
        outputDirectory: URL,
        dpi: Int,
        jpegQuality: Double,
        namer: UniqueFileNamer
    ) throws -> [URL] {
        guard let document = PDFDocument(url: url) else {
            throw ConversionError.cannotReadPDF
        }
        guard !document.isLocked else {
            throw ConversionError.encryptedPDF
        }
        guard document.pageCount > 0 else {
            throw ConversionError.emptyPDF
        }

        let pageDigits = max(3, String(document.pageCount).count)
        let base = url.deletingPathExtension().lastPathComponent
        var outputs: [URL] = []
        outputs.reserveCapacity(document.pageCount)

        for index in 0..<document.pageCount {
            let output: URL = try autoreleasepool {
                guard let page = document.page(at: index) else {
                    throw ConversionError.cannotRenderPDFPage(index + 1)
                }

                guard let pageRef = page.pageRef else {
                    throw ConversionError.cannotRenderPDFPage(index + 1)
                }

                let pageBox = pageRef.getBoxRect(.mediaBox)
                let rotation = ((pageRef.rotationAngle % 360) + 360) % 360
                let swapsDimensions = rotation == 90 || rotation == 270
                let displayedWidth = swapsDimensions ? pageBox.height : pageBox.width
                let displayedHeight = swapsDimensions ? pageBox.width : pageBox.height
                let scale = CGFloat(dpi) / 72.0
                let width = max(1, Int(ceil(displayedWidth * scale)))
                let height = max(1, Int(ceil(displayedHeight * scale)))

                guard let bitmap = CGContext(
                    data: nil,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                ) else {
                    throw ConversionError.cannotRenderPDFPage(index + 1)
                }

                bitmap.setFillColor(CGColor(gray: 1, alpha: 1))
                bitmap.fill(CGRect(x: 0, y: 0, width: width, height: height))
                bitmap.saveGState()
                bitmap.scaleBy(x: scale, y: scale)
                let destinationRect = CGRect(x: 0, y: 0, width: displayedWidth, height: displayedHeight)
                let pageTransform = pageRef.getDrawingTransform(
                    .mediaBox,
                    rect: destinationRect,
                    rotate: 0,
                    preserveAspectRatio: true
                )
                bitmap.concatenate(pageTransform)
                bitmap.drawPDFPage(pageRef)
                bitmap.restoreGState()

                guard let image = bitmap.makeImage() else {
                    throw ConversionError.cannotRenderPDFPage(index + 1)
                }

                let pageNumber = String(format: "%0*d", pageDigits, index + 1)
                let destination = namer.reserve(
                    in: outputDirectory,
                    baseName: "\(base)_\(pageNumber)",
                    extension: "jpg"
                )
                do {
                    try ImageProcessor.encode(image, to: destination, format: .jpeg, jpegQuality: jpegQuality)
                    return destination
                } catch {
                    namer.release(destination)
                    throw error
                }
            }
            outputs.append(output)
        }
        return outputs
    }
}
