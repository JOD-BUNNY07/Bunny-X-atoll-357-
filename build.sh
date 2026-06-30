#!/bin/bash
set -e

WORKDIR=$(pwd)
OUT_DIR="$WORKDIR/out"
CLANG_DIR="$WORKDIR/toolchains/clang"
GCC_DIR="$WORKDIR/toolchains/gcc"
ANYKERNEL_DIR="$WORKDIR/AnyKernel3"

DEVICE="RMX2061"
DEFCONFIG="atoll_defconfig"
KERNEL_NAME="BunnyX"
VARIANT="Perf-atoll"
SUFFIX="KSUN"
BUILD_TYPE="Stable"
VERSION="v1.0.3"

DATE=$(date +%Y%m%d)
TIME=$(date +%H%M)
KERNEL_FULL_NAME="${KERNEL_NAME}-${VARIANT}-${DEVICE}-${DATE}-${TIME}-${VERSION}-${SUFFIX}"
ZIPNAME="${KERNEL_FULL_NAME}.zip"

if [ -n "$GITHUB_ENV" ]; then
    echo "KERNEL_FULL_NAME=${KERNEL_FULL_NAME}" >> "$GITHUB_ENV"
    echo "ZIPNAME=${ZIPNAME}" >> "$GITHUB_ENV"
fi

export USE_CCACHE=1
export CCACHE_DIR="${CCACHE_DIR:-$WORKDIR/.ccache}"
mkdir -p "$CCACHE_DIR"
ccache -M 15G >/dev/null 2>&1 || true

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

echo ""
echo "========================================"
echo "    BUNNYX KERNEL BUILD SYSTEM"
echo "========================================"

mkdir -p "$WORKDIR/toolchains"

if [ ! -d "$CLANG_DIR/bin" ] || [ -z "$(ls -A $CLANG_DIR/bin 2>/dev/null)" ]; then
    echo "Downloading Clang..."
    rm -rf "$CLANG_DIR"
    mkdir -p "$CLANG_DIR"
    git clone --depth=1 \
    https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86 \
    "$CLANG_DIR"
fi

CLANG_BIN=$(find "$CLANG_DIR" -maxdepth 2 -type d -name "bin" | head -1)
if [ -z "$CLANG_BIN" ]; then
    CLANG_BIN="$CLANG_DIR/bin"
fi

if [ ! -d "$GCC_DIR/bin" ] || [ -z "$(ls -A $GCC_DIR/bin 2>/dev/null)" ]; then
    echo "Downloading GCC..."
    rm -rf "$GCC_DIR"
    git clone --depth=1 \
    https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-gnu-9.3 \
    "$GCC_DIR" 2>&1 | tail -1
fi

export PATH="$CLANG_BIN:$GCC_DIR/bin:$PATH"
export ARCH=arm64
export SUBARCH=arm64

export CC=clang
export CXX=clang++
export LD=ld.lld
export AR=llvm-ar
export NM=llvm-nm
export STRIP=llvm-strip
export OBJCOPY=llvm-objcopy
export OBJDUMP=llvm-objdump

export CROSS_COMPILE=aarch64-linux-gnu-
export CROSS_COMPILE_ARM32=arm-linux-gnueabi-

echo ""
echo "========================================"
echo "    COMPILER INFORMATION"
echo "========================================"

if command -v clang &>/dev/null; then
    CLANG_VER=$(clang --version | head -n1)
    CLANG_VER_NUM=$(echo "$CLANG_VER" | grep -oP 'clang version \K[0-9.]+' || echo "unknown")
    echo "Clang: ${CLANG_VER}"
else
    echo "ERROR: Clang not found!"
    exit 1
fi

if command -v aarch64-linux-gnu-gcc &>/dev/null; then
    GCC_VER=$(aarch64-linux-gnu-gcc --version | head -n1)
    echo "GCC:   ${GCC_VER}"
fi

if command -v ld.lld &>/dev/null; then
    LD_VER=$(ld.lld --version | head -n1)
    echo "LD:    ${LD_VER}"
fi

echo ""
echo "========================================"
echo "    BUILD CONFIGURATION"
echo "========================================"
echo "Device:     ${DEVICE}"
echo "Defconfig:  ${DEFCONFIG}"
echo "Name:       ${KERNEL_NAME} ${VARIANT}"
echo "Version:    ${VERSION}"
echo "Type:       ${BUILD_TYPE}"
echo "Output:     ${ZIPNAME}"
echo "Date:       $(date '+%Y-%m-%d %H:%M:%S')"
echo "Host:       $(uname -n) | $(nproc) cores"
echo "========================================"

if [ ! -d "$ANYKERNEL_DIR/.git" ]; then
    echo "Cloning AnyKernel3..."
    rm -rf "$ANYKERNEL_DIR"
    git clone --depth=1 --branch master \
    https://github.com/JOD-BUNNY07/AnyKernel3.git "$ANYKERNEL_DIR"
fi

AK_SH="$ANYKERNEL_DIR/anykernel.sh"
if [ -f "$AK_SH" ]; then
    sed -i "s/kernel.string=.*/kernel.string=${KERNEL_NAME} ${VARIANT} Kernel/" "$AK_SH"
    sed -i "s/kernel.for=.*/kernel.for=${DEVICE}/" "$AK_SH"
    sed -i "s/kernel.compiler=.*/kernel.compiler=Clang ${CLANG_VER_NUM}/" "$AK_SH"
    sed -i "s/kernel.made=.*/kernel.made=GitHub Actions | BunnyX Build/" "$AK_SH"
    sed -i "s/kernel.version=.*/kernel.version=${VERSION}/" "$AK_SH"
fi

START_TIME=$(date +%s)

send_msg "Build Started
${DEVICE} | ${DEFCONFIG}
Clang ${CLANG_VER_NUM} | $(nproc) cores
ETA: ~10min"

echo ""
echo "========================================"
echo "    COMPILING KERNEL"
echo "========================================"

rm -f "$ANYKERNEL_DIR/zImage" "$ANYKERNEL_DIR"/*.zip
mkdir -p "$OUT_DIR"

echo "Generating config..."
make O="$OUT_DIR" ARCH=arm64 "$DEFCONFIG" > /dev/null 2>&1
make O="$OUT_DIR" ARCH=arm64 olddefconfig > /dev/null 2>&1

JOBS=$(nproc)
BUILD_START=$(date +%s)

if ! make -j${JOBS} \
    O="$OUT_DIR" \
    ARCH=arm64 \
    CC="ccache clang" \
    CXX="ccache clang++" \
    HOSTCC=gcc \
    HOSTCXX=g++ \
    LD=ld.lld \
    LLVM=1 \
    LLVM_IAS=1 \
    CLANG_TRIPLE=aarch64-linux-gnu- \
    CROSS_COMPILE=aarch64-linux-gnu- \
    CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
    2>&1 | tee "$OUT_DIR/build.log"; then

    echo ""
    echo "========================================"
    echo "    BUILD FAILED"
    echo "========================================"
    
    ERROR_COUNT=$(grep -c "error:" "$OUT_DIR/build.log" || echo "0")
    echo "Errors: ${ERROR_COUNT}"
    
    send_msg "Build Failed
${DEVICE}
Errors: ${ERROR_COUNT}"
    send_file "$OUT_DIR/build.log" "Error Log"
    exit 1
fi

BUILD_END=$(date +%s)
BUILD_TIME=$((BUILD_END - BUILD_START))

IMG="$OUT_DIR/arch/arm64/boot/Image.gz-dtb"

if [ ! -f "$IMG" ]; then
    echo "ERROR: Image.gz-dtb not found!"
    send_msg "Image Missing!"
    exit 1
fi

IMG_SIZE=$(du -h "$IMG" | cut -f1)
echo ""
echo "Kernel Image: ${IMG_SIZE}"

echo ""
echo "========================================"
echo "    PACKAGING ZIP"
echo "========================================"

cp "$IMG" "$ANYKERNEL_DIR/zImage"
cd "$ANYKERNEL_DIR"
zip -r9q "$ZIPNAME" * -x ".git*" "README.md" "*.zip"

ZIP_PATH="$ANYKERNEL_DIR/$ZIPNAME"
ZIP_SIZE=$(du -h "$ZIPNAME" | cut -f1)

echo "ZIP: ${ZIPNAME}"
echo "Size: ${ZIP_SIZE}"

END_TIME=$(date +%s)
TOTAL_TIME=$((END_TIME - START_TIME))
MINS=$((TOTAL_TIME / 60))
SECS=$((TOTAL_TIME % 60))

echo ""
echo "========================================"
echo "    BUILD COMPLETE"
echo "========================================"
echo "Output:     ${ZIPNAME}"
echo "Size:       ${ZIP_SIZE}"
echo "Build Time: ${BUILD_TIME}s"
echo "Total Time: ${MINS}m ${SECS}s"
echo "========================================"

send_file "$ZIP_PATH" \
"Build Complete!

Device: ${DEVICE}
Defconfig: ${DEFCONFIG}
Compiler: Clang ${CLANG_VER_NUM}
Name: ${KERNEL_NAME} ${VARIANT}
Version: ${VERSION}
Size: ${ZIP_SIZE}
Time: ${MINS}m ${SECS}s
Date: $(date '+%Y-%m-%d %H:%M')"

mv "$ZIP_PATH" "$OUT_DIR/"

echo ""
echo "Zip saved to: ${OUT_DIR}/${ZIPNAME}"

