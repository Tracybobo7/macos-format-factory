import AppKit
import SwiftUI
import UniformTypeIdentifiers
import FormatFactoryCore

struct ContentView: View {
    @StateObject private var model = AppModel()
    @State private var isDropTarget = false

    var body: some View {
        VStack(spacing: 14) {
            header
            importArea
            fileList
            settings
            progressArea
        }
        .padding(18)
        .sheet(item: $model.cropEditorContext) { context in
            CropEditorView(
                context: context,
                onCancel: { model.cropEditorContext = nil },
                onComplete: { crop in model.finishCrop(id: context.id, crop: crop) }
            )
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("格式工厂")
                    .font(.system(size: 26, weight: .semibold))
                Text("本地批量转换 · 文件不会上传")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("选择文件", systemImage: "plus") { model.chooseFiles() }
                .buttonStyle(.borderedProminent)
            Button("删除选中", systemImage: "minus") { model.removeSelected() }
                .disabled(model.selection.isEmpty || model.isConverting)
            Button("清空列表", systemImage: "trash") { model.clear() }
                .disabled(model.files.isEmpty || model.isConverting)
        }
    }

    private var importArea: some View {
        HStack(spacing: 10) {
            Image(systemName: "square.and.arrow.down")
                .font(.title2)
                .foregroundStyle(isDropTarget ? Color.accentColor : Color.secondary)
            Text("将 HEIC、JPG、PNG 或 PDF 文件拖到这里")
                .foregroundStyle(isDropTarget ? Color.primary : Color.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 54)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isDropTarget ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(isDropTarget ? Color.accentColor : Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [6]))
        )
        .onDrop(of: [UTType.fileURL.identifier], isTargeted: $isDropTarget, perform: handleDrop)
    }

    private var fileList: some View {
        GroupBox {
            if model.files.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.on.doc")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("尚未添加文件")
                        .font(.headline)
                    Text("选择文件，或直接拖入多个文件")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                List(selection: $model.selection) {
                    ForEach(model.files) { file in
                        FileRow(
                            file: file,
                            onCrop: { model.beginCrop(file.id) },
                            onRevealSource: { model.revealSource(file.id) },
                            onRevealOutput: { model.revealOutput(file.id) }
                        )
                        .tag(file.id)
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 210)
            }
        } label: {
            Label("待转换文件（\(model.files.count)）", systemImage: "list.bullet")
        }
    }

    private var settings: some View {
        GroupBox {
            HStack(alignment: .top, spacing: 26) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("图片输出格式").font(.headline)
                    Picker("图片输出格式", selection: $model.imageOutputFormat) {
                        ForEach(OutputImageFormat.allCases, id: \.self) { format in
                            Text(format.rawValue).tag(format)
                        }
                    }
                    .pickerStyle(.segmented)

                    HStack {
                        Text("JPG 质量")
                        Slider(value: $model.jpegQuality, in: 0.6...1.0, step: 0.01)
                        Text("\(Int(model.jpegQuality * 100))%")
                            .monospacedDigit()
                            .frame(width: 42, alignment: .trailing)
                    }
                    .disabled(model.imageOutputFormat != .jpeg)
                }
                .frame(maxWidth: .infinity)

                Divider()

                VStack(alignment: .leading, spacing: 9) {
                    Text("PDF 清晰度").font(.headline)
                    Picker("PDF 清晰度", selection: $model.pdfResolution) {
                        ForEach(PDFResolution.allCases, id: \.self) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxWidth: .infinity)

                Divider()

                VStack(alignment: .leading, spacing: 9) {
                    Text("输出位置").font(.headline)
                    Picker("输出位置", selection: $model.outputLocationMode) {
                        ForEach(OutputLocationMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    HStack {
                        Button("选择目录…") { model.chooseOutputDirectory() }
                        if model.outputLocationMode == .besideOriginal {
                            Text("直接输出到每个源文件所在目录")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if model.outputLocationMode == .resultFolder {
                            Text("在每个源文件目录下建立“转换结果”")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if let directory = model.customOutputDirectory {
                            Text(directory.path)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.vertical, 4)
        } label: {
            Label("转换设置", systemImage: "slider.horizontal.3")
        }
    }

    private var progressArea: some View {
        VStack(spacing: 9) {
            if model.isConverting || model.completedCount > 0 {
                HStack {
                    ProgressView(value: model.progress)
                    Text("\(model.completedCount) / \(model.files.filter { $0.kind != .unsupported }.count)")
                        .monospacedDigit()
                    Text(model.currentFileName.isEmpty ? "转换完成" : model.currentFileName)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("成功 \(model.successCount)  失败 \(model.failureCount)")
                        .monospacedDigit()
                }
            }
            HStack {
                Button("打开输出文件夹", systemImage: "folder") { model.openOutputFolder() }
                    .disabled(model.lastOutputURLs.isEmpty && model.customOutputDirectory == nil)
                Spacer()
                Button {
                    model.startConversion()
                } label: {
                    Label(model.isConverting ? "正在转换…" : "开始转换", systemImage: "arrow.triangle.2.circlepath")
                        .frame(minWidth: 130)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!model.canStart)
            }
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers where provider.canLoadObject(ofClass: NSURL.self) {
            accepted = true
            provider.loadObject(ofClass: NSURL.self) { object, _ in
                guard let nsURL = object as? NSURL else { return }
                Task { @MainActor in
                    model.addFiles([nsURL as URL])
                }
            }
        }
        return accepted
    }
}

private struct FileRow: View {
    let file: ConversionFile
    let onCrop: () -> Void
    let onRevealSource: () -> Void
    let onRevealOutput: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: file.kind == .pdf ? "doc.richtext" : "photo")
                .foregroundStyle(file.kind == .pdf ? Color.red : Color.accentColor)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(file.url.lastPathComponent).lineLimit(1)
                if let message = file.status.errorMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(file.kind.rawValue)
                .foregroundStyle(.secondary)
                .frame(width: 54)
            Text(file.byteCount.formattedFileSize)
                .foregroundStyle(.secondary)
                .frame(width: 75, alignment: .trailing)
            Text(file.status.title)
                .foregroundStyle(file.status.color)
                .frame(width: 74, alignment: .leading)
            if file.kind.isImage {
                Button("裁切", action: onCrop)
                    .buttonStyle(.borderless)
            }
            Menu {
                Button("在 Finder 中显示源文件", action: onRevealSource)
                Button("在 Finder 中显示转换结果", action: onRevealOutput)
                    .disabled(file.outputURLs.isEmpty)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 24)
        }
        .padding(.vertical, 3)
        .help(file.url.path)
    }
}
