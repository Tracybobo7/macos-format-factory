import Foundation
import CoreGraphics

public enum ConversionEngine {
    public static func defaultOutputDirectory(for inputURL: URL) -> URL {
        inputURL.deletingLastPathComponent()
    }

    public static func resultFolderOutputDirectory(for inputURL: URL) -> URL {
        defaultOutputDirectory(for: inputURL)
            .appendingPathComponent("转换结果", isDirectory: true)
    }

    public static func convert(
        _ request: ConversionRequest,
        namer: UniqueFileNamer = UniqueFileNamer()
    ) throws -> ConversionResult {
        guard request.sourceKind != .unsupported else {
            throw ConversionError.unsupportedFormat
        }

        do {
            try FileManager.default.createDirectory(
                at: request.outputDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        } catch {
            throw ConversionError.cannotCreateOutputDirectory(request.outputDirectory.path)
        }

        if request.sourceKind == .pdf {
            let outputs = try PDFProcessor.convert(
                url: request.inputURL,
                outputDirectory: request.outputDirectory,
                dpi: request.pdfDPI,
                jpegQuality: request.jpegQuality,
                namer: namer
            )
            return ConversionResult(requestID: request.id, outputURLs: outputs)
        }

        let output = namer.reserve(
            in: request.outputDirectory,
            baseName: request.inputURL.deletingPathExtension().lastPathComponent,
            extension: request.outputFormat.fileExtension
        )

        do {
            let decoded = try ImageProcessor.loadOrientedImage(from: request.inputURL)
            let finalImage: CGImage
            if let crop = request.crop, crop != .full {
                finalImage = try ImageProcessor.crop(decoded, normalized: crop)
            } else {
                finalImage = decoded
            }
            try ImageProcessor.encode(
                finalImage,
                to: output,
                format: request.outputFormat,
                jpegQuality: request.jpegQuality
            )
            return ConversionResult(requestID: request.id, outputURLs: [output])
        } catch {
            namer.release(output)
            try? FileManager.default.removeItem(at: output)
            throw error
        }
    }
}
