# fi-6110 Scanner

[![Build & Release](https://github.com/federicomarra/open-mac-fujitsu-fi-6110/actions/workflows/ci.yml/badge.svg)](https://github.com/federicomarra/open-mac-fujitsu-fi-6110/actions/workflows/ci.yml)

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
Sources/CSane        C shim exposing the SANE API types to Swift
Sources/ScannerCore  engine: dlopens the bundled libsane-fujitsu.so, drives the
                     ADF page loop, converts raw frames to CGImage; PDF/OCR/
                     image writers (PDFBuilder embeds pages as JPEG, OCREngine
                     adds an invisible Vision text layer)
Sources/FiScanner    SwiftUI app (macOS 12-compatible), Italian + English
Sources/SaneHarness  developer CLI: list / scan / convert without the GUI
vendor/              builds libusb + sane-backends from pinned sources, per-arch,
                     then lipo-merges into vendor/out (deployment target 12.0)
packaging/           Info.plist, icon renderer, .app assembly + ad-hoc signing,
                     DMG creation
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
║   fi-6110 Scanner.app (universal binary, macOS 12.0+)                           ║
║   ┌─────────────────────────────────────────────────────────────────────────────┐ ║
║   │ Contents/                                                                   │ ║
║   │   ┌─────────────────────────────────────────────────────────────────────┐ │ ║
║   │   │ MacOS/                                                              │ │ ║
║   │   │   ┌─────────────────────────────────────────────────────────────┐   │ │ ║
║   │   │   │ FiScanner           (SwiftGUI → ScannerCore → CSane)        │   │ │ ║
║   │   │   └─────────────────────────────────────────────────────────────┘   │ │ ║
║   │   │                                                                     │ │ ║
║   │   │ Frameworks/                                                         │ │ ║
║   │   │   │ libsane-fujitsu.so        (SANE backend, bundled, rpath → lib/) │ │ ║
║   │   │   │ libusb-1.0.0.dylib        ( bundled, rpath → lib/)             │ │ ║
║   │   │   └─────────────────────────────────────────────────────────────┘   │ │ ║
║   │   │                                                                     │ │ ║
║   │   │ Resources/                                                          │ │ ║
║   │   │   │ en.lproj/Localizable.strings                                      │ │ ║
║   │   │   │ it.lproj/Localizable.strings                                      │ │ ║
║   │   │   │ AppIcon.icns                                                        │ │ ║
║   │   │   │ sane.d/                                                             │ │ ║
║   │   │   │   │ fujitsu                     (SANE backend config)             │ │ ║
║   │   │   │   │   └─ daemon → libsane-fujitsu.so (dlopen via CSane)          │ │ ║
║   │   │   └─────────────────────────────────────────────────────────────┘   │ │ ║
║   │   └─────────────────────────────────────────────────────────────────────┘ │ ║
║   └─────────────────────────────────────────────────────────────────────────────┘ ║
╚═══════════════════════════════════════════════════════════════════════════════════╝

- `FiScanner` (SwiftUI) → loads `CSane` (C shim) → `dlopen("lib/libsane-fujitsu.so")` → SANE backend -> libusb-1.0.0.dylib
- SANE backend uses `SANE_CONFIG_DIR` → `Resources/sane.d` → daemon loads `.so` from `Frameworks/`
- App *not* sandboxed: USB access via libusb requires it
```

## Code Architecture

```
┌────────────────────────── fi-6110 Scanner.app ──────────────────────────┐
│ SwiftUI app (universal, macOS 12+)                                      │
│  ├─ SaneEngine  — Swift wrapper over bundled libsane (C interop)        │
│  │    device discovery · options (mode/dpi/duplex/deskew/blank-skip)    │
│  │    ADF page loop → CGImage per page, progressive UI updates          │
│  ├─ UI          — Image-Capture-style window: thumbnails left,          │
│  │    options panel right, big "Scansiona" button                       │
│  ├─ Processing  — PDFKit multi-page PDF · Vision OCR → searchable PDF   │
│  │    (invisible text layer) · JPEG/PNG/TIFF via NSBitmapImageRep       │
│  └─ Frameworks/ — bundled universal dylibs: libsane (fujitsu backend    │
│       compiled in) + libusb-1.0, rpath-fixed, ad-hoc signed             │
└─────────────────────────────────────────────────────────────────────────┘
```

```
┌─────────────────────────── Vendor / Build (ARM64 + x86_64) ──────────────┐
│ vendor/build-sane.sh                                                     │
│  ├── vendor/src/libusb       — pinned commit, cmake → universal lib     │
│  ├── vendor/src/sane-backends — pinned, CMakeLists.txt patches for       │
│  │    macOS universal build (fujitsu backend compiled as MH_BUNDLE)     │
│  └── Compiled artifacts in vendor/out (universal lib + libsane-fujitsu │
│      symlink, rpath-fixed for macOS Frameworks layout)                   │
└──────────────────────────────────────────────────────────────────────────┘
```

```
┌─────────────────────────── Build Orchestration ─────────────────────────┐
│ .github/workflows/build-release.yml (CI/CD)                              │
│  ├── Checkout + version bump → bump + 0.1 on latest git tag             │
│  ├── Cache vendor/out · vendor/src (for libsane + libusb)                │
│  ├── Build vendor libs (if not cached) via vendor/build-sane.sh          │
│  ├── Stamp version into Info.plist (CFBundleShortVersionString /        │
│  │    CFBundleVersion = github-run-number)                              │
│  ├── Make app + DMG via packaging/{make-icon.sh,make-app.sh,make-dmg.sh} │
│  ├── Upload artifact (ZIP of DMG)                                      │
│  └── Tag v$VERSION + GitHub Release + release notes from commit range     │
└─────────────────────────────────────────────────────────────────────────┘
```

```



## Developer CLI

```sh
swift build
.build/debug/SaneHarness list                      # find the scanner
.build/debug/SaneHarness scan --duplex --dpi 300 --out ~/Desktop/test
.build/debug/SaneHarness convert p1.png --format searchablePDF --out .
```
