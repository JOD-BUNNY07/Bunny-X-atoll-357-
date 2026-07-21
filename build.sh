#!/bin/bash
set -e

WORKDIR=$(pwd)
OUT_DIR="$WORKDIR/out"
CLANG_DIR="$WORKDIR/toolchains/clang"
GCC_DIR="$WORKDIR/toolchains/gcc"
ANYKERNEL_DIR="$WORKDIR/AnyKernel3"

DEVICE="RMX2061"
DEFCONFIG="atoll_defconfig"
KERNEL_NAME="BunnyX-atoll-ResukiSU
BUILD_TYPE="Test"
VERSION="v1.0"

DATE=$(date +%Y%m%d)
TIME=$(date +%H%M)
ZIPNAME="${KERNEL_NAME}-${DEVICE}-${TIME}-${DATE}-${VERSION}.zip"

# ========== EXPORT FULL NAME FOR ARTIFACT ==========
KERNEL_FULL_NAME="${KERNEL_NAME}-${DEVICE}-${TIME}-${DATE}-${VERSION}"
if [ -n "$GITHUB_ENV" ]; then
    echo "KERNEL_FULL_NAME=${KERNEL_FULL_NAME}" >> "$GITHUB_ENV"
fi
# ===================================================

# ===================== CCACHE =====================
export USE_CCACHE=1
export CCACHE_DIR="$WORKDIR/.ccache"
mkdir -p "$CCACHE_DIR"
ccache -M 15G >/dev/null 2>&1 || true

# ===================== TELEGRAM =====================
BOT_TOKEN="${TELEGRAM_TOKEN}"
CHAT_ID="${TELEGRAM_CHAT_ID}"

send_msg() {
    if [[ -n "$BOT_TOKEN" && -n "$CHAT_ID" ]]; then
        curl -s -X POST \
        "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d chat_id="${CHAT_ID}" \
        -d parse_mode=HTML \
        -d text="$1" > /dev/null
    fi
}

send_file() {
    if [[ -n "$BOT_TOKEN" && -n "$CHAT_ID" ]]; then
        curl -s -X POST \
        "https://api.telegram.org/bot${BOT_TOKEN}/sendDocument" \
        -F chat_id="${CHAT_ID}" \
        -F document=@"$1" \
        -F parse_mode=HTML \
        -F caption="$2" > /dev/null
    fi
}

# ===================== TOOLCHAIN =====================

echo "========================================"
echo "    BUNNYX KERNEL BUILD SYSTEM"
echo "========================================"

mkdir -p "$WORKDIR/toolchains"

# ===== CLANG (ORIGINAL - DO NOT CHANGE) =====
if [ ! -d "$CLANG_DIR" ]; then
    echo "Downloading Clang..."
    git clone --depth=1 \
    https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86 \
    "$CLANG_DIR"
fi

# Auto-detect latest clang (ORIGINAL)
CLANG_BIN=$(find "$CLANG_DIR" -maxdepth 1 -type d -name "clang-r*" | sort -V | tail -1)

if [ -z "$CLANG_BIN" ]; then
    echo "No clang found"
    ls -1 "$CLANG_DIR" | head -5
    exit 1
fi

echo "Clang: $(basename $CLANG_BIN)"

# ===== LLVM BINUTILS (ORIGINAL) =====
BINUTILS_DIR="$CLANG_DIR/llvm-binutils-stable"

if [ ! -d "$BINUTILS_DIR" ]; then
    echo "Downloading llvm-binutils-stable..."
    git clone --depth=1 \
    https://android.googlesource.com/toolchain/llvm-binutils-stable \
    "$BINUTILS_DIR" 2>&1 | tail -1
else
    echo "Using cached binutils"
fi

# ===== GCC (ORIGINAL) =====
if [ ! -d "$GCC_DIR" ]; then
    echo "Downloading GCC..."
    git clone --depth=1 \
    https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-gnu-9.3 \
    "$GCC_DIR"
fi

# ===== PATH SETUP (ORIGINAL) =====
export PATH="$CLANG_BIN/bin:$BINUTILS_DIR/bin:$GCC_DIR/bin:$PATH"
export ARCH=arm64
export SUBARCH=arm64

export CC=clang
export LD=ld.lld
export AR=llvm-ar
export NM=llvm-nm
export STRIP=llvm-strip
export OBJCOPY=llvm-objcopy
export OBJDUMP=llvm-objdump

echo "Compiler ready"

# ===================== BUILD INFO BOX (NEW) =====================
echo ""
echo "========================================"
echo "    COMPILER INFORMATION"
echo "========================================"

CLANG_VER=$(clang --version | head -n1)
echo "Clang: ${CLANG_VER}"

GCC_VER=$(aarch64-linux-gnu-gcc --version | head -n1)
echo "GCC:   ${GCC_VER}"

LD_VER=$(ld.lld --version | head -n1)
echo "LD:    ${LD_VER}"

echo ""
echo "========================================"
echo "    BUILD CONFIGURATION"
echo "========================================"
echo "Device:     ${DEVICE}"
echo "Defconfig:  ${DEFCONFIG}"
echo "Name:       ${KERNEL_NAME}"
echo "Version:    ${VERSION}"
echo "Type:       ${BUILD_TYPE}"
echo "Output:     ${ZIPNAME}"
echo "Date:       $(date '+%Y-%m-%d %H:%M:%S')"
echo "Host:       $(uname -n) | $(nproc) cores"
echo "========================================"

# ===================== ANYKERNEL3 =====================
if [ ! -d "$ANYKERNEL_DIR" ]; then
    echo "Cloning AnyKernel3..."
    git clone --depth=1 --branch master \
    https://github.com/JOD-BUNNY07/AnyKernel3.git \
    "$ANYKERNEL_DIR"
fi

# ===================== BUILD START =====================
START=$(date +%s)

send_msg "Build Started
${DEVICE} | $(nproc) cores | ~10min"

echo ""
echo "========================================"
echo "    BUILDING"
echo "========================================"

# Minimal cleanup
rm -f "$ANYKERNEL_DIR/zImage" "$ANYKERNEL_DIR"/*.zip

# Update config
mkdir -p "$OUT_DIR"
make O="$OUT_DIR" ARCH=arm64 "$DEFCONFIG" > /dev/null 2>&1
make O="$OUT_DIR" ARCH=arm64 olddefconfig > /dev/null 2>&1

# Build with max parallelization
JOBS=$(($(nproc) * 2))

if ! make -j$JOBS \
O="$OUT_DIR" \
ARCH=arm64 \
CC=clang \
HOSTCC=gcc \
HOSTCXX=g++ \
LD=ld.lld \
LLVM=1 \
LLVM_IAS=1 \
CLANG_TRIPLE=aarch64-linux-gnu- \
CROSS_COMPILE=aarch64-linux-gnu- \
2>&1 | tee "$OUT_DIR/build.log"; then

    echo "Build Failed"
    send_msg "Build Failed"
    send_file "$OUT_DIR/build.log" "Error Log"
    exit 1
fi

# ===================== IMAGE CHECK =====================
IMG="$OUT_DIR/arch/arm64/boot/Image.gz-dtb"

if [ ! -f "$IMG" ]; then
    echo "Image not found"
    send_msg "Image Missing"
    exit 1
fi

echo "Image: $(du -h "$IMG" | cut -f1)"

# ===================== PACKAGING =====================
echo ""
echo "========================================"
echo "    PACKAGING"
echo "========================================"

cp "$IMG" "$ANYKERNEL_DIR/zImage"

cd "$ANYKERNEL_DIR"
zip -r9q "$ZIPNAME" * -x ".git*" README.md "*.zip"

ZIP_SIZE=$(du -h "$ZIPNAME" | cut -f1)
echo "ZIP: $ZIP_SIZE"

# ===================== FINISH =====================
END=$(date +%s)
DIFF=$((END - START))
MINS=$((DIFF / 60))
SECS=$((DIFF % 60))

echo ""
echo "========================================"
echo "    BUILD COMPLETE!"
echo "========================================"
echo "Output: ${ZIPNAME}"
echo "Size:   ${ZIP_SIZE}"
echo "Time:   ${MINS}m ${SECS}s"
echo "========================================"

send_file "$ANYKERNEL_DIR/$ZIPNAME" \
"Build Success

${ZIPNAME}
Size: ${ZIP_SIZE}
Time: ${MINS}m ${SECS}s"

# Move to out for artifact
mv "$ANYKERNEL_DIR/$ZIPNAME" "$OUT_DIR/"

echo "Zip saved to: ${OUT_DIR}/${ZIPNAME}"

