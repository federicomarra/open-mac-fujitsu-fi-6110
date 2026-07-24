# fi-6110 Scanner

[![Build & Release](https://img.shields.io/github/actions/workflow/status/federicomarra/open-mac-fujitsu-fi-6110/build-release.yml?style=flat-square&logo=githubactions&logoColor=white&label=build)](https://github.com/federicomarra/open-mac-fujitsu-fi-6110/actions/workflows/build-release.yml)
[![Latest release](https://img.shields.io/github/v/release/federicomarra/open-mac-fujitsu-fi-6110?style=flat-square&logo=github&label=release&color=lightgreen)](https://github.com/federicomarra/open-mac-fujitsu-fi-6110/releases/latest)

<!-- [![Downloads](https://img.shields.io/github/downloads/federicomarra/open-mac-fujitsu-fi-6110/total?style=flat-square&logo=github&label=downloads&color=success)](https://github.com/federicomarra/open-mac-fujitsu-fi-6110/releases) -->

[![Swift](https://img.shields.io/badge/Swift-5.9-F05138?style=flat-square&logo=swift&logoColor=white)](https://swift.org)
[![macOS](https://img.shields.io/badge/macOS-12.0%2B-000000?style=flat-square&logo=apple&logoColor=white)](https://www.apple.com/macos)
[![Universal](https://img.shields.io/badge/binary-Apple%20Silicon%20%2B%20Intel-555555?style=flat-square&logo=apple&logoColor=white)](https://developer.apple.com/documentation/apple-silicon/building-a-universal-macos-binary)
[![License](https://img.shields.io/badge/license-MIT-blue?style=flat-square)](LICENSE)

A native macOS app that brings the **Fujitsu fi-6110** USB document scanner back
to life on modern Macs. Fujitsu stopped supporting the fi-6110 at macOS 10.14,
so this app bundles the open-source [SANE](http://www.sane-project.org)
`fujitsu` backend and [libusb](https://libusb.info) *inside* the .app — nothing
else to install: plug in the scanner, open the app, scan.

Modeled on Apple's Image Capture ("Acquisizione Immagine"): thumbnails on the
left, options on the right, one big Scan button.

**Features**
- Universal binary (Apple Silicon + Intel), macOS 12 Monterey or newer
- Bilingual UI — Italian / English, follows the system language
- Color / grayscale / black & white, 150–600 dpi, A4 / A5 / Letter / Legal
- Single-sided or duplex (both sides in one pass, via the ADF)
- Output: multi-page PDF, **searchable PDF** (on-device OCR via Apple Vision,
  Italian + English), JPEG, PNG, TIFF
- Auto-straighten (deskew) and blank-page skipping (done by the SANE backend)
- Auto-rotate upside-down pages — detected on-device from the text via Apple
  Vision (both faces of a duplex sheet flip together)
- Reorder or reverse pages after scanning — the saved file is rewritten in place
- Optional overwrite mode, or auto-numbered filenames that never clobber
- No drivers, no Homebrew, no setup — fully self-contained .app

## Building

Requires Xcode (full app, not just CLT) on Apple Silicon. Three steps:

```sh
vendor/build-sane.sh      # 1. build universal libusb + SANE fujitsu backend
packaging/make-app.sh     # 2. build the app → dist/fi-6110 Scanner.app
packaging/make-dmg.sh     # 3. wrap it in an installer → dist/fi-6110 Scanner.dmg
```

The DMG contains the app, an *Applicazioni* drag-target, and `Leggimi.rtf`
with first-launch instructions in Italian (the app is ad-hoc signed, so the
very first launch on another Mac needs right-click → Open).

## How it works

```
📁 Sources/
├── ⚙️ CSane/          C shim bridging SANE API types (CSaneShim.h / shim.c) to Swift
├── 🧠 ScannerCore/    Core engine: dlopens libsane-fujitsu.so, drives ADF page loop,
│                      converts raw frames to CGImage; auto-rotates upside-down pages
│                      (OrientationCorrector) & handles PDF/OCR writers (PDFBuilder / OCREngine)
├── 🖥️ FiScanner/      SwiftUI app interface (macOS 12+), bilingual (Italian / English)
└── 🛠️ SaneHarness/    Developer CLI: list, scan, convert, resave & image test suite

📁 vendor/             Compiles libusb & sane-backends from pinned sources for arm64 + x86_64,
                       then lipo-merges universal binaries into vendor/out (macOS 12.0+)

📁 packaging/          App icons, Info.plist, .app bundle assembly, ad-hoc signing & DMG installer
```

Notable choices:
- The SANE backend module is loaded with `dlopen` (it's an MH_BUNDLE); its
  `@loader_path` rpath finds libusb sitting next to it, so the pair works from
  any directory — `vendor/out/lib` in development, `Contents/Frameworks` in
  the app.
- Only the `fujitsu` backend is built; `SANE_CONFIG_DIR` points into the app's
  `Resources/sane.d`.
- The app is intentionally **not sandboxed**: user-space USB access via libusb
  requires it.

## App Architecture

```
╔═══════════════════════════════════════════════════════════════════════════════════╗
║   fi-6110 Scanner.app (universal binary, macOS 12.0+)                             ║
║   ┌─────────────────────────────────────────────────────────────────────────────┐ ║
║   │ Contents/                                                                   │ ║
║   │   ┌─────────────────────────────────────────────────────────────────────┐   │ ║
║   │   │ MacOS/                                                              │   │ ║
║   │   │   ┌─────────────────────────────────────────────────────────────┐   │   │ ║
║   │   │   │ FiScanner           (SwiftUI → ScannerCore → CSane)         │   │   │ ║
║   │   │   └─────────────────────────────────────────────────────────────┘   │   │ ║
║   │   │                                                                     │   │ ║
║   │   │ Frameworks/                                                         │   │ ║
║   │   │   │ libsane-fujitsu.so        (SANE backend, dlopen'd via CSane)    │   │ ║
║   │   │   │ libusb-1.0.0.dylib        (loaded beside the backend)           │   │ ║
║   │   │   └─────────────────────────────────────────────────────────────┘   │   │ ║
║   │   │                                                                     │   │ ║
║   │   │ Resources/                                                          │   │ ║
║   │   │   │ en.lproj/Localizable.strings                                    │   │ ║
║   │   │   │ it.lproj/Localizable.strings                                    │   │ ║
║   │   │   │ AppIcon.icns                                                    │   │ ║
║   │   │   │ sane.d/                                                         │   │ ║
║   │   │   │   │ fujitsu.conf                     (USB vendor:product IDs)   │   │ ║
║   │   │   │   │   └─ read by the backend via SANE_CONFIG_DIR                │   │ ║
║   │   │   └─────────────────────────────────────────────────────────────┘   │   │ ║
║   │   └─────────────────────────────────────────────────────────────────────┘   │ ║
║   └─────────────────────────────────────────────────────────────────────────────┘ ║
╚═══════════════════════════════════════════════════════════════════════════════════╝

- `FiScanner` (SwiftUI) → loads `CSane` (C shim) → `dlopen("libsane-fujitsu.so")` → SANE backend → libusb-1.0.0.dylib
- SANE backend reads `fujitsu.conf` via `SANE_CONFIG_DIR` → `Resources/sane.d`; the app `dlopen`s the `.so` from `Frameworks/`
- App *not* sandboxed: USB access via libusb requires it
```

## Code Architecture

```
╔═══════════════════════════════════════════════════════════════════════════════════╗
║                             CODE ARCHITECTURE & FLOW                              ║
║                                                                                   ║
║  ┌─────────────────────────┐         ┌─────────────────────────────────────────┐  ║
║  │   FiScanner (GUI App)   │         │            SaneHarness (CLI)            │  ║
║  │  - App.swift            │         │  - main.swift                           │  ║
║  │  - ContentView.swift    │         │  (Headless scanning, testing & OCR)     │  ║
║  │  - ScannerViewModel.swift ──────┐ └────────────────────┬────────────────────┘  ║
║  └─────────────────────────┘       │                      │                       ║
║                                    ▼                      ▼                       ║
║  ┌─────────────────────────────────────────────────────────────────────────────┐  ║
║  │                           ScannerCore Target                                │  ║
║  │                                                                             │  ║
║  │  ┌───────────────────────────┐         ┌─────────────────────────────────┐  ║  ║
║  │  │   SANE Device Control     │         │   Image & Document Processing   │  ║  ║
║  │  │  - SaneScanner.swift      │         │  - ImageBuilder.swift           │  ║  ║
║  │  │  - SaneAPI.swift          │         │  - PDFBuilder.swift             │  ║  ║
║  │  │  - SaneTypes.swift        │         │  - OCREngine (Apple Vision)     │  ║  ║
║  │  └─────────────┬─────────────┘         │  - OrientationCorrector.swift   │  ║  ║
║  │                │                       │  - ScanWriter.swift             │  ║  ║
║  │                │                       └─────────────────────────────────┘  ║  ║
║  └────────────────┼────────────────────────────────────────────────────────────┘  ║
║                   │                                                               ║
║                   ▼                                                               ║
║  ┌─────────────────────────────────────────────────────────────────────────────┐  ║
║  │                             CSane Shim Target                               │  ║
║  │  - shim.c / CSaneShim.h (C bridging header for Swift)                       │  ║
║  └────────────────┬────────────────────────────────────────────────────────────┘  ║
║                   │ (dlopen runtime link)                                         ║
║                   ▼                                                               ║
║  ┌─────────────────────────────────────────────────────────────────────────────┐  ║
║  │                       Bundled SANE & USB Libraries                          │  ║
║  │  libsane-fujitsu.so ───► libusb-1.0.0.dylib ───► Fujitsu fi-6110 Hardware   │  ║
║  └─────────────────────────────────────────────────────────────────────────────┘  ║
╚═══════════════════════════════════════════════════════════════════════════════════╝
```

- **`FiScanner`**: SwiftUI application layer (`App`, `ContentView`, `ScannerViewModel`, `SettingsView`, `TutorialView`).
- **`ScannerCore`**: Engine managing scanner options (`SaneScanner`, `SaneAPI`, `SaneTypes`), image rendering (`ImageBuilder`), page output (`PDFBuilder`, `ScanWriter`), auto-rotation of upside-down pages (`OrientationCorrector`), and Vision OCR (`OCREngine`). Deskew and blank-page skipping are done by the SANE backend itself.
- **`CSane`**: C shim (`shim.c` / `CSaneShim.h`) bridging the SANE headers (`sane/sane.h`) to Swift.
- **`SaneHarness`**: Command-line developer harness for testing hardware communication and document processing.

## Developer CLI

```sh
swift build
.build/debug/SaneHarness list                      # find the scanner
.build/debug/SaneHarness scan --duplex --auto-rotate --dpi 300 --out ~/Desktop/test
.build/debug/SaneHarness convert p1.png --format searchablePDF --out .
```

## Credits

This program was created by Federico Marra.