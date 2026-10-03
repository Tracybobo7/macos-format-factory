# Format Factory for macOS · 格式工厂

[English](README.en.md) · [简体中文](README.md)

A lightweight, local macOS utility for converting photos and PDFs. Drop files into the window, choose an output format, and start a batch. Your files stay on your Mac. No account, cloud service, or third-party runtime is required.

> Current version: 1.0.3 · Minimum OS: macOS 13 · License: [MIT](LICENSE)

## Features

| Input | Output | Notes |
| --- | --- | --- |
| HEIC | JPG, PNG | Applies iPhone/EXIF orientation and preserves the oriented pixel dimensions |
| JPG | PNG | Supports nondestructive cropping |
| PNG | JPG | Composites transparency over white for JPEG output |
| PDF | JPG | Exports every page separately at 150, 200, or 300 DPI |

- Import one or many files with the file picker or drag and drop. Conversion runs in the background with per-file status and overall progress.
- Set JPEG quality from 60% to 100% (90% by default). PDF rendering defaults to 200 DPI.
- Crop images with free, original, 1:1, 4:3, 3:4, 16:9, or 9:16 aspect ratios. The editor uses a low-resolution preview; export reads the full-resolution source. Original files are not modified.
- PDF pages are rendered one at a time. Landscape pages, 90°/270° page rotation, and offset page boxes are supported. A document named `Contract.pdf` produces `Contract_001.jpg`, `Contract_002.jpg`, and so on.
- Image batches use bounded concurrency based on CPU count. A failed file reports an error without stopping the remaining jobs.
- Existing output files are never silently overwritten: `IMG_001.jpg` becomes `IMG_001_2.jpg`, then `IMG_001_3.jpg` if needed.

## Use the app

1. Open `格式工厂.app` and click **选择文件** (Choose Files), or drop HEIC, JPG, PNG, and PDF files into the window. The app interface is currently in Chinese.
2. To crop, select one image and click **裁切选中图片** (Crop Selected Image).
3. Choose the image format, JPEG quality, PDF resolution, and output location.
4. Click **开始转换** (Start Conversion). When finished, click **打开输出文件夹** (Open Output Folder).

There are three output-location modes:

| Mode | Example |
| --- | --- |
| Beside original (default) | `Photos/IMG_001.jpg` |
| Create a `转换结果` folder | `Photos/转换结果/IMG_001.jpg` |
| Custom directory | The directory you select |

When a batch contains files from different source directories, the folder mode uses a `转换结果` folder beside each source. An existing folder is reused, and file-name collision protection still applies.

## Build from source

The repository contains two native macOS implementations: a SwiftUI interface and Swift conversion core under `Sources/`, and an AppKit interface with an Objective-C conversion core under `NativeFallback/`. The build script selects SwiftUI when a full Xcode installation is detected; otherwise it builds the AppKit implementation. The verified local app was built with AppKit. Both implementations use Apple system frameworks and follow the same feature design.

### Requirements

- macOS 13 or later.
- For the AppKit build: Apple Command Line Tools, including `clang` and `codesign`.
- For the SwiftUI build: a full Xcode version compatible with your macOS SDK.
- No Homebrew, Python, Node.js, Electron, or ImageMagick dependency.

### Build the app

```bash
git clone https://github.com/Tracybobo7/macos-format-factory.git
cd macos-format-factory
zsh scripts/build_app.sh
```

The script creates `格式工厂.app` at the repository root. You can select an implementation explicitly:

```bash
FORMAT_FACTORY_BUILD_VARIANT=swift zsh scripts/build_app.sh
FORMAT_FACTORY_BUILD_VARIANT=appkit zsh scripts/build_app.sh
```

The script ad-hoc signs the app for local use. This is not Apple Developer ID signing or notarization. When opening a downloaded build for the first time, macOS may require **Open** from Finder's context menu. Build on the target Mac to produce its native Apple Silicon or Intel architecture.

### Run tests

```bash
zsh scripts/test_core.sh
```

Optionally provide a real iPhone HEIC to exercise the system HEIC decoder and EXIF orientation path:

```bash
zsh scripts/test_core.sh "/path/to/photo.HEIC"
```

Integration tests cover image conversion, cropped dimensions, multi-page PDFs and DPI, rotated landscape pages, output-directory behavior, and name collisions. They create temporary samples and clean them up. On a Mac with full Xcode, run the Swift XCTest suite with:

```bash
swift test
```

The development Mac's Command Line Tools had a Swift compiler/SDK version mismatch, so the SwiftUI branch has not been compiled on that machine. The AppKit branch has been built and integration-tested. If `swift test` fails on your Mac, check the installed Xcode and SDK versions first.

## Repository layout

```text
Sources/FormatFactoryCore/       Swift conversion core
Sources/FormatFactoryApp/        SwiftUI interface and crop editor
NativeFallback/                 AppKit interface, Objective-C core, integration tests
Tests/FormatFactoryCoreTests/    Swift XCTest suite
Resources/                      Info.plist and app icon
scripts/build_app.sh             Build, bundle, and ad-hoc sign the app
scripts/test_core.sh             AppKit core integration tests
```

The app uses SwiftUI, AppKit, ImageIO, CoreGraphics, CoreImage, PDFKit, and UniformTypeIdentifiers. Conversion happens locally; the app does not upload your files.

## Known limitations

- Locked or encrypted PDFs fail with an error; there is no password-entry UI yet.
- Animated images, multi-frame HEIC, GIF, RAW, video, OCR, and Office documents are out of scope.
- Export preserves visible orientation and pixel dimensions but does not promise to copy all EXIF/GPS metadata.
- A very large PDF page can still use substantial memory at 300 DPI; pages are rendered and released one at a time.
- This public repository provides source code. Locally built apps are ad-hoc signed and not Apple-notarized.

## License

Released under the [MIT License](LICENSE).
