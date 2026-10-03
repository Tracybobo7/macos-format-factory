# 格式工厂 · Format Factory for macOS

[简体中文](README.md) · [English](README.en.md)

一款轻量的 macOS 本地图片与 PDF 格式转换工具。拖入文件、选择格式、点击“开始转换”即可批量处理。文件始终留在本机；应用不需要账号、云服务或第三方运行环境。

> 当前版本：1.0.3 · 最低系统：macOS 13 · 开源协议：[MIT](LICENSE)

## 功能

| 输入 | 输出 | 说明 |
| --- | --- | --- |
| HEIC | JPG、PNG | 处理 iPhone 照片方向，保留方向校正后的原始像素尺寸 |
| JPG | PNG | 支持非破坏性裁切 |
| PNG | JPG | 透明区域在 JPG 中使用白色背景 |
| PDF | JPG | 每页单独导出，支持 150、200、300 DPI |

- 可通过文件选择器或拖拽一次导入多个文件；转换在后台运行，显示逐文件状态和总体进度。
- JPG 质量可设为 60%～100%，默认为 90%；PDF 默认 200 DPI。
- 图片裁切支持自由、原始比例、1:1、4:3、3:4、16:9、9:16。预览使用缩略图，最终导出重新读取原始分辨率图片；源文件不会被修改。
- PDF 逐页渲染，兼容横版、90°/270°旋转页面及非零页框偏移；输出如 `合同_001.jpg`、`合同_002.jpg`。
- 图片转换按 CPU 核心数限制并发；单个文件失败会显示错误，并继续处理其他文件。
- 已有文件不会被覆盖：`IMG_001.jpg` 冲突时依次生成 `IMG_001_2.jpg`、`IMG_001_3.jpg`。

## 使用方法

1. 打开 `格式工厂.app`，点击“选择文件”或将 HEIC、JPG、PNG、PDF 拖入窗口。
2. 如需裁切，选中一张图片后点击“裁切选中图片”。
3. 选择输出格式、JPG 质量、PDF 清晰度和输出位置。
4. 点击“开始转换”，完成后使用“打开输出文件夹”。

“输出位置”有三个选项：

| 选项 | 输出示例 |
| --- | --- |
| 原文件所在目录（默认） | `照片/IMG_001.jpg` |
| 新建“转换结果”文件夹 | `照片/转换结果/IMG_001.jpg` |
| 自定义目录 | 输出到你选定的目录 |

批量文件来自不同目录时，“新建文件夹”模式会在每个源文件目录下使用各自的 `转换结果` 文件夹。文件夹已存在时会复用，输出文件仍按重名规则避让。

## 从源码构建

项目提供两套 macOS 原生实现：`Sources/` 中的 SwiftUI + Swift 核心，以及 `NativeFallback/` 中的 AppKit + Objective-C 实现。构建脚本在检测到完整 Xcode 时默认选择 SwiftUI；没有完整 Xcode 时选择 AppKit。已验证的本机可运行 App 使用 AppKit 构建。两套实现共用相同的功能设计和 macOS 系统框架。

### 环境

- macOS 13 或更新版本。
- 构建 AppKit 版本：Apple Command Line Tools（提供 `clang`、`codesign`）。
- 构建 SwiftUI 版本：与当前 macOS SDK 匹配的完整 Xcode。
- 不需要 Homebrew、Python、Node.js、Electron 或 ImageMagick。

### 构建 App

```bash
git clone https://github.com/Tracybobo7/macos-format-factory.git
cd macos-format-factory
./scripts/build_app.sh
```

成功后在项目根目录生成 `格式工厂.app`。指定实现：

```bash
FORMAT_FACTORY_BUILD_VARIANT=swift ./scripts/build_app.sh
FORMAT_FACTORY_BUILD_VARIANT=appkit ./scripts/build_app.sh
```

脚本会对 App 做本机 ad-hoc 签名。这适合本地构建与使用，不等于 Apple Developer ID 签名或公证。首次从外部下载 App 时，macOS 可能要求在 Finder 中右键选择“打开”。Apple Silicon 与 Intel Mac 可分别在目标机器上构建对应架构。

### 测试

```bash
./scripts/test_core.sh
```

可选传入一张真实 iPhone HEIC，额外验证系统 HEIC 解码和 EXIF 方向：

```bash
./scripts/test_core.sh "/path/to/photo.HEIC"
```

测试覆盖格式转换、裁切后像素尺寸、PDF 多页与 DPI、横版旋转页面、输出目录行为及重名保护。测试在系统临时目录中生成样本并清理。SwiftUI 实现的 XCTest 可在完整 Xcode 环境中运行：

```bash
swift test
```

本项目开发机上的 Command Line Tools 曾存在 Swift 编译器与 SDK 版本不匹配，因此 SwiftUI 分支尚未在该机器完成编译验证；AppKit 分支已通过本机编译和集成测试。若 `swift test` 在你的机器上失败，请先检查 Xcode 与 SDK 是否匹配。

## 项目结构

```text
Sources/FormatFactoryCore/       Swift 转换核心
Sources/FormatFactoryApp/        SwiftUI 界面和裁切编辑器
NativeFallback/                 AppKit 界面、Objective-C 转换核心与集成测试
Tests/FormatFactoryCoreTests/    Swift XCTest
Resources/                      Info.plist 和 App 图标
scripts/build_app.sh             构建、封装与本机签名
scripts/test_core.sh             AppKit 核心集成测试
```

主要使用 SwiftUI、AppKit、ImageIO、CoreGraphics、CoreImage、PDFKit 和 UniformTypeIdentifiers。转换完全在本机进行；应用本身不上传文件。

## 已知限制

- 加密且未解锁的 PDF 会显示失败；目前没有 PDF 密码输入界面。
- 动态图片、多帧 HEIC、GIF、RAW、视频、OCR 和 Office 文档不在支持范围内。
- 输出保留可见方向与像素尺寸，但不保证复制全部 EXIF/GPS 元数据。
- 300 DPI 的超大 PDF 单页仍可能占用较多内存；程序按页渲染和释放。
- 公开仓库提供源码；本机生成的 App 采用 ad-hoc 签名，尚未经过 Apple 公证。

## 许可证

本项目采用 [MIT License](LICENSE)。
