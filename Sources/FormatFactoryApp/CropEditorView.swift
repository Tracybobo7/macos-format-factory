import CoreGraphics
import SwiftUI
import FormatFactoryCore

enum CropRatio: String, CaseIterable, Identifiable {
    case free = "自由"
    case original = "原始比例"
    case square = "1:1"
    case fourThree = "4:3"
    case threeFour = "3:4"
    case sixteenNine = "16:9"
    case nineSixteen = "9:16"

    var id: String { rawValue }

    func aspectRatio(imageAspect: CGFloat) -> CGFloat? {
        switch self {
        case .free: return nil
        case .original: return imageAspect
        case .square: return 1
        case .fourThree: return 4 / 3
        case .threeFour: return 3 / 4
        case .sixteenNine: return 16 / 9
        case .nineSixteen: return 9 / 16
        }
    }
}

struct CropEditorView: View {
    let context: CropEditorContext
    let onCancel: () -> Void
    let onComplete: (NormalizedCrop) -> Void

    @State private var preview: CGImage?
    @State private var loadError: String?
    @State private var crop: NormalizedCrop
    @State private var ratio: CropRatio = .free

    init(
        context: CropEditorContext,
        onCancel: @escaping () -> Void,
        onComplete: @escaping (NormalizedCrop) -> Void
    ) {
        self.context = context
        self.onCancel = onCancel
        self.onComplete = onComplete
        _crop = State(initialValue: context.existingCrop ?? NormalizedCrop(x: 0.1, y: 0.1, width: 0.8, height: 0.8))
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("裁切图片")
                    .font(.title2.weight(.semibold))
                Text(context.url.lastPathComponent)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
            }

            Group {
                if let preview {
                    CropCanvas(image: preview, crop: $crop, ratio: $ratio)
                } else if let loadError {
                    ContentUnavailableView("无法预览图片", systemImage: "exclamationmark.triangle", description: Text(loadError))
                } else {
                    ProgressView("正在生成预览…")
                }
            }
            .frame(minWidth: 720, minHeight: 480)
            .background(Color.black.opacity(0.92))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack {
                Text("比例")
                Picker("比例", selection: $ratio) {
                    ForEach(CropRatio.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 560)

                Button("重置裁切") {
                    ratio = .free
                    crop = NormalizedCrop(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
                }
                Spacer()
                Button("取消", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("完成") { onComplete(crop.clamped) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(preview == nil)
            }
        }
        .padding(18)
        .task {
            do {
                preview = try await Task.detached(priority: .userInitiated) {
                    try ImageProcessor.makePreview(from: context.url)
                }.value
            } catch {
                loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
        }
    }
}

private struct CropCanvas: View {
    let image: CGImage
    @Binding var crop: NormalizedCrop
    @Binding var ratio: CropRatio

    private var imageAspect: CGFloat { CGFloat(image.width) / CGFloat(image.height) }

    var body: some View {
        GeometryReader { proxy in
            let fitted = fittedRect(for: proxy.size)
            ZStack {
                Color.black
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: fitted.width, height: fitted.height)
                    .position(x: fitted.midX, y: fitted.midY)

                CropOverlay(
                    crop: $crop,
                    ratio: ratio,
                    imageAspect: imageAspect,
                    canvasSize: fitted.size
                )
                .frame(width: fitted.width, height: fitted.height)
                .position(x: fitted.midX, y: fitted.midY)
            }
            .onChange(of: ratio) { newValue in
                guard let target = newValue.aspectRatio(imageAspect: imageAspect) else { return }
                crop = centeredCrop(for: target)
            }
        }
    }

    private func fittedRect(for container: CGSize) -> CGRect {
        let containerAspect = container.width / max(container.height, 1)
        let size: CGSize
        if containerAspect > imageAspect {
            size = CGSize(width: container.height * imageAspect, height: container.height)
        } else {
            size = CGSize(width: container.width, height: container.width / imageAspect)
        }
        return CGRect(
            x: (container.width - size.width) / 2,
            y: (container.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    private func centeredCrop(for targetAspect: CGFloat) -> NormalizedCrop {
        var width: CGFloat = 0.84
        var height = width * imageAspect / targetAspect
        if height > 0.84 {
            height = 0.84
            width = height * targetAspect / imageAspect
        }
        return NormalizedCrop(
            x: Double((1 - width) / 2),
            y: Double((1 - height) / 2),
            width: Double(width),
            height: Double(height)
        )
    }
}

private enum CropCorner: CaseIterable, Identifiable {
    case topLeft, topRight, bottomLeft, bottomRight
    var id: Self { self }
}

private struct CropOverlay: View {
    @Binding var crop: NormalizedCrop
    let ratio: CropRatio
    let imageAspect: CGFloat
    let canvasSize: CGSize
    @State private var moveStart: NormalizedCrop?

    private var cropRect: CGRect {
        CGRect(
            x: CGFloat(crop.x) * canvasSize.width,
            y: CGFloat(crop.y) * canvasSize.height,
            width: CGFloat(crop.width) * canvasSize.width,
            height: CGFloat(crop.height) * canvasSize.height
        )
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Path { path in
                path.addRect(CGRect(origin: .zero, size: canvasSize))
                path.addRect(cropRect)
            }
            .fill(Color.black.opacity(0.58), style: FillStyle(eoFill: true))
            .allowsHitTesting(false)

            Rectangle()
                .stroke(Color.white, lineWidth: 2)
                .background(Color.clear)
                .frame(width: cropRect.width, height: cropRect.height)
                .position(x: cropRect.midX, y: cropRect.midY)
                .contentShape(Rectangle())
                .gesture(moveGesture)

            Path { path in
                let thirdW = cropRect.width / 3
                let thirdH = cropRect.height / 3
                for index in 1...2 {
                    let x = cropRect.minX + thirdW * CGFloat(index)
                    path.move(to: CGPoint(x: x, y: cropRect.minY))
                    path.addLine(to: CGPoint(x: x, y: cropRect.maxY))
                    let y = cropRect.minY + thirdH * CGFloat(index)
                    path.move(to: CGPoint(x: cropRect.minX, y: y))
                    path.addLine(to: CGPoint(x: cropRect.maxX, y: y))
                }
            }
            .stroke(Color.white.opacity(0.42), lineWidth: 0.7)
            .allowsHitTesting(false)

            ForEach(CropCorner.allCases) { corner in
                CropHandle(
                    crop: $crop,
                    corner: corner,
                    canvasSize: canvasSize,
                    targetAspect: ratio.aspectRatio(imageAspect: imageAspect),
                    imageAspect: imageAspect
                )
                .position(handlePosition(corner))
            }
        }
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if moveStart == nil { moveStart = crop }
                guard let start = moveStart else { return }
                let dx = Double(value.translation.width / max(canvasSize.width, 1))
                let dy = Double(value.translation.height / max(canvasSize.height, 1))
                crop.x = min(max(start.x + dx, 0), 1 - start.width)
                crop.y = min(max(start.y + dy, 0), 1 - start.height)
            }
            .onEnded { _ in moveStart = nil }
    }

    private func handlePosition(_ corner: CropCorner) -> CGPoint {
        switch corner {
        case .topLeft: return CGPoint(x: cropRect.minX, y: cropRect.minY)
        case .topRight: return CGPoint(x: cropRect.maxX, y: cropRect.minY)
        case .bottomLeft: return CGPoint(x: cropRect.minX, y: cropRect.maxY)
        case .bottomRight: return CGPoint(x: cropRect.maxX, y: cropRect.maxY)
        }
    }
}

private struct CropHandle: View {
    @Binding var crop: NormalizedCrop
    let corner: CropCorner
    let canvasSize: CGSize
    let targetAspect: CGFloat?
    let imageAspect: CGFloat
    @State private var start: NormalizedCrop?

    var body: some View {
        Circle()
            .fill(Color.white)
            .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 1))
            .frame(width: 14, height: 14)
            .contentShape(Rectangle().inset(by: -10))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if start == nil { start = crop }
                        guard let start else { return }
                        resize(from: start, translation: value.translation)
                    }
                    .onEnded { _ in start = nil }
            )
    }

    private func resize(from start: NormalizedCrop, translation: CGSize) {
        let dx = Double(translation.width / max(canvasSize.width, 1))
        let dy = Double(translation.height / max(canvasSize.height, 1))
        let left = start.x
        let right = start.x + start.width
        let top = start.y
        let bottom = start.y + start.height
        let minimum = 0.03

        let movingRight = corner == .topRight || corner == .bottomRight
        let movingBottom = corner == .bottomLeft || corner == .bottomRight
        let fixedX = movingRight ? left : right
        let fixedY = movingBottom ? top : bottom
        var movingX = movingRight ? right + dx : left + dx
        var movingY = movingBottom ? bottom + dy : top + dy
        movingX = min(max(movingX, 0), 1)
        movingY = min(max(movingY, 0), 1)

        if let targetAspect {
            var width = max(abs(movingX - fixedX), minimum)
            var height = width * Double(imageAspect / targetAspect)
            let maxWidth = movingRight ? 1 - fixedX : fixedX
            let maxHeight = movingBottom ? 1 - fixedY : fixedY
            if height > maxHeight {
                height = maxHeight
                width = height * Double(targetAspect / imageAspect)
            }
            width = min(width, maxWidth)
            height = min(height, maxHeight)
            let newX = movingRight ? fixedX : fixedX - width
            let newY = movingBottom ? fixedY : fixedY - height
            crop = NormalizedCrop(x: newX, y: newY, width: width, height: height).clamped
        } else {
            let newX = min(fixedX, movingX)
            let newY = min(fixedY, movingY)
            let width = max(abs(movingX - fixedX), minimum)
            let height = max(abs(movingY - fixedY), minimum)
            crop = NormalizedCrop(x: newX, y: newY, width: width, height: height).clamped
        }
    }
}

