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

## Developer CLI

```sh
swift build
.build/debug/SaneHarness list                      # find the scanner
.build/debug/SaneHarness scan --duplex --dpi 300 --out ~/Desktop/test
.build/debug/SaneHarness convert p1.png --format searchablePDF --out .
```
