#!/bin/bash
set -e

# ============================================================
# BunnyX Kernel Build
# FULL LLVM/CLANG BUILD - GCC FREE
# Target: Qualcomm atoll / RMX2061 / Linux 4.14
# ============================================================

WORKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="$WORKDIR/out"

CLANG_REPO="https://gitlab.com/crdroidandroid/android_prebuilts_clang_host_linux-x86_clang-r547379.git"
CLANG_DIR="$WORKDIR/toolchains/clang-r547379"

BINUTILS_DIR="$WORKDIR/toolchains/llvm-binutils-stable"
ANYKERNEL_DIR="$WORKDIR/AnyKernel3"

DEVICE="RMX2061"
DEFCONFIG="atoll_defconfig"

KERNEL_NAME="BunnyBladeX-Perf"
BUILD_TYPE="ReSukiSU"
VERSION="v1.0.1"

DATE="$(date +%Y%m%d)"
TIME="$(date +%H%M)"

ZIPNAME="${KERNEL_NAME}-${DEVICE}-${BUILD_TYPE}-${TIME}-${DATE}-${VERSION}.zip"

# ============================================================
# GITHUB ARTIFACT NAME
# ============================================================

KERNEL_FULL_NAME="${KERNEL_NAME}-${DEVICE}-${BUILD_TYPE}-${TIME}-${DATE}-${VERSION}"

if [ -n "${GITHUB_ENV:-}" ]; then
    echo "KERNEL_FULL_NAME=${KERNEL_FULL_NAME}" >> "$GITHUB_ENV"
fi

# ============================================================
# COLOURS
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
# CCACHE
# ============================================================

export USE_CCACHE=1
export CCACHE_DIR="${CCACHE_DIR:-$WORKDIR/.ccache}"

mkdir -p "$CCACHE_DIR"

ccache -M 15G >/dev/null 2>&1 || true

# ============================================================
# TELEGRAM
# ============================================================

# Support both variable names.
BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-${TELEGRAM_TOKEN:-}}"
CHAT_ID="${TELEGRAM_CHAT_ID:-}"

send_msg() {

    if [[ -z "$BOT_TOKEN" || -z "$CHAT_ID" ]]; then
        echo -e "${YELLOW}Telegram credentials missing. Message skipped.${NC}"
        echo "BOT_TOKEN: $([[ -n "$BOT_TOKEN" ]] && echo SET || echo EMPTY)"
        echo "CHAT_ID:   $([[ -n "$CHAT_ID" ]] && echo SET || echo EMPTY)"
        return 0
    fi

    echo -e "${CYAN}Sending Telegram message...${NC}"

    RESPONSE="$(curl -sS \
        --connect-timeout 15 \
        --max-time 60 \
        -X POST \
        "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
        -d "chat_id=${CHAT_ID}" \
        -d "parse_mode=HTML" \
        --data-urlencode "text=$1" || true)"

    echo "Telegram response: ${RESPONSE}"

    if echo "$RESPONSE" | grep -q '"ok":true'; then
        echo -e "${GREEN}Telegram message sent.${NC}"
    else
        echo -e "${RED}Telegram message failed.${NC}"
    fi
}

send_file() {

    FILE="$1"
    CAPTION="$2"

    if [[ -z "$BOT_TOKEN" || -z "$CHAT_ID" ]]; then
        echo -e "${YELLOW}Telegram credentials missing. File upload skipped.${NC}"
        return 0
    fi

    if [[ ! -f "$FILE" ]]; then
        echo -e "${RED}Telegram upload file not found:${NC}"
        echo "$FILE"
        return 1
    fi

    echo -e "${CYAN}Uploading file to Telegram...${NC}"
    echo "File: $FILE"
    echo "Size: $(du -h "$FILE" | cut -f1)"

    RESPONSE="$(curl -sS \
        --connect-timeout 30 \
        --max-time 600 \
        -X POST \
        "https://api.telegram.org/bot${BOT_TOKEN}/sendDocument" \
        -F "chat_id=${CHAT_ID}" \
        -F "document=@${FILE}" \
        --form-string "parse_mode=HTML" \
        --form-string "caption=${CAPTION}" || true)"

    echo "Telegram upload response: ${RESPONSE}"

    if echo "$RESPONSE" | grep -q '"ok":true'; then
        echo -e "${GREEN}Telegram file upload successful.${NC}"
    else
        echo -e "${RED}Telegram file upload failed.${NC}"
    fi
}

# ============================================================
# START
# ============================================================

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}      BUNNYX KERNEL BUILD SYSTEM${NC}"
echo -e "${CYAN}========================================${NC}"

echo -e "${WHITE}Kernel:     ${KERNEL_NAME}${NC}"
echo -e "${WHITE}Device:     ${DEVICE}${NC}"
echo -e "${WHITE}Build:      ${BUILD_TYPE}${NC}"
echo -e "${WHITE}Version:    ${VERSION}${NC}"
echo -e "${WHITE}Compiler:   LLVM / Clang${NC}"

echo -e "${CYAN}========================================${NC}"

# ============================================================
# DIRECTORIES
# ============================================================

mkdir -p "$WORKDIR/toolchains"
mkdir -p "$OUT_DIR"

# ============================================================
# CLANG TOOLCHAIN
# ============================================================

if [ ! -x "$CLANG_DIR/bin/clang" ]; then

    echo ""
    echo -e "${YELLOW}Downloading Clang r547379...${NC}"

    git clone \
        --depth=1 \
        "$CLANG_REPO" \
        "$CLANG_DIR"

else

    echo -e "${GREEN}Using cached Clang r547379.${NC}"

fi

# ============================================================
# LLVM BINUTILS
# ============================================================

if [ ! -x "$BINUTILS_DIR/bin/ld.lld" ]; then

    echo ""
    echo -e "${YELLOW}Downloading LLVM binutils...${NC}"

    rm -rf "$BINUTILS_DIR"

    git clone \
        --depth=1 \
        https://android.googlesource.com/toolchain/llvm-binutils-stable \
        "$BINUTILS_DIR"

else

    echo -e "${GREEN}Using cached LLVM binutils.${NC}"

fi

# ============================================================
# LLVM PATH
# ============================================================

export PATH="$CLANG_DIR/bin:$BINUTILS_DIR/bin:$PATH"

export ARCH=arm64
export SUBARCH=arm64

# ============================================================
# LLVM COMPILERS
# ============================================================

export CC=clang
export CXX=clang++

export LD=ld.lld
export AR=llvm-ar
export NM=llvm-nm

export STRIP=llvm-strip
export OBJCOPY=llvm-objcopy
export OBJDUMP=llvm-objdump

# LLVM integrated assembler
export LLVM=1
export LLVM_IAS=1

# ARM64 target
export CLANG_TRIPLE=aarch64-linux-gnu-

# ============================================================
# HOST TOOLS - CLANG ONLY
# ============================================================

export HOSTCC=clang
export HOSTCXX=clang++
export HOSTLD=ld.lld

# ============================================================
# VERIFY CLANG TOOLCHAIN
# ============================================================

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}       LLVM TOOLCHAIN CHECK${NC}"
echo -e "${CYAN}========================================${NC}"

echo -e "${GREEN}Clang:${NC}"
clang --version | head -n 1

echo ""
echo -e "${GREEN}Clang++:${NC}"
clang++ --version | head -n 1

echo ""
echo -e "${GREEN}LLD:${NC}"
ld.lld --version | head -n 1

echo ""
echo -e "${GREEN}LLVM tools:${NC}"

command -v clang
command -v clang++
command -v ld.lld
command -v llvm-ar
command -v llvm-nm
command -v llvm-objcopy
command -v llvm-objdump
command -v llvm-strip

# ============================================================
# REQUIRED LLVM TOOLS CHECK
# ============================================================

for TOOL in \
    clang \
    clang++ \
    ld.lld \
    llvm-ar \
    llvm-nm \
    llvm-objcopy \
    llvm-objdump \
    llvm-strip
do

    if ! command -v "$TOOL" >/dev/null 2>&1; then
        echo -e "${RED}Missing LLVM tool: $TOOL${NC}"
        exit 1
    fi

done

echo ""
echo -e "${GREEN}LLVM toolchain ready.${NC}"

# ============================================================
# ANYKERNEL3
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

    echo -e "${GREEN}Using cached AnyKernel3.${NC}"

fi

# ============================================================
# BUILD INFORMATION
# ============================================================

JOBS="${JOBS:-$(nproc)}"

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}       BUILD CONFIGURATION${NC}"
echo -e "${CYAN}========================================${NC}"

echo -e "${WHITE}Device:       ${DEVICE}${NC}"
echo -e "${WHITE}Defconfig:    ${DEFCONFIG}${NC}"
echo -e "${WHITE}Kernel:       ${KERNEL_NAME}${NC}"
echo -e "${WHITE}Build type:   ${BUILD_TYPE}${NC}"
echo -e "${WHITE}Version:      ${VERSION}${NC}"
echo -e "${WHITE}Compiler:     Clang${NC}"
echo -e "${WHITE}Host CC:      Clang${NC}"
echo -e "${WHITE}Host CXX:     Clang++${NC}"
echo -e "${WHITE}Linker:       LLD${NC}"
echo -e "${WHITE}LLVM IAS:     Enabled${NC}"
echo -e "${WHITE}Jobs:         ${JOBS}${NC}"
echo -e "${WHITE}Output:       ${ZIPNAME}${NC}"
echo -e "${WHITE}CCACHE_DIR:   ${CCACHE_DIR}${NC}"
echo -e "${WHITE}Host:         $(uname -n)${NC}"
echo -e "${WHITE}CPU cores:    $(nproc)${NC}"

echo -e "${CYAN}========================================${NC}"

# ============================================================
# CLEAN OLD ARTIFACTS
# ============================================================

echo ""
echo -e "${YELLOW}Cleaning old artifacts...${NC}"

rm -f "$ANYKERNEL_DIR/zImage"
rm -f "$ANYKERNEL_DIR"/*.zip

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"

# ============================================================
# BUILD START
# ============================================================

START="$(date +%s)"

send_msg \
"<b>⚡ BunnyX Kernel Build Started</b>

<b>Device:</b> ${DEVICE}
<b>Kernel:</b> ${KERNEL_NAME}
<b>Build:</b> ${BUILD_TYPE}
<b>Compiler:</b> LLVM/Clang
<b>Host Compiler:</b> Clang
<b>Linker:</b> LLD
<b>Jobs:</b> ${JOBS}
<b>Version:</b> ${VERSION}"

# ============================================================
# DEFCONFIG
# ============================================================

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}          DEFCONFIG${NC}"
echo -e "${CYAN}========================================${NC}"

make \
    O="$OUT_DIR" \
    ARCH=arm64 \
    LLVM=1 \
    LLVM_IAS=1 \
    HOSTCC=clang \
    HOSTCXX=clang++ \
    HOSTLD=ld.lld \
    "$DEFCONFIG"

echo ""
echo -e "${GREEN}Defconfig completed.${NC}"

# ============================================================
# OLDDEFCONFIG
# ============================================================

make \
    O="$OUT_DIR" \
    ARCH=arm64 \
    LLVM=1 \
    LLVM_IAS=1 \
    HOSTCC=clang \
    HOSTCXX=clang++ \
    HOSTLD=ld.lld \
    olddefconfig

echo ""
echo -e "${GREEN}olddefconfig completed.${NC}"

# ============================================================
# ReSukiSU CONFIG CHECK
# ============================================================

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}       ReSukiSU CONFIG CHECK${NC}"
echo -e "${CYAN}========================================${NC}"

grep -E \
    '^(CONFIG_KSU=|CONFIG_KSU_SUSFS=|CONFIG_KSU_MULTI_MANAGER_SUPPORT=|CONFIG_KSU_FULL_NAME_FORMAT=|CONFIG_KSU_SUSFS_)' \
    "$OUT_DIR/.config" \
    || true

# ============================================================
# KERNEL BUILD
# ============================================================

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}          KERNEL COMPILATION${NC}"
echo -e "${CYAN}========================================${NC}"

echo -e "${MAGENTA}Starting FULL LLVM/Clang build...${NC}"

if ! make \
    -j"$JOBS" \
    O="$OUT_DIR" \
    ARCH=arm64 \
    CC=clang \
    LD=ld.lld \
    AR=llvm-ar \
    NM=llvm-nm \
    OBJCOPY=llvm-objcopy \
    OBJDUMP=llvm-objdump \
    STRIP=llvm-strip \
    HOSTCC=clang \
    HOSTCXX=clang++ \
    HOSTLD=ld.lld \
    LLVM=1 \
    LLVM_IAS=1 \
    CLANG_TRIPLE=aarch64-linux-gnu- \
    2>&1 | tee "$OUT_DIR/build.log"
then

    echo ""
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}           BUILD FAILED${NC}"
    echo -e "${RED}========================================${NC}"

    send_msg \
"<b>❌ BunnyX Kernel Build Failed</b>

<b>Device:</b> ${DEVICE}
<b>Kernel:</b> ${KERNEL_NAME}
<b>Compiler:</b> LLVM/Clang
<b>Linker:</b> LLD

Build failed."

    if [ -f "$OUT_DIR/build.log" ]; then

        send_file \
            "$OUT_DIR/build.log" \
            "❌ ${KERNEL_NAME} - LLVM/Clang Build Error"

    fi

    exit 1
fi

# ============================================================
# IMAGE CHECK
# ============================================================

IMG="$OUT_DIR/arch/arm64/boot/Image.gz-dtb"

if [ ! -f "$IMG" ]; then

    echo ""
    echo -e "${RED}Image.gz-dtb not found!${NC}"

    send_msg \
"<b>❌ Build completed but Image.gz-dtb is missing.</b>"

    exit 1

fi

IMAGE_SIZE="$(du -h "$IMG" | cut -f1)"

echo ""
echo -e "${GREEN}Kernel image successfully built.${NC}"
echo -e "${GREEN}Image size: ${IMAGE_SIZE}${NC}"

# ============================================================
# PACKAGING
# ============================================================

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}             PACKAGING${NC}"
echo -e "${CYAN}========================================${NC}"

cp "$IMG" "$ANYKERNEL_DIR/zImage"

cd "$ANYKERNEL_DIR"

rm -f "$ZIPNAME"

zip \
    -r9q \
    "$ZIPNAME" \
    * \
    -x ".git*" \
    -x "README.md" \
    -x "*.zip"

if [ ! -f "$ANYKERNEL_DIR/$ZIPNAME" ]; then

    echo -e "${RED}Failed to create AnyKernel3 ZIP.${NC}"

    send_msg \
"<b>❌ AnyKernel3 packaging failed.</b>"

    exit 1

fi

ZIP_SIZE="$(du -h "$ANYKERNEL_DIR/$ZIPNAME" | cut -f1)"

echo ""
echo -e "${GREEN}ZIP created successfully.${NC}"
echo -e "${GREEN}ZIP:  ${ZIPNAME}${NC}"
echo -e "${GREEN}Size: ${ZIP_SIZE}${NC}"

# ============================================================
# COPY ZIP TO OUT
# ============================================================

cp \
    "$ANYKERNEL_DIR/$ZIPNAME" \
    "$OUT_DIR/$ZIPNAME"

echo ""
echo -e "${GREEN}Artifact ZIP:${NC}"
echo -e "${GREEN}$OUT_DIR/$ZIPNAME${NC}"

# ============================================================
# FINISH
# ============================================================

END="$(date +%s)"
DIFF=$((END - START))

MINS=$((DIFF / 60))
SECS=$((DIFF % 60))

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}          BUILD COMPLETE${NC}"
echo -e "${GREEN}========================================${NC}"

echo -e "${WHITE}Kernel:    ${KERNEL_NAME}${NC}"
echo -e "${WHITE}Device:    ${DEVICE}${NC}"
echo -e "${WHITE}Build:     ${BUILD_TYPE}${NC}"
echo -e "${WHITE}Compiler:  LLVM/Clang${NC}"
echo -e "${WHITE}Host CC:   Clang${NC}"
echo -e "${WHITE}Linker:    LLD${NC}"
echo -e "${WHITE}ZIP:       ${ZIPNAME}${NC}"
echo -e "${WHITE}Size:      ${ZIP_SIZE}${NC}"
echo -e "${WHITE}Time:      ${MINS}m ${SECS}s${NC}"

echo -e "${GREEN}========================================${NC}"

# ============================================================
# TELEGRAM SUCCESS
# ============================================================

send_file \
    "$ANYKERNEL_DIR/$ZIPNAME" \
"<b>⚡ BunnyX Kernel Build Success</b>

<b>Kernel:</b> ${KERNEL_NAME}
<b>Device:</b> ${DEVICE}
<b>Build:</b> ${BUILD_TYPE}
<b>Compiler:</b> LLVM/Clang
<b>Host Compiler:</b> Clang
<b>Linker:</b> LLD
<b>Version:</b> ${VERSION}

<b>ZIP:</b> ${ZIPNAME}
<b>Size:</b> ${ZIP_SIZE}
<b>Time:</b> ${MINS}m ${SECS}s"

echo ""
echo -e "${GREEN}ZIP saved at:${NC}"
echo -e "${GREEN}${ANYKERNEL_DIR}/${ZIPNAME}${NC}"

echo ""
echo -e "${GREEN}Build finished successfully.${NC}"
