#!/bin/bash
set -e

# ===================== BASIC =====================

WORKDIR=$(pwd)

OUT_DIR="$WORKDIR/out"
CLANG_DIR="$WORKDIR/toolchains/clang"
GCC_DIR="$WORKDIR/toolchains/gcc"
ANYKERNEL_DIR="$WORKDIR/AnyKernel3"

DEVICE="RMX2061"
DEFCONFIG="atoll_defconfig"

KERNEL_NAME="BunnyX-atoll"
VERSION="v1.0.0"

DATE=$(date +%Y%m%d)
TIME=$(date +%H%M)

ZIPNAME="${KERNEL_NAME}-${DEVICE}-${TIME}-${DATE}-${VERSION}.zip"

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

# ===================== INFO =====================

echo "========================================"
echo "💾 STORAGE INFO"
echo "========================================"

df -h

echo "========================================"
echo "🧠 CPU INFO"
echo "========================================"

nproc

# ===================== TOOLCHAIN =====================

echo "========================================"
echo "🔧 SETTING UP TOOLCHAINS"
echo "========================================"

mkdir -p toolchains

rm -rf "$CLANG_DIR"
rm -rf "$GCC_DIR"

git clone --depth=1 \
https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86 \
"$CLANG_DIR"

CLANG_BIN=$(find "$CLANG_DIR" -type d -name "clang-*" | head -n 1)

git clone --depth=1 \
https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-gnu-9.3 \
"$GCC_DIR"

export PATH="$CLANG_BIN/bin:$GCC_DIR/bin:$PATH"

export ARCH=arm64
export SUBARCH=arm64

export CC=clang
export LD=ld.lld

# ===================== VERIFY =====================

echo "========================================"
echo "⚙️ CLANG VERSION"
echo "========================================"

clang --version

# ===================== ANYKERNEL =====================

echo "========================================"
echo "📦 ANYKERNEL"
echo "========================================"

if [ ! -d "$ANYKERNEL_DIR" ]; then
    git clone --depth=1 \
    --branch master \
    https://github.com/JOD-BUNNY07/AnyKernel3.git \
    "$ANYKERNEL_DIR"
fi

# ===================== START =====================

START=$(date +%s)

send_msg "
🚀 <b>Kernel Build Started</b>

📱 <code>$DEVICE</code>
⚙️ <code>Clang 22.0.2 + GCC</code>
🧠 <code>$KERNEL_NAME</code>
"

# ===================== CLEAN =====================

echo "========================================"
echo "🧹 CLEANING"
echo "========================================"

rm -rf "$OUT_DIR"

mkdir -p "$OUT_DIR"

rm -f "$ANYKERNEL_DIR/zImage"
rm -f "$ANYKERNEL_DIR"/*.zip

# ===================== DEFCONFIG =====================

echo "========================================"
echo "⚙️ GENERATING DEFCONFIG"
echo "========================================"

make O="$OUT_DIR" ARCH=arm64 "$DEFCONFIG"

# ===================== BUILD =====================

echo "========================================"
echo "🚀 BUILDING KERNEL"
echo "========================================"

if ! make -j$(nproc) \
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

    echo "========================================"
    echo "❌ BUILD FAILED"
    echo "========================================"

    send_msg "
❌ <b>Build Failed</b>
"

    send_file "$OUT_DIR/build.log" \
    "❌ Build Error Log"

    exit 1
fi

# ===================== IMAGE CHECK =====================

IMG="$OUT_DIR/arch/arm64/boot/Image.gz-dtb"

if [ ! -f "$IMG" ]; then

    echo "========================================"
    echo "❌ IMAGE NOT FOUND"
    echo "========================================"

    send_msg "
❌ <b>Kernel Image Missing</b>
"

    send_file "$OUT_DIR/build.log" \
    "❌ Missing Image Log"

    exit 1
fi

echo "========================================"
echo "✅ BUILD SUCCESS"
echo "========================================"

# ===================== PACKAGING =====================

echo "========================================"
echo "📦 PACKAGING"
echo "========================================"

cp "$IMG" "$ANYKERNEL_DIR/zImage"

cd "$ANYKERNEL_DIR"

zip -r9 "$ZIPNAME" * \
-x ".git*" README.md "*.zip" > /dev/null

# ===================== FINISH =====================

END=$(date +%s)
DIFF=$((END - START))

send_file "$ANYKERNEL_DIR/$ZIPNAME" \
"
✅ <b>Build Success</b>

📦 <code>$ZIPNAME</code>
⏱ <code>${DIFF}s</code>
"

echo "========================================"
echo "🎉 DONE!"
echo "========================================"
