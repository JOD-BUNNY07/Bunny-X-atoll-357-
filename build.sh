#!/bin/bash
set -e

WORKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$WORKDIR" || exit 1
OUT_DIR="$WORKDIR/out"
ANYKERNEL_DIR="$HOME/AnyKernel3"

DEVICE="RMX2061"
DEFCONFIG="atoll_defconfig"
KERNEL_NAME="Bunny-X-Zenith-BakaSU"
VERSION="v1.0.0"

DATE=$(date +%Y%m%d)
TIME=$(date +%H%M)
ZIPNAME="${KERNEL_NAME}-${DEVICE}-${TIME}-${DATE}-${VERSION}.zip"

# ===================== COLOURS =====================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[1;34m'
CYAN='\033[1;36m'
WHITE='\033[1;37m'
NC='\033[0m'
# ===================================================

# ===================== CCACHE =====================
export USE_CCACHE=1
export CCACHE_DIR="$WORKDIR/.ccache"
mkdir -p "$CCACHE_DIR"
ccache -M 15G >/dev/null 2>&1 || true

# ===================== TOOLCHAIN =====================

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}    BUNNYX KERNEL BUILD SYSTEM${NC}"
echo -e "${CYAN}========================================${NC}"

# Use system clang/ld.lld (pre-installed on ubuntu-latest runners)
if command -v clang >/dev/null 2>&1 && command -v ld.lld >/dev/null 2>&1; then
    echo -e "${GREEN}Using system clang and ld.lld${NC}"
    TOOLCHAIN_BIN="$(dirname "$(command -v clang)")"
else
    echo -e "${YELLOW}System clang not found, installing...${NC}"
    sudo apt-get update -qq
    sudo apt-get install -y -qq clang llvm lld
    TOOLCHAIN_BIN="$(dirname "$(command -v clang)")"
fi

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
export CLANG_TRIPLE=aarch64-linux-gnu-
export CROSS_COMPILE=aarch64-linux-gnu-

# Verify required compiler tools
for tool in clang ld.lld llvm-ar llvm-nm llvm-strip llvm-objcopy llvm-objdump; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo -e "${RED}Missing LLVM tool: $tool${NC}"
        exit 1
    fi
done

echo -e "${GREEN}Clang: $(clang --version | head -n1)${NC}"
echo -e "${GREEN}LD:    $(ld.lld --version | head -n1)${NC}"

# ===================== ANYKERNEL3 =====================
if [ ! -d "$ANYKERNEL_DIR" ]; then
    echo -e "${YELLOW}Cloning AnyKernel3...${NC}"
    git clone --depth=1 https://github.com/theshaenix/AnyKernel3.git "$ANYKERNEL_DIR"
fi

# ===================== BUILD START =====================
START=$(date +%s)

echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}    BUILDING${NC}"
echo -e "${CYAN}========================================${NC}"

# Minimal cleanup
rm -f "$ANYKERNEL_DIR/zImage" "$ANYKERNEL_DIR"/*.zip
rm -rf "$OUT_DIR"

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
    exit 1
fi

# ===================== IMAGE CHECK =====================
IMG="$OUT_DIR/arch/arm64/boot/Image.gz-dtb"

if [ ! -f "$IMG" ]; then
    echo -e "${RED}Image not found${NC}"
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

# Move zip to out for artifact collection
mv "$ANYKERNEL_DIR/$ZIPNAME" "$OUT_DIR/"

echo -e "${GREEN}Zip saved to: ${OUT_DIR}/${ZIPNAME}${NC}"
