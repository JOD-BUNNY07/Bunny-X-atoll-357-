#!/bin/bash
set -e

# ============================================================
#                  BUNNYX KERNEL BUILD SYSTEM
# ============================================================

WORKDIR=$(pwd)

OUT_DIR="$WORKDIR/out"
CLANG_DIR="$WORKDIR/toolchains/clang"
GCC_DIR="$WORKDIR/toolchains/gcc"
ANYKERNEL_DIR="$WORKDIR/AnyKernel3"

DEVICE="RMX2061"
DEFCONFIG="atoll_defconfig"
KERNEL_NAME="BunnyBladeX-KSUN"
BUILD_TYPE="Stable"
VERSION="v1.0.1"

DATE=$(date +%Y%m%d)
TIME=$(date +%H%M)

ZIPNAME="${KERNEL_NAME}-${DEVICE}-${TIME}-${DATE}-${VERSION}.zip"

# ============================================================
#                 EXPORT FULL NAME FOR ARTIFACT
# ============================================================

KERNEL_FULL_NAME="${KERNEL_NAME}-${DEVICE}-${TIME}-${DATE}-${VERSION}"

if [ -n "$GITHUB_ENV" ]; then
    echo "KERNEL_FULL_NAME=${KERNEL_FULL_NAME}" >> "$GITHUB_ENV"
fi

# ============================================================
#                         COLOURS
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m'

# ============================================================
#                          CCACHE
# ============================================================

export USE_CCACHE=1
export CCACHE_DIR="$WORKDIR/.ccache"

mkdir -p "$CCACHE_DIR"

ccache -M 15G >/dev/null 2>&1 || true

# ============================================================
#                         TELEGRAM
# ============================================================

BOT_TOKEN="${TELEGRAM_TOKEN}"
CHAT_ID="${TELEGRAM_CHAT_ID}"

send_msg() {
    if [[ -n "$BOT_TOKEN" && -n "$CHAT_ID" ]]; then
        curl -s -X POST \
            "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
            -d chat_id="${CHAT_ID}" \
            -d parse_mode=HTML \
            -d text="$1" \
            > /dev/null
    fi
}

send_file() {
    if [[ -n "$BOT_TOKEN" && -n "$CHAT_ID" ]]; then
        curl -s -X POST \
            "https://api.telegram.org/bot${BOT_TOKEN}/sendDocument" \
            -F chat_id="${CHAT_ID}" \
            -F document=@"$1" \
            -F parse_mode=HTML \
            -F caption="$2" \
            > /dev/null
    fi
}

# ============================================================
#                         BUILD HEADER
# ============================================================

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}       BUNNYX KERNEL BUILD SYSTEM${NC}"
echo -e "${CYAN}========================================${NC}"

mkdir -p "$WORKDIR/toolchains"

# ============================================================
#              EXACT ANDROID CLANG TOOLCHAIN
#
#              Clang 22.0.2
#              LLVM r596125
#              Build ID 15071444
# ============================================================

CLANG_VERSION="clang-r596125"
CLANG_BUILD_ID="15071444"

CLANG_BIN="$CLANG_DIR/$CLANG_VERSION"

# Exact prebuilt mirror
CLANG_URL="https://github.com/bachnxuan/aosp_clang_mirror/releases/download/clang-r596125-15071444/clang-r596125.tar.gz"

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}       ANDROID CLANG TOOLCHAIN${NC}"
echo -e "${CYAN}========================================${NC}"

if [ ! -x "$CLANG_BIN/bin/clang" ]; then

    echo -e "${YELLOW}Downloading exact Android Clang...${NC}"
    echo -e "${YELLOW}Version : 22.0.2${NC}"
    echo -e "${YELLOW}Revision: r596125${NC}"
    echo -e "${YELLOW}Build ID: ${CLANG_BUILD_ID}${NC}"

    mkdir -p "$CLANG_DIR"

    rm -rf "$CLANG_BIN"

    curl -L \
        --fail \
        --retry 3 \
        --retry-delay 5 \
        "$CLANG_URL" \
        -o "$CLANG_DIR/clang-r596125.tar.gz"

    echo -e "${YELLOW}Extracting Clang...${NC}"

    tar -xzf \
        "$CLANG_DIR/clang-r596125.tar.gz" \
        -C "$CLANG_DIR"

    rm -f "$CLANG_DIR/clang-r596125.tar.gz"
fi

if [ ! -x "$CLANG_BIN/bin/clang" ]; then
    echo -e "${RED}ERROR: Clang binary not found!${NC}"
    echo ""
    find "$CLANG_DIR" -maxdepth 2 -type f -name clang | head -20
    exit 1
fi

echo -e "${GREEN}Clang directory found:${NC}"
echo -e "${GREEN}$CLANG_BIN${NC}"

# ============================================================
#                    LLVM BINUTILS
# ============================================================

BINUTILS_DIR="$CLANG_DIR/llvm-binutils-stable"

if [ ! -d "$BINUTILS_DIR" ]; then

    echo ""
    echo -e "${YELLOW}Downloading llvm-binutils-stable...${NC}"

    git clone \
        --depth=1 \
        https://android.googlesource.com/toolchain/llvm-binutils-stable \
        "$BINUTILS_DIR"

else

    echo -e "${GREEN}Using cached LLVM binutils${NC}"

fi

# ============================================================
#                         GCC 9.3
# ============================================================

if [ ! -d "$GCC_DIR" ]; then

    echo ""
    echo -e "${YELLOW}Downloading GCC 9.3...${NC}"

    git clone \
        --depth=1 \
        https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-gnu-9.3 \
        "$GCC_DIR"

else

    echo -e "${GREEN}Using cached GCC${NC}"

fi

# ============================================================
#                         PATH SETUP
# ============================================================

export PATH="$CLANG_BIN/bin:$BINUTILS_DIR/bin:$GCC_DIR/bin:$PATH"

export ARCH=arm64
export SUBARCH=arm64

# Target compiler
export CC=clang
export CXX=clang++

# LLVM tools
export LD=ld.lld
export AR=llvm-ar
export NM=llvm-nm
export STRIP=llvm-strip
export OBJCOPY=llvm-objcopy
export OBJDUMP=llvm-objdump

# Host compiler
export HOSTCC=gcc
export HOSTCXX=g++

# Kernel LLVM build
export LLVM=1
export LLVM_IAS=1

echo ""
echo -e "${GREEN}Compiler environment ready${NC}"

# ============================================================
#                    COMPILER VERIFICATION
# ============================================================

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}       COMPILER INFORMATION${NC}"
echo -e "${CYAN}========================================${NC}"

CLANG_FULL_VER="$(clang --version)"
CLANG_VER="$(echo "$CLANG_FULL_VER" | head -n1)"

GCC_VER="$(aarch64-linux-gnu-gcc --version | head -n1)"
LD_VER="$(ld.lld --version | head -n1)"

echo ""
echo -e "${GREEN}Clang:${NC}"
echo "$CLANG_FULL_VER"

echo ""
echo -e "${GREEN}GCC:${NC}"
echo "$GCC_VER"

echo ""
echo -e "${GREEN}LLD:${NC}"
echo "$LD_VER"

# ------------------------------------------------------------
# Exact compiler checks
# ------------------------------------------------------------

if ! echo "$CLANG_FULL_VER" | grep -q "15071444"; then

    echo ""
    echo -e "${RED}ERROR: Wrong Clang Build ID!${NC}"
    echo -e "${RED}Expected: 15071444${NC}"
    echo ""
    clang --version
    exit 1

fi

if ! echo "$CLANG_FULL_VER" | grep -q "based on r596125"; then

    echo ""
    echo -e "${RED}ERROR: Wrong LLVM revision!${NC}"
    echo -e "${RED}Expected: r596125${NC}"
    echo ""
    clang --version
    exit 1

fi

if ! echo "$CLANG_FULL_VER" | grep -q "clang version 22.0.2"; then

    echo ""
    echo -e "${RED}ERROR: Wrong Clang version!${NC}"
    echo -e "${RED}Expected: 22.0.2${NC}"
    echo ""
    clang --version
    exit 1

fi

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}       EXACT CLANG VERIFIED${NC}"
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}Version : 22.0.2${NC}"
echo -e "${GREEN}LLVM    : r596125${NC}"
echo -e "${GREEN}Build ID: 15071444${NC}"
echo -e "${GREEN}========================================${NC}"

# ============================================================
#                    BUILD CONFIGURATION
# ============================================================

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}        BUILD CONFIGURATION${NC}"
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

# ============================================================
#                       ANYKERNEL3
# ============================================================

if [ ! -d "$ANYKERNEL_DIR" ]; then

    echo ""
    echo -e "${YELLOW}Cloning AnyKernel3...${NC}"

    git clone \
        --depth=1 \
        --branch master \
        https://github.com/JOD-BUNNY07/AnyKernel3.git \
        "$ANYKERNEL_DIR"

else

    echo -e "${GREEN}Using cached AnyKernel3${NC}"

fi

# ============================================================
#                       BUILD START
# ============================================================

START=$(date +%s)

send_msg "Build Started
${DEVICE} | $(nproc) cores | Clang 22.0.2 r596125 Build 15071444"

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}             BUILDING${NC}"
echo -e "${CYAN}========================================${NC}"

# ============================================================
#                       CLEANUP
# ============================================================

rm -f "$ANYKERNEL_DIR/zImage"
rm -f "$ANYKERNEL_DIR"/*.zip

# ============================================================
#                    PREPARE OUTPUT
# ============================================================

mkdir -p "$OUT_DIR"

# ============================================================
#                       DEFCONFIG
# ============================================================

echo ""
echo -e "${YELLOW}Loading ${DEFCONFIG}...${NC}"

make \
    O="$OUT_DIR" \
    ARCH=arm64 \
    "$DEFCONFIG"

echo -e "${GREEN}Defconfig loaded${NC}"

# ============================================================
#                      OLDDEFCONFIG
# ============================================================

echo ""
echo -e "${YELLOW}Running olddefconfig...${NC}"

make \
    O="$OUT_DIR" \
    ARCH=arm64 \
    olddefconfig

echo -e "${GREEN}Configuration ready${NC}"

# ============================================================
#                     BUILD KERNEL
# ============================================================

JOBS=$(($(nproc) * 2))

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}          KERNEL COMPILATION${NC}"
echo -e "${CYAN}========================================${NC}"

echo -e "${WHITE}Jobs:     ${JOBS}${NC}"
echo -e "${WHITE}Compiler: Clang 22.0.2${NC}"
echo -e "${WHITE}LLVM:     r596125${NC}"
echo -e "${WHITE}Build ID: 15071444${NC}"
echo -e "${WHITE}Target:   arm64${NC}"
echo -e "${CYAN}========================================${NC}"

if ! make \
    -j"$JOBS" \
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

    echo ""
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}             BUILD FAILED${NC}"
    echo -e "${RED}========================================${NC}"

    send_msg "Build Failed
${DEVICE}
Compiler: Clang 22.0.2
LLVM: r596125
Build ID: 15071444"

    send_file \
        "$OUT_DIR/build.log" \
        "BunnyX Build Error Log"

    exit 1
fi

# ============================================================
#                       IMAGE CHECK
# ============================================================

IMG="$OUT_DIR/arch/arm64/boot/Image.gz-dtb"

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}             IMAGE CHECK${NC}"
echo -e "${CYAN}========================================${NC}"

if [ ! -f "$IMG" ]; then

    echo -e "${RED}Image.gz-dtb not found!${NC}"

    echo ""
    echo "Searching for kernel image:"
    find "$OUT_DIR/arch/arm64/boot" \
        -maxdepth 1 \
        -type f \
        -printf '%f\n' 2>/dev/null || true

    send_msg "Image Missing
${DEVICE}"

    exit 1
fi

IMAGE_SIZE=$(du -h "$IMG" | cut -f1)

echo -e "${GREEN}Image found:${NC} $IMG"
echo -e "${GREEN}Image size:${NC} $IMAGE_SIZE"

# ============================================================
#                       PACKAGING
# ============================================================

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}             PACKAGING${NC}"
echo -e "${CYAN}========================================${NC}"

cp "$IMG" "$ANYKERNEL_DIR/zImage"

cd "$ANYKERNEL_DIR"

rm -f "$ZIPNAME"

zip -r9q \
    "$ZIPNAME" \
    * \
    -x ".git*" \
    "README.md" \
    "*.zip"

ZIP_SIZE=$(du -h "$ZIPNAME" | cut -f1)

echo -e "${GREEN}ZIP created:${NC} $ZIPNAME"
echo -e "${GREEN}ZIP size:${NC}    $ZIP_SIZE"

# ============================================================
#                       BUILD FINISH
# ============================================================

END=$(date +%s)

DIFF=$((END - START))

MINS=$((DIFF / 60))
SECS=$((DIFF % 60))

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}          BUILD COMPLETE!${NC}"
echo -e "${GREEN}========================================${NC}"

echo -e "${WHITE}Output: ${ZIPNAME}${NC}"
echo -e "${WHITE}Size:   ${ZIP_SIZE}${NC}"
echo -e "${WHITE}Time:   ${MINS}m ${SECS}s${NC}"

echo ""
echo -e "${GREEN}Compiler:${NC} Android Clang 22.0.2"
echo -e "${GREEN}LLVM:${NC}     r596125"
echo -e "${GREEN}Build ID:${NC} 15071444"

echo -e "${GREEN}========================================${NC}"

# ============================================================
#                    TELEGRAM UPLOAD
# ============================================================

send_file \
    "$ANYKERNEL_DIR/$ZIPNAME" \
    "Build Success

${ZIPNAME}
Size: ${ZIP_SIZE}
Time: ${MINS}m ${SECS}s

Compiler: Android Clang 22.0.2
LLVM: r596125
Build ID: 15071444"

# ============================================================
#                       ARTIFACT
# ============================================================

mv \
    "$ANYKERNEL_DIR/$ZIPNAME" \
    "$OUT_DIR/"

echo ""
echo -e "${GREEN}Zip saved to:${NC}"
echo -e "${GREEN}${OUT_DIR}/${ZIPNAME}${NC}"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}              DONE${NC}"
echo -e "${GREEN}========================================${NC}"
