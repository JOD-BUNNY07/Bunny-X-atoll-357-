#!/bin/bash
set -e

WORKDIR=$(pwd)
OUT_DIR="$WORKDIR/out"
NEUTRON_TAG="${NEUTRON_TAG:-06092026}"
NEUTRON_DIR="$WORKDIR/toolchains/neutron-clang-${NEUTRON_TAG}"
NEUTRON_URL="https://github.com/Neutron-Toolchains/clang-build-catalogue/releases/download/${NEUTRON_TAG}/neutron-clang-${NEUTRON_TAG}.tar.zst"

# Fallback compiler
CLANG_REPO="https://gitlab.com/crdroidandroid/android_prebuilts_clang_host_linux-x86_clang-r547379.git"
CLANG_DIR="$WORKDIR/toolchains/clang-r547379"
BINUTILS_DIR="$WORKDIR/toolchains/llvm-binutils-stable"
ANYKERNEL_DIR="$WORKDIR/AnyKernel3"

DEVICE="RMX2061"
DEFCONFIG="atoll_defconfig"
KERNEL_NAME="BunnyBladeX-Perf-BakaSU"
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

# ===== NEUTRON CLANG =====

NEUTRON_BIN=""

if [ -x "$NEUTRON_DIR/bin/clang" ]; then
    NEUTRON_BIN="$NEUTRON_DIR/bin"
    echo -e "${GREEN}Using cached Neutron Clang ${NEUTRON_TAG}${NC}"
else
    echo -e "${YELLOW}Downloading Neutron Clang ${NEUTRON_TAG}...${NC}"

    ARCHIVE="$WORKDIR/toolchains/neutron-clang-${NEUTRON_TAG}.tar.zst"
    EXTRACT_DIR="$WORKDIR/toolchains/neutron-extract-${NEUTRON_TAG}"

    if curl -fL --retry 5 --retry-delay 5 \
        --connect-timeout 20 \
        -o "$ARCHIVE" "$NEUTRON_URL" &&
        mkdir -p "$EXTRACT_DIR" &&
        tar --zstd -xf "$ARCHIVE" -C "$EXTRACT_DIR"; then

        FOUND_CLANG=$(find "$EXTRACT_DIR" -maxdepth 5 \
            \( -type f -o -type l \) -path '*/bin/clang' -print -quit)

        if [ -n "$FOUND_CLANG" ]; then
            NEUTRON_BIN="$(dirname "$FOUND_CLANG")"

            if [ "$NEUTRON_BIN" != "$NEUTRON_DIR/bin" ]; then
                mkdir -p "$NEUTRON_DIR"
                cp -a "$NEUTRON_BIN/." "$NEUTRON_DIR/bin/"
                NEUTRON_BIN="$NEUTRON_DIR/bin"
            fi

            echo -e "${GREEN}Neutron Clang extracted successfully${NC}"
        fi
    fi

    rm -rf "$EXTRACT_DIR"
    rm -f "$ARCHIVE"
fi

# ===== FALLBACK CLANG =====

if [ -n "$NEUTRON_BIN" ] && [ -x "$NEUTRON_BIN/clang" ]; then
    TOOLCHAIN_BIN="$NEUTRON_BIN"
    echo -e "${GREEN}Selected compiler: Neutron Clang ${NEUTRON_TAG}${NC}"
else
    echo -e "${YELLOW}Neutron unavailable; using fallback Clang r547379${NC}"

    if [ ! -d "$CLANG_DIR" ]; then
        git clone --depth=1 "$CLANG_REPO" "$CLANG_DIR"
    fi

    if [ ! -x "$CLANG_DIR/bin/clang" ]; then
        echo -e "${RED}Fallback Clang not found${NC}"
        exit 1
    fi

    if [ ! -d "$BINUTILS_DIR" ]; then
        git clone --depth=1 \
            https://android.googlesource.com/toolchain/llvm-binutils-stable \
            "$BINUTILS_DIR"
    fi

    TOOLCHAIN_BIN="$CLANG_DIR/bin"
    export PATH="$BINUTILS_DIR/bin:$PATH"
fi

# ===== PATH AND LLVM TOOLS =====

export PATH="$TOOLCHAIN_BIN:$PATH"
export ARCH=arm64
export SUBARCH=arm64

export CC=clang
export LD=ld.lld
export AR=llvm-ar
export NM=llvm-nm
export STRIP=llvm-strip
export OBJCOPY=llvm-objcopy
export OBJDUMP=llvm-objdump

# Verify required compiler tools
for tool in clang ld.lld llvm-ar llvm-nm llvm-strip llvm-objcopy llvm-objdump; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo -e "${RED}Missing LLVM tool: $tool${NC}"
        exit 1
    fi
done

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

# Kernel FCM level 7 (Android 17, 4.14) requirements checked by the ROM's VINTF step.
required_configs=(
  CONFIG_AS_IS_LLVM CONFIG_CC_IS_CLANG CONFIG_CFI_CLANG CONFIG_HIDRAW
  CONFIG_HID_PLAYSTATION CONFIG_KFENCE CONFIG_LD_IS_LLD CONFIG_NET_ACT_BPF
  CONFIG_NET_ACT_POLICE CONFIG_NET_CLS_MATCHALL CONFIG_NET_SCH_TBF
  CONFIG_PLAYSTATION_FF CONFIG_RD_LZ4 CONFIG_SHADOW_CALL_STACK
  CONFIG_SECURITY_NETWORK CONFIG_SECURITY_SELINUX
  CONFIG_CGROUPS CONFIG_CGROUP_SCHED CONFIG_FAIR_GROUP_SCHED
)
for config in "${required_configs[@]}"; do
  if ! grep -qx "$config=y" "$OUT_DIR/.config"; then
    echo -e "\n❌ \033[1;31mRequired kernel config missing: $config\033[0m"
    exit 1
  fi
done

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
