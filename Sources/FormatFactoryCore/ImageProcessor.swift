import Foundation
import CoreGraphics
import CoreImage
import ImageIO
import UniformTypeIdentifiers

public enum ImageProcessor {
    private static let context = CIContext(options: [
        .cacheIntermediates: false,
        .useSoftwareRenderer: false
    ])

    public static func makePreview(from url: URL, maxPixelSize: Int = 1600) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw ConversionError.cannotReadImage
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(256, maxPixelSize),
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            throw ConversionError.cannotReadImage
        }
        return thumbnail
    }

    public static func loadOrientedImage(from url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let rawImage = CGImageSourceCreateImageAtIndex(source, 0, [
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else {
            throw ConversionError.cannotReadImage
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientation = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.int32Value ?? 1
        let oriented = CIImage(cgImage: rawImage).oriented(forExifOrientation: orientation)
        let extent = oriented.extent.integral

        guard extent.width > 0, extent.height > 0,
              let result = context.createCGImage(oriented, from: extent) else {
            throw ConversionError.cannotCreateImage
        }
        return result
    }

    public static func crop(_ image: CGImage, normalized crop: NormalizedCrop) throws -> CGImage {
        let crop = crop.clamped
        let imageWidth = CGFloat(image.width)
        let imageHeight = CGFloat(image.height)

        // SwiftUI presents images with a top-left origin; Core Image uses bottom-left.
        var rect = CGRect(
            x: CGFloat(crop.x) * imageWidth,
            y: CGFloat(1 - crop.y - crop.height) * imageHeight,
            width: CGFloat(crop.width) * imageWidth,
            height: CGFloat(crop.height) * imageHeight
        ).integral
        rect = rect.intersection(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))

        guard rect.width >= 1, rect.height >= 1 else {
            throw ConversionError.cannotCreateImage
        }

        let source = CIImage(cgImage: image)
        let cropped = source.cropped(to: rect)
        guard let result = context.createCGImage(cropped, from: rect) else {
            throw ConversionError.cannotCreateImage
        }
        return result
    }

    public static func encode(
        _ image: CGImage,
        to url: URL,
        format: OutputImageFormat,
        jpegQuality: Double
    ) throws {
        let finalImage: CGImage
        if format == .jpeg {
            finalImage = try flattenTransparency(on: image)
        } else {
            finalImage = image
        }

        let type: CFString = format == .jpeg ? UTType.jpeg.identifier as CFString : UTType.png.identifier as CFString
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type, 1, nil) else {
            throw ConversionError.cannotWriteFile(url.path)
        }

        var properties: [CFString: Any] = [kCGImagePropertyOrientation: 1]
        if format == .jpeg {
            properties[kCGImageDestinationLossyCompressionQuality] = min(max(jpegQuality, 0.6), 1.0)
        }
        CGImageDestinationAddImage(destination, finalImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            try? FileManager.default.removeItem(at: url)
            throw ConversionError.cannotEncodeImage
        }
    }

    private static func flattenTransparency(on image: CGImage) throws -> CGImage {
        guard let bitmap = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else {
            throw ConversionError.cannotCreateImage
        }
        bitmap.setFillColor(CGColor(gray: 1, alpha: 1))
        bitmap.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        bitmap.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let result = bitmap.makeImage() else {
            throw ConversionError.cannotCreateImage
        }
        return result
    }
}

