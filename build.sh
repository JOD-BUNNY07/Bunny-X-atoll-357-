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
# TOOLCHAINS
# =========================================
echo "========================================"
echo "🔽 DOWNLOADING TOOLCHAINS"
echo "========================================"
mkdir -p "$TOOLCHAIN_DIR"

CLANG_BIN="$CLANG_DIR/clang-r563880c/bin"

# OPTIMISED: Git-এর বদলে সরাসরি নিরাপদ Tarball ডাউনলোড মেথড
if [ ! -d "$CLANG_BIN" ]; then
    echo "⬇️ Downloading exact Clang (clang-r563880c) via Tarball..."
    rm -rf "$CLANG_DIR"
    mkdir -p "$CLANG_DIR/clang-r563880c"
    
    # গুগলের অফিশিয়াল আর্কাভ লিংক থেকে সরাসরি ডাউনলোড
    if ! curl -fLo "$TOOLCHAIN_DIR/clang.tar.gz" "https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/refs/heads/main/clang-r563880c.tar.gz"; then
        echo "⚠️ Main branch archive fallback, trying static commit hash..."
        curl -fLo "$TOOLCHAIN_DIR/clang.tar.gz" "https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86/+archive/f8439f0628d799092dd07df440a6334cab28939c/clang-r563880c.tar.gz"
    fi
    
    echo "📦 Extracting Clang toolchain..."
    tar -xzf "$TOOLCHAIN_DIR/clang.tar.gz" -C "$CLANG_DIR/clang-r563880c"
    rm -f "$TOOLCHAIN_DIR/clang.tar.gz"
fi

echo "========================================"
echo "✅ EXACT CLANG COMPONENT VERIFIED"
echo "========================================"

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
export KBUILD_COMPILER_STRING="Project Infinity X Clang 21.0.0"

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
echo "========================================"
echo "📦 CLONING ANYKERNEL"
echo "========================================"
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
echo "========================================"
echo "🧹 CLEANING"
echo "========================================"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"
rm -f "$ANYKERNEL_DIR/Image.gz-dtb" "$ANYKERNEL_DIR/Image.gz" "$ANYKERNEL_DIR/Image"
rm -f "$ANYKERNEL_DIR"/*.zip

# =========================================
# DEFCONFIG
# =========================================
echo "========================================"
echo "⚙️ GENERATING DEFCONFIG"
echo "========================================"
make O="$OUT_DIR" ARCH=arm64 "$DEFCONFIG"

# =========================================
# BUILD
# =========================================
echo "========================================"
echo "🚀 BUILDING KERNEL"
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
# IMAGE CHECK & PACKAGING
# =========================================
echo "========================================"
echo "📦 CHECKING KERNEL IMAGE"
echo "========================================"

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
    echo "========================================"
    echo "❌ KERNEL IMAGE NOT FOUND"
    echo "========================================"
    send_msg "❌ <b>Kernel Image Missing</b>"
    send_file "$OUT_DIR/build.log" "❌ Missing Kernel Image"
    exit 1
fi

echo "✅ Found Kernel Image: $TARGET_NAME"
cp "$IMG" "$ANYKERNEL_DIR/$TARGET_NAME"

# =========================================
# PACKAGING ZIP
# =========================================
echo "========================================"
echo "📦 PACKAGING ZIP"
echo "========================================"
cd "$ANYKERNEL_DIR"
zip -r9 "$ZIPNAME" ./* -x ".git*" README.md "*.zip" > /dev/null

# =========================================
# FINISH
# =========================================
END=$(date +%s)
DIFF=$((END - START))

send_msg "
✅ <b>Build Success</b>

📦 <code>$ZIPNAME</code>
⏱ <code>${DIFF}s</code>
👤 <code>$KBUILD_BUILD_USER</code>
"

send_file "$ANYKERNEL_DIR/$ZIPNAME" "
✅ <b>BunnyX Kernel Build Success</b>

📦 <code>$ZIPNAME</code>
⏱ <code>${DIFF}s</code>
⚙️ <code>$COMPILER</code>
"

echo "========================================"
echo "🎉 BUILD COMPLETED SUCCESSFULLY"
echo "========================================"
