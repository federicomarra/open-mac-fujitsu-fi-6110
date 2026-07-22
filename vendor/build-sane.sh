#!/bin/bash
# Builds universal (arm64 + x86_64) libusb and libsane for bundling inside
# "fi-6110 Scanner.app". Only the fujitsu backend is built, preloaded into
# libsane so no dlopen of separate backend dylibs is needed at runtime.
#
# Output: vendor/out/
#   lib/libsane.1.dylib, lib/libusb-1.0.0.dylib   (universal, minos 12.0, @rpath ids)
#   include/sane/                                  (public SANE headers)
#   etc/sane.d/dll.conf, fujitsu.conf              (minimal config for the bundle)
#
# Also syncs the SANE public headers into Sources/CSane/include/ for the Swift build.
set -euo pipefail

VENDOR="$(cd "$(dirname "$0")" && pwd)"
REPO="$(dirname "$VENDOR")"
SRC="$VENDOR/src"
BUILD="$VENDOR/build"
OUT="$VENDOR/out"

export MACOSX_DEPLOYMENT_TARGET=12.0

LIBUSB_VER=1.0.30
LIBUSB_URL="https://github.com/libusb/libusb/releases/download/v${LIBUSB_VER}/libusb-${LIBUSB_VER}.tar.bz2"
LIBUSB_SHA256=fea36f34f9156400209595e300840767ab1a385ede1dc7ee893015aea9c6dbaf

SANE_VER=1.4.0
SANE_URL="https://gitlab.com/-/project/429008/uploads/843c156420e211859e974f78f64c3ea3/sane-backends-${SANE_VER}.tar.gz"
SANE_SHA256=f99205c903dfe2fb8990f0c531232c9a00ec9c2c66ac7cb0ce50b4af9f407a72

ARCHS=(arm64 x86_64)
JOBS="$(sysctl -n hw.ncpu)"

# Use Apple's real tools explicitly — Anaconda ships cctools-port fakes that
# shadow them in PATH and write bogus signatures.
LIPO=/usr/bin/lipo
INT=/usr/bin/install_name_tool
CODESIGN=/usr/bin/codesign

# clang 16+ makes these old-C patterns hard errors; sane-backends 1.4.0 still uses them.
CWARN="-Wno-error=incompatible-function-pointer-types -Wno-error=implicit-function-declaration -Wno-error=implicit-int"

fetch() { # url sha dest
    local url="$1" sha="$2" dest="$3"
    if [[ -f "$dest" ]] && echo "$sha  $dest" | shasum -a 256 -c - >/dev/null 2>&1; then
        echo ">>> already fetched: $(basename "$dest")"
        return
    fi
    echo ">>> fetching $(basename "$dest")"
    curl -fL --retry 3 -o "$dest" "$url"
    echo "$sha  $dest" | shasum -a 256 -c -
}

host_for() { [[ "$1" == arm64 ]] && echo aarch64-apple-darwin || echo x86_64-apple-darwin; }

mkdir -p "$SRC" "$BUILD"
fetch "$LIBUSB_URL" "$LIBUSB_SHA256" "$SRC/libusb-$LIBUSB_VER.tar.bz2"
fetch "$SANE_URL" "$SANE_SHA256" "$SRC/sane-backends-$SANE_VER.tar.gz"

for arch in "${ARCHS[@]}"; do
    PREFIX="$BUILD/$arch/prefix"
    mkdir -p "$PREFIX"

    if [[ ! -f "$PREFIX/lib/libusb-1.0.0.dylib" ]]; then
        echo ">>> [$arch] building libusb $LIBUSB_VER"
        rm -rf "$BUILD/$arch/libusb" && mkdir -p "$BUILD/$arch/libusb"
        tar xf "$SRC/libusb-$LIBUSB_VER.tar.bz2" -C "$BUILD/$arch/libusb" --strip-components 1
        (
            cd "$BUILD/$arch/libusb"
            ./configure --host="$(host_for "$arch")" --prefix="$PREFIX" \
                --disable-static --enable-shared \
                CC="clang -arch $arch" CFLAGS="-O2 $CWARN" >configure.log
            make -j"$JOBS" >make.log 2>&1
            make install >install.log 2>&1
        )
        # Uniform @rpath id so libsane records @rpath/libusb-1.0.0.dylib in both slices
        "$INT" -id "@rpath/libusb-1.0.0.dylib" "$PREFIX/lib/libusb-1.0.0.dylib"
        "$CODESIGN" -f -s - "$PREFIX/lib/libusb-1.0.0.dylib"
    fi

    if [[ ! -f "$PREFIX/lib/sane/libsane-fujitsu.1.so" ]]; then
        echo ">>> [$arch] building sane-backends $SANE_VER (fujitsu backend)"
        rm -rf "$BUILD/$arch/sane" && mkdir -p "$BUILD/$arch/sane"
        tar xf "$SRC/sane-backends-$SANE_VER.tar.gz" -C "$BUILD/$arch/sane" --strip-components 1
        (
            cd "$BUILD/$arch/sane"
            PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig" \
            ./configure --host="$(host_for "$arch")" --prefix="$PREFIX" \
                BACKENDS="fujitsu" --disable-preload \
                --disable-static --enable-shared --disable-nls \
                CC="clang -arch $arch" CXX="clang++ -arch $arch" CFLAGS="-O2 $CWARN" >configure.log
            make -j"$JOBS" >make.log 2>&1
            make install >install.log 2>&1
        )
    fi
done

echo ">>> merging universal libraries into vendor/out"
rm -rf "$OUT"
mkdir -p "$OUT/lib" "$OUT/include" "$OUT/etc/sane.d"
A="$BUILD/arm64/prefix"
X="$BUILD/x86_64/prefix"

# The fujitsu backend module is an MH_BUNDLE that exports the complete plain
# sane_* API — the app dlopens it directly (no dll-router backend, no linking).
"$LIPO" -create "$A/lib/libusb-1.0.0.dylib" "$X/lib/libusb-1.0.0.dylib" -output "$OUT/lib/libusb-1.0.0.dylib"
"$LIPO" -create "$A/lib/sane/libsane-fujitsu.1.so" "$X/lib/sane/libsane-fujitsu.1.so" -output "$OUT/lib/libsane-fujitsu.so"
if ! nm -gU "$OUT/lib/libsane-fujitsu.so" | grep -q " _sane_init$"; then
    echo "ERROR: libsane-fujitsu does not export _sane_init" >&2
    exit 1
fi
# Let the module's @rpath/libusb reference resolve to the libusb sitting next to it,
# wherever the pair is placed (vendor/out/lib in dev, Contents/Frameworks in the app).
"$INT" -add_rpath "@loader_path/." "$OUT/lib/libsane-fujitsu.so"
"$CODESIGN" -f -s - "$OUT/lib/libusb-1.0.0.dylib" "$OUT/lib/libsane-fujitsu.so"

cp -R "$A/include/sane" "$OUT/include/"
# Only fujitsu.conf is needed: the standalone backend reads it via SANE_CONFIG_DIR
cp "$A/etc/sane.d/fujitsu.conf" "$OUT/etc/sane.d/fujitsu.conf"

echo ">>> syncing SANE headers into Sources/CSane/include"
mkdir -p "$REPO/Sources/CSane/include"
rm -rf "$REPO/Sources/CSane/include/sane"
cp -R "$OUT/include/sane" "$REPO/Sources/CSane/include/"

echo ">>> verification"
for f in "$OUT/lib/libusb-1.0.0.dylib" "$OUT/lib/libsane-fujitsu.so"; do
    echo "--- $f"
    "$LIPO" -info "$f"
    otool -l "$f" | awk '/LC_BUILD_VERSION/{v=1} v&&/minos/{print "    minos:", $2; v=0}'
    otool -L "$f" | tail -n +2
done
if otool -L "$OUT/lib/"*.dylib | grep -E '/opt/homebrew|/usr/local' ; then
    echo "ERROR: bundled libs reference Homebrew/local paths (not self-contained)" >&2
    exit 1
fi
echo ">>> OK: vendor/out is ready"
