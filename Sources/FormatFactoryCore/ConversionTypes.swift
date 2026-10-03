import Foundation

public enum SourceKind: String, Sendable, Codable {
    case heic = "HEIC"
    case jpeg = "JPG"
    case png = "PNG"
    case pdf = "PDF"
    case unsupported = "不支持"

    public static func detect(from url: URL) -> SourceKind {
        switch url.pathExtension.lowercased() {
        case "heic", "heif": return .heic
        case "jpg", "jpeg": return .jpeg
        case "png": return .png
        case "pdf": return .pdf
        default: return .unsupported
        }
    }

    public var isImage: Bool {
        self == .heic || self == .jpeg || self == .png
    }
}

public enum OutputImageFormat: String, CaseIterable, Sendable, Codable {
    case jpeg = "JPG"
    case png = "PNG"

    public var fileExtension: String {
        switch self {
        case .jpeg: return "jpg"
        case .png: return "png"
        }
    }
}

public enum PDFResolution: Int, CaseIterable, Sendable, Codable {
    case standard = 150
    case high = 200
    case ultra = 300

    public var title: String {
        switch self {
        case .standard: return "标准 150 DPI"
        case .high: return "高清 200 DPI"
        case .ultra: return "超清 300 DPI"
        }
    }
}

/// A crop rectangle in the displayed, orientation-corrected image coordinate space.
/// The origin is at the top-left and every value is normalized to 0...1.
public struct NormalizedCrop: Sendable, Codable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public static let full = NormalizedCrop(x: 0, y: 0, width: 1, height: 1)

    public var clamped: NormalizedCrop {
        let safeX = min(max(x, 0), 1)
        let safeY = min(max(y, 0), 1)
        let safeWidth = min(max(width, 0.001), 1 - safeX)
        let safeHeight = min(max(height, 0.001), 1 - safeY)
        return NormalizedCrop(x: safeX, y: safeY, width: safeWidth, height: safeHeight)
    }
}

public struct ConversionRequest: Sendable {
    public let id: UUID
    public let inputURL: URL
    public let outputDirectory: URL
    public let sourceKind: SourceKind
    public let outputFormat: OutputImageFormat
    public let jpegQuality: Double
    public let pdfDPI: Int
    public let crop: NormalizedCrop?

    public init(
        id: UUID = UUID(),
        inputURL: URL,
        outputDirectory: URL,
        sourceKind: SourceKind? = nil,
        outputFormat: OutputImageFormat,
        jpegQuality: Double = 0.9,
        pdfDPI: Int = 200,
        crop: NormalizedCrop? = nil
    ) {
        self.id = id
        self.inputURL = inputURL
        self.outputDirectory = outputDirectory
        self.sourceKind = sourceKind ?? SourceKind.detect(from: inputURL)
        self.outputFormat = outputFormat
        self.jpegQuality = min(max(jpegQuality, 0.6), 1.0)
        self.pdfDPI = [150, 200, 300].contains(pdfDPI) ? pdfDPI : 200
        self.crop = crop
    }
}

public struct ConversionResult: Sendable {
    public let requestID: UUID
    public let outputURLs: [URL]

    public init(requestID: UUID, outputURLs: [URL]) {
        self.requestID = requestID
        self.outputURLs = outputURLs
    }
}

public enum ConversionError: LocalizedError, Sendable {
    case unsupportedFormat
    case cannotReadImage
    case cannotCreateImage
    case cannotEncodeImage
    case cannotReadPDF
    case encryptedPDF
    case emptyPDF
    case cannotRenderPDFPage(Int)
    case cannotCreateOutputDirectory(String)
    case cannotWriteFile(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat: return "不支持的文件格式"
        case .cannotReadImage: return "图片损坏或无法读取"
        case .cannotCreateImage: return "无法生成方向正确的图片"
        case .cannotEncodeImage: return "图片编码失败"
        case .cannotReadPDF: return "PDF 损坏或无法读取"
        case .encryptedPDF: return "PDF 已加密，暂不支持转换"
        case .emptyPDF: return "PDF 没有可转换的页面"
        case .cannotRenderPDFPage(let page): return "PDF 第 \(page) 页渲染失败"
        case .cannotCreateOutputDirectory(let path): return "无法创建输出目录：\(path)"
        case .cannotWriteFile(let path): return "无法写入：\(path)"
        }
    }
}

