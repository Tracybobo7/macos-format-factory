import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import FormatFactoryCore

enum FileStatus: Equatable {
    case waiting
    case converting
    case completed
    case failed(String)
    case cropped

    var title: String {
        switch self {
        case .waiting: return "等待转换"
        case .converting: return "转换中"
        case .completed: return "已完成"
        case .failed: return "失败"
        case .cropped: return "已裁切"
        }
    }

    var color: Color {
        switch self {
        case .waiting: return .secondary
        case .converting: return .accentColor
        case .completed: return .green
        case .failed: return .red
        case .cropped: return .orange
        }
    }

    var errorMessage: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}

struct ConversionFile: Identifiable {
    let id: UUID
    let url: URL
    let kind: SourceKind
    let byteCount: Int64
    var status: FileStatus
    var crop: NormalizedCrop?
    var outputURLs: [URL]

    init(url: URL) {
        self.id = UUID()
        self.url = url
        self.kind = SourceKind.detect(from: url)
        self.byteCount = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        self.status = kind == .unsupported ? .failed("不支持的文件格式") : .waiting
        self.crop = nil
        self.outputURLs = []
    }
}

enum OutputLocationMode: String, CaseIterable, Identifiable {
    case besideOriginal
    case resultFolder
    case custom

    var id: String { rawValue }
    var title: String {
        switch self {
        case .besideOriginal: return "原文件所在目录"
        case .resultFolder: return "新建“转换结果”文件夹"
        case .custom: return "自定义目录"
        }
    }
}

struct CropEditorContext: Identifiable {
    let id: UUID
    let url: URL
    let existingCrop: NormalizedCrop?
}

private struct JobOutcome: Sendable {
    let id: UUID
    let outputURLs: [URL]
    let errorMessage: String?
}

@MainActor
final class AppModel: ObservableObject {
    @Published var files: [ConversionFile] = []
    @Published var selection = Set<UUID>()
    @Published var imageOutputFormat: OutputImageFormat = .jpeg
    @Published var jpegQuality: Double {
        didSet { UserDefaults.standard.set(jpegQuality, forKey: "jpegQuality") }
    }
    @Published var pdfResolution: PDFResolution {
        didSet { UserDefaults.standard.set(pdfResolution.rawValue, forKey: "pdfDPI") }
    }
    @Published var outputLocationMode: OutputLocationMode = .besideOriginal
    @Published var customOutputDirectory: URL?
    @Published var isConverting = false
    @Published var completedCount = 0
    @Published var successCount = 0
    @Published var failureCount = 0
    @Published var currentFileName = ""
    @Published var cropEditorContext: CropEditorContext?

    private(set) var lastOutputURLs: [URL] = []
    private var conversionTask: Task<Void, Never>?

    init() {
        let storedQuality = UserDefaults.standard.double(forKey: "jpegQuality")
        self.jpegQuality = storedQuality == 0 ? 0.9 : min(max(storedQuality, 0.6), 1.0)
        let storedDPI = UserDefaults.standard.integer(forKey: "pdfDPI")
        self.pdfResolution = PDFResolution(rawValue: storedDPI) ?? .high
    }

    var progress: Double {
        let convertible = files.filter { $0.kind != .unsupported }.count
        return convertible == 0 ? 0 : Double(completedCount) / Double(convertible)
    }

    var canStart: Bool {
        !isConverting && files.contains(where: { $0.kind != .unsupported }) &&
        (outputLocationMode == .besideOriginal || customOutputDirectory != nil)
    }

    func addFiles(_ urls: [URL]) {
        let existing = Set(files.map { $0.url.standardizedFileURL.path })
        let regularFiles = urls.filter { url in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
        }
        var seen = existing
        for url in regularFiles {
            let standardized = url.standardizedFileURL
            guard seen.insert(standardized.path).inserted else { continue }
            files.append(ConversionFile(url: standardized))
        }
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.title = "选择要转换的文件"
        panel.prompt = "加入列表"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.heic, .jpeg, .png, .pdf]
        if panel.runModal() == .OK {
            addFiles(panel.urls)
        }
    }

    func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择输出目录"
        panel.prompt = "选择"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            customOutputDirectory = url
            outputLocationMode = .custom
        }
    }

    func removeSelected() {
        guard !isConverting else { return }
        files.removeAll { selection.contains($0.id) }
        selection.removeAll()
    }

    func clear() {
        guard !isConverting else { return }
        files.removeAll()
        selection.removeAll()
        resetProgress()
    }

    func revealSource(_ id: UUID) {
        guard let url = files.first(where: { $0.id == id })?.url else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func revealOutput(_ id: UUID) {
        guard let urls = files.first(where: { $0.id == id })?.outputURLs, !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }

    func openOutputFolder() {
        if outputLocationMode == .custom, let customOutputDirectory {
            NSWorkspace.shared.open(customOutputDirectory)
            return
        }
        if let first = lastOutputURLs.first {
            NSWorkspace.shared.open(first.deletingLastPathComponent())
        }
    }

    func beginCrop(_ id: UUID) {
        guard !isConverting,
              let file = files.first(where: { $0.id == id }),
              file.kind.isImage else { return }
        cropEditorContext = CropEditorContext(id: id, url: file.url, existingCrop: file.crop)
    }

    func finishCrop(id: UUID, crop: NormalizedCrop) {
        guard let index = files.firstIndex(where: { $0.id == id }) else { return }
        files[index].crop = crop.clamped
        files[index].status = .cropped
        cropEditorContext = nil
    }

    func startConversion() {
        guard canStart else { return }
        conversionTask?.cancel()
        resetProgress()
        isConverting = true

        var requests: [ConversionRequest] = []
        for index in files.indices where files[index].kind != .unsupported {
            files[index].status = .waiting
            files[index].outputURLs = []
            let file = files[index]
            let directory: URL
            if outputLocationMode == .custom, let customOutputDirectory {
                directory = customOutputDirectory
            } else if outputLocationMode == .resultFolder {
                directory = ConversionEngine.resultFolderOutputDirectory(for: file.url)
            } else {
                directory = ConversionEngine.defaultOutputDirectory(for: file.url)
            }
            requests.append(ConversionRequest(
                id: file.id,
                inputURL: file.url,
                outputDirectory: directory,
                sourceKind: file.kind,
                outputFormat: file.kind == .pdf ? .jpeg : imageOutputFormat,
                jpegQuality: jpegQuality,
                pdfDPI: pdfResolution.rawValue,
                crop: file.crop
            ))
        }

        conversionTask = Task { [weak self] in
            await self?.execute(requests)
        }
    }

    private func execute(_ requests: [ConversionRequest]) async {
        let concurrency = max(1, min(ProcessInfo.processInfo.activeProcessorCount, 6))
        let namer = UniqueFileNamer()

        await withTaskGroup(of: JobOutcome.self) { group in
            var next = 0

            func add(_ request: ConversionRequest) {
                group.addTask(priority: .userInitiated) {
                    if Task.isCancelled {
                        return JobOutcome(id: request.id, outputURLs: [], errorMessage: "已取消")
                    }
                    do {
                        let result = try ConversionEngine.convert(request, namer: namer)
                        return JobOutcome(id: request.id, outputURLs: result.outputURLs, errorMessage: nil)
                    } catch {
                        return JobOutcome(
                            id: request.id,
                            outputURLs: [],
                            errorMessage: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                        )
                    }
                }
            }

            let initialCount = min(concurrency, requests.count)
            for _ in 0..<initialCount {
                let request = requests[next]
                markConverting(request)
                add(request)
                next += 1
            }

            while let outcome = await group.next() {
                completedCount += 1
                if let index = files.firstIndex(where: { $0.id == outcome.id }) {
                    if let errorMessage = outcome.errorMessage {
                        files[index].status = .failed(errorMessage)
                        failureCount += 1
                    } else {
                        files[index].status = .completed
                        files[index].outputURLs = outcome.outputURLs
                        lastOutputURLs.append(contentsOf: outcome.outputURLs)
                        successCount += 1
                    }
                }

                if next < requests.count {
                    let request = requests[next]
                    markConverting(request)
                    add(request)
                    next += 1
                }
            }
        }

        currentFileName = ""
        isConverting = false
        NSSound(named: "Glass")?.play()
    }

    private func markConverting(_ request: ConversionRequest) {
        if let index = files.firstIndex(where: { $0.id == request.id }) {
            files[index].status = .converting
            currentFileName = files[index].url.lastPathComponent
        }
    }

    private func resetProgress() {
        completedCount = 0
        successCount = 0
        failureCount = 0
        currentFileName = ""
        lastOutputURLs = []
    }
}

extension Int64 {
    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}
