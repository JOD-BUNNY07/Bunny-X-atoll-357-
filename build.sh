#!/bin/bash
set -e

# =========================================
# BUNNYX KERNEL BUILD SCRIPT
# EXACT SAME CLANG AS PROJECT INFINITY X
# clang-r563880c (Android LLVM 21)
# =========================================

WORKDIR=$(pwd)
OUT_DIR="$WORKDIR/out"
TOOLCHAIN_DIR="$WORKDIR/toolchains"
CLANG_DIR="$TOOLCHAIN_DIR/clang"
GCC64_DIR="$TOOLCHAIN_DIR/gcc64"
GCC32_DIR="$TOOLCHAIN_DIR/gcc32"
ANYKERNEL_DIR="$WORKDIR/AnyKernel3"

DEVICE="RMX2061"
DEFCONFIG="atoll_defconfig"
KERNEL_NAME="BunnyX-atoll-KSUN"
VERSION="v1.0.0"

export KBUILD_BUILD_USER="JOD_BUNNY"
export KBUILD_BUILD_HOST="BunnyX-PERF"

DATE=$(date +%Y%m%d)
TIME=$(date +%H%M)
ZIPNAME="${KERNEL_NAME}-${DEVICE}-${TIME}-${DATE}-${VERSION}.zip"

# =========================================
# TELEGRAM
# =========================================
BOT_TOKEN="${TELEGRAM_TOKEN}"
CHAT_ID="${TELEGRAM_CHAT_ID}"

send_msg() {
    [ -z "$BOT_TOKEN" ] && return
    curl -s -X POST \
        "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
        -d chat_id="$CHAT_ID" \
        -d parse_mode=HTML \
        -d text="$1" > /dev/null
}

send_file() {
    [ -z "$BOT_TOKEN" ] && return
    curl -s -X POST \
        "https://api.telegram.org/bot$BOT_TOKEN/sendDocument" \
        -F chat_id="$CHAT_ID" \
        -F document=@"$1" \
        -F parse_mode=HTML \
        -F caption="$2" > /dev/null
}

# =========================================
# SYSTEM INFO
# =========================================
echo "========================================"
echo "💾 STORAGE INFO"
echo "========================================"
df -h

echo "========================================"
echo "🧠 CPU INFO"
echo "========================================"
nproc

# =========================================
# DEPENDENCIES
# =========================================
echo "========================================"
echo "📦 INSTALLING DEPENDENCIES"
echo "========================================"
sudo apt update
sudo apt install -y \
    bc bison build-essential curl flex git \
    libssl-dev lzop python3 zip unzip \
    gcc g++ ccache libelf-dev

# =========================================
# CCACHE
# =========================================
export USE_CCACHE=1
export CCACHE_DIR="$WORKDIR/.ccache"
ccache -M 10G

# =========================================
# TOOLCHAINS (DOWNLOAD SOLUTION)
# =========================================
echo "========================================"
echo "🔽 DOWNLOADING TOOLCHAINS"
echo "========================================"
mkdir -p "$TOOLCHAIN_DIR"

if [ ! -d "$CLANG_DIR/clang-r563880c" ]; then
    echo "⬇️ Cloning exact Clang toolchain (clang-r563880c)..."
    rm -rf "$CLANG_DIR"
    git clone --depth=1 --sparse https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86 -b main "$CLANG_DIR"
    cd "$CLANG_DIR"
    git sparse-checkout set clang-r563880c
    cd "$WORKDIR"
fi

# Set Exact Binary Path
CLANG_BIN="$CLANG_DIR/clang-r563880c/bin"

if [ ! -d "$CLANG_BIN" ]; then
    echo "========================================"
    echo "❌ ERROR: Clang Binary Folder Not Found!"
    echo "========================================"
    exit 1
fi

echo "✅ EXACT CLANG FOUND: $CLANG_BIN"

# GCC64
if [ ! -d "$GCC64_DIR" ]; then
    git clone --depth=1 \
        https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-gnu-9.3 \
        "$GCC64_DIR"
fi

# GCC32
if [ ! -d "$GCC32_DIR" ]; then
    git clone --depth=1 \
        https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_arm_arm-linux-gnueabi-9.3 \
        "$GCC32_DIR"
fi

# =========================================
# EXPORTS
# =========================================
export PATH="$CLANG_BIN:$GCC64_DIR/bin:$GCC32_DIR/bin:$PATH"

export ARCH=arm64
export SUBARCH=arm64
export KEYBOARD_SUPPRESS_UNKNOWN=1

# =========================================
# CLANG VERSION CHECK
# =========================================
echo "========================================"
echo "⚙️ CLANG VERSION"
echo "========================================"
clang --version

# =========================================
# ANYKERNEL
# =========================================
if [ ! -d "$ANYKERNEL_DIR" ]; then
    git clone --depth=1 \
        --branch master \
        https://github.com/JOD-BUNNY07/AnyKernel3.git \
        "$ANYKERNEL_DIR"
fi

# =========================================
# BUILD START
# =========================================
START=$(date +%s)
COMPILER=$(clang --version | head -n1)

send_msg "
🚀 <b>BunnyX Kernel Build Started</b>

📱 <code>$DEVICE</code>
🧠 <code>$KERNEL_NAME</code>
⚙️ <code>$COMPILER</code>
"

# =========================================
# CLEAN
# =========================================
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"
rm -f "$ANYKERNEL_DIR/Image.gz-dtb" "$ANYKERNEL_DIR/Image.gz" "$ANYKERNEL_DIR/Image"
rm -f "$ANYKERNEL_DIR"/*.zip

# =========================================
# DEFCONFIG
# =========================================
make O="$OUT_DIR" ARCH=arm64 "$DEFCONFIG"

# =========================================
# COMPILING KERNEL
# =========================================
echo "========================================"
echo "🚀 COMPILING KERNEL WITH LLVM=1"
echo "========================================"

if ! make -j"$(nproc)" O="$OUT_DIR" ARCH=arm64 \
    CC=clang \
    HOSTCC=gcc \
    HOSTCXX=g++ \
    LLVM=1 \
    LLVM_IAS=1 \
    CLANG_TRIPLE=aarch64-linux-gnu- \
    CROSS_COMPILE=aarch64-linux-gnu- \
    CROSS_COMPILE_ARM32=arm-linux-gnueabi- \
    2>&1 | tee "$OUT_DIR/build.log"; then

    echo "========================================"
    echo "❌ BUILD FAILED"
    echo "========================================"
    send_msg "❌ <b>Build Failed</b>"
    send_file "$OUT_DIR/build.log" "❌ Build Error Log"
    exit 1
fi

# =========================================
# SMART IMAGE CHECK & PACKAGING
# =========================================
if [ -f "$OUT_DIR/arch/arm64/boot/Image.gz-dtb" ]; then
    IMG="$OUT_DIR/arch/arm64/boot/Image.gz-dtb"
    TARGET_NAME="Image.gz-dtb"
elif [ -f "$OUT_DIR/arch/arm64/boot/Image.gz" ]; then
    IMG="$OUT_DIR/arch/arm64/boot/Image.gz"
    TARGET_NAME="Image.gz"
elif [ -f "$OUT_DIR/arch/arm64/boot/Image" ]; then
    IMG="$OUT_DIR/arch/arm64/boot/Image"
    TARGET_NAME="Image"
else
    echo "❌ KERNEL IMAGE NOT FOUND"
    send_msg "❌ <b>Kernel Image Missing</b>"
    exit 1
fi

cp "$IMG" "$ANYKERNEL_DIR/$TARGET_NAME"

# Packaging Zip
cd "$ANYKERNEL_DIR"
zip -r9 "$ZIPNAME" ./* -x ".git*" README.md "*.zip" > /dev/null

END=$(date +%s)
DIFF=$((END - START))

send_msg "
✅ <b>Build Success</b>
📦 <code>$ZIPNAME</code>
⏱ <code>${DIFF}s</code>
"

send_file "$ANYKERNEL_DIR/$ZIPNAME" "✅ <b>BunnyX Kernel Success!</b>"
echo "🎉 COMPLETED SUCCESSFULLY"
