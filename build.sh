#!/bin/bash
set -e

WORKDIR=$(pwd)
OUT_DIR="$WORKDIR/out"
CLANG_DIR="$WORKDIR/toolchains/clang"
GCC_DIR="$WORKDIR/toolchains/gcc"
ANYKERNEL_DIR="$WORKDIR/AnyKernel3"

DEVICE="RMX2061"
DEFCONFIG="atoll_defconfig"
KERNEL_NAME="BunnyBladeX"
VARIENT="ResukiSU"
BUILD_TYPE="Test"
VERSION="v1.0.0"

DATE=$(date +%Y%m%d)
TIME=$(date +%H%M)
ZIPNAME="${KERNEL_NAME}-${DEVICE}-${TIME}-${DATE}-${VERSION}.zip"

# ========== EXPORT FULL NAME FOR ARTIFACT ==========
KERNEL_FULL_NAME="${KERNEL_NAME}-${DEVICE}-${TIME}-${DATE}-${VERSION}"
if [ -n "$GITHUB_ENV" ]; then
    echo "KERNEL_FULL_NAME=${KERNEL_FULL_NAME}" >> "$GITHUB_ENV"
fi
# ===================================================

# ===================== COLOURS =====================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m' # No Colour
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

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}    BUNNYX KERNEL BUILD SYSTEM${NC}"
echo -e "${CYAN}========================================${NC}"

mkdir -p "$WORKDIR/toolchains"

# ===== CLANG (ORIGINAL - DO NOT CHANGE) =====
if [ ! -d "$CLANG_DIR" ]; then
    echo -e "${YELLOW}Downloading Clang...${NC}"
    git clone --depth=1 \
    https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86 \
    "$CLANG_DIR"
fi

# Auto-detect latest clang (ORIGINAL)
CLANG_BIN=$(find "$CLANG_DIR" -maxdepth 1 -type d -name "clang-r*" | sort -V | tail -1)

if [ -z "$CLANG_BIN" ]; then
    echo -e "${RED}No clang found${NC}"
    ls -1 "$CLANG_DIR" | head -5
    exit 1
fi

echo -e "${GREEN}Clang: $(basename $CLANG_BIN)${NC}"

# ===== LLVM BINUTILS (ORIGINAL) =====
BINUTILS_DIR="$CLANG_DIR/llvm-binutils-stable"

if [ ! -d "$BINUTILS_DIR" ]; then
    echo -e "${YELLOW}Downloading llvm-binutils-stable...${NC}"
    git clone --depth=1 \
    https://android.googlesource.com/toolchain/llvm-binutils-stable \
    "$BINUTILS_DIR" 2>&1 | tail -1
else
    echo -e "${GREEN}Using cached binutils${NC}"
fi

# ===== GCC (ORIGINAL) =====
if [ ! -d "$GCC_DIR" ]; then
    echo -e "${YELLOW}Downloading GCC...${NC}"
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

echo -e "${GREEN}Compiler ready${NC}"

# ===================== BUILD INFO BOX (NEW) =====================
echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}    COMPILER INFORMATION${NC}"
echo -e "${CYAN}========================================${NC}"

CLANG_VER=$(clang --version | head -n1)
echo -e "${GREEN}Clang: ${CLANG_VER}${NC}"

GCC_VER=$(aarch64-linux-gnu-gcc --version | head -n1)
echo -e "${GREEN}GCC:   ${GCC_VER}${NC}"

LD_VER=$(ld.lld --version | head -n1)
echo -e "${GREEN}LD:    ${LD_VER}${NC}"

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}    BUILD CONFIGURATION${NC}"
echo -e "${CYAN}========================================${NC}"
echo -e "${WHITE}Device:     ${DEVICE}${NC}"
echo -e "${WHITE}Defconfig:  ${DEFCONFIG}${NC}"
echo -e "${WHITE}Name:       ${KERNEL_NAME}${NC}"
echo -e "${WHITE}Version:    ${VERSION}${NC}"
echo -e "${WHITE}Type:       ${BUILD_TYPE}${NC}"
echo -e "${WHITE}Output:     ${ZIPNAME}${NC}"
echo -e "${WHITE}Date:       $(date '+%Y-%m-%d %H:%M:%S')${NC}"
echo -e "${WHITE}Host:       $(uname -n) | $(nproc) cores${NC}"
echo -e "${CYAN}========================================${NC}"

# ===================== ANYKERNEL3 =====================
if [ ! -d "$ANYKERNEL_DIR" ]; then
    echo -e "${YELLOW}Cloning AnyKernel3...${NC}"
    git clone --depth=1 --branch master \
    https://github.com/JOD-BUNNY07/AnyKernel3.git \
    "$ANYKERNEL_DIR"
fi

# ===================== BUILD START =====================
START=$(date +%s)

send_msg "Build Started
${DEVICE} | $(nproc) cores | ~10min"

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}    BUILDING${NC}"
echo -e "${CYAN}========================================${NC}"

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

    echo -e "${RED}Build Failed${NC}"
    send_msg "Build Failed"
    send_file "$OUT_DIR/build.log" "Error Log"
    exit 1
fi

# ===================== IMAGE CHECK =====================
IMG="$OUT_DIR/arch/arm64/boot/Image.gz-dtb"

if [ ! -f "$IMG" ]; then
    echo -e "${RED}Image not found${NC}"
    send_msg "Image Missing"
    exit 1
fi

echo -e "${GREEN}Image: $(du -h "$IMG" | cut -f1)${NC}"

# ===================== PACKAGING =====================
echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}    PACKAGING${NC}"
echo -e "${CYAN}========================================${NC}"

cp "$IMG" "$ANYKERNEL_DIR/zImage"

cd "$ANYKERNEL_DIR"
zip -r9q "$ZIPNAME" * -x ".git*" README.md "*.zip"

ZIP_SIZE=$(du -h "$ZIPNAME" | cut -f1)
echo -e "${GREEN}ZIP: $ZIP_SIZE${NC}"

# ===================== FINISH =====================
END=$(date +%s)
DIFF=$((END - START))
MINS=$((DIFF / 60))
SECS=$((DIFF % 60))

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}    BUILD COMPLETE!${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${WHITE}Output: ${ZIPNAME}${NC}"
echo -e "${WHITE}Size:   ${ZIP_SIZE}${NC}"
echo -e "${WHITE}Time:   ${MINS}m ${SECS}s${NC}"
echo -e "${GREEN}========================================${NC}"

send_file "$ANYKERNEL_DIR/$ZIPNAME" \
"Build Success

${ZIPNAME}
Size: ${ZIP_SIZE}
Time: ${MINS}m ${SECS}s"

# Move to out for artifact
mv "$ANYKERNEL_DIR/$ZIPNAME" "$OUT_DIR/"

echo -e "${GREEN}Zip saved to: ${OUT_DIR}/${ZIPNAME}${NC}"

