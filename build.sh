#!/bin/bash
set -e

=========================================

BUNNYX KERNEL BUILD SCRIPT

Optimized Stable Build Script

=========================================

WORKDIR=$(pwd)

OUT_DIR="$WORKDIR/out"

TOOLCHAIN_DIR="$WORKDIR/toolchains"

CLANG_DIR="$TOOLCHAIN_DIR/clang"
GCC64_DIR="$TOOLCHAIN_DIR/gcc64"

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

=========================================

TELEGRAM

=========================================

BOT_TOKEN="${TELEGRAM_TOKEN}"
CHAT_ID="${TELEGRAM_CHAT_ID}"

send_msg() {
if [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ]; then
echo "Telegram not configured"
return
fi

curl -s -X POST \
    "https://api.telegram.org/bot$BOT_TOKEN/sendMessage" \
    -d chat_id="$CHAT_ID" \
    -d parse_mode=HTML \
    -d text="$1" > /dev/null

}

send_file() {
if [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ]; then
echo "Telegram not configured"
return
fi

if [ ! -f "$1" ]; then
    echo "File not found: $1"
    return
fi

curl -s -X POST \
    "https://api.telegram.org/bot$BOT_TOKEN/sendDocument" \
    -F chat_id="$CHAT_ID" \
    -F document=@"$1" \
    -F parse_mode=HTML \
    -F caption="$2" > /dev/null

}

=========================================

SYSTEM INFO

=========================================

echo "========================================"
echo "💾 STORAGE INFO"
echo "========================================"

df -h

echo "========================================"
echo "🧠 CPU INFO"
echo "========================================"

nproc

=========================================

DEPENDENCIES

=========================================

echo "========================================"
echo "📦 INSTALLING DEPENDENCIES"
echo "========================================"

sudo apt update

sudo apt install -y 
bc bison build-essential curl flex git 
libssl-dev lzop python3 zip unzip 
gcc g++ ccache

=========================================

CCACHE

=========================================

export USE_CCACHE=1
export CCACHE_DIR="$WORKDIR/.ccache"

ccache -M 10G

=========================================

TOOLCHAINS

=========================================

echo "========================================"
echo "🔽 CLONING TOOLCHAINS"
echo "========================================"

mkdir -p "$TOOLCHAIN_DIR"

rm -rf "$CLANG_DIR"
rm -rf "$GCC64_DIR"

=========================================

CLANG

=========================================

git clone --depth=1 
https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86 
"$CLANG_DIR"

CLANG_BIN=$(find "$CLANG_DIR" -type d -name "clang-*" | head -n 1)

if [ -z "$CLANG_BIN" ]; then

echo "========================================"
echo "❌ CLANG NOT FOUND"
echo "========================================"

exit 1

fi

echo "========================================"
echo "✅ CLANG FOUND"
echo "========================================"

echo "$CLANG_BIN"

=========================================

GCC64

=========================================

git clone --depth=1 
https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-gnu-9.3 
"$GCC64_DIR"

=========================================

EXPORTS

=========================================

export PATH="$CLANG_BIN/bin:$GCC64_DIR/bin:$PATH"

export ARCH=arm64
export SUBARCH=arm64

export CC=clang
export LD=ld.lld

export LLVM=1
export LLVM_IAS=1

export AR=llvm-ar
export NM=llvm-nm
export OBJCOPY=llvm-objcopy
export OBJDUMP=llvm-objdump
export STRIP=llvm-strip

=========================================

VERIFY LLVM

=========================================

echo "========================================"
echo "⚙️ VERIFY LLVM TOOLS"
echo "========================================"

which clang
which ld.lld
which llvm-ar
which llvm-nm
which llvm-objdump

echo "========================================"
echo "⚙️ CLANG VERSION"
echo "========================================"

clang --version

COMPILER=$(clang --version | head -n1)

=========================================

ANYKERNEL

=========================================

echo "========================================"
echo "📦 CLONING ANYKERNEL"
echo "========================================"

if [ ! -d "$ANYKERNEL_DIR" ]; then
git clone --depth=1 
https://github.com/JOD-BUNNY07/AnyKernel3.git 
"$ANYKERNEL_DIR"
fi

=========================================

BUILD START

=========================================

START=$(date +%s)

send_msg "
🚀 <b>BunnyX Kernel Build Started</b>

📱 <code>$DEVICE</code>
🧠 <code>$KERNEL_NAME</code>
⚙️ <code>$COMPILER</code>
"

=========================================

CLEAN

=========================================

echo "========================================"
echo "🧹 CLEANING"
echo "========================================"

rm -rf "$OUT_DIR"

mkdir -p "$OUT_DIR"

rm -f "$ANYKERNEL_DIR/Image.gz-dtb"
rm -f "$ANYKERNEL_DIR"/*.zip

=========================================

DEFCONFIG

=========================================

echo "========================================"
echo "⚙️ GENERATING DEFCONFIG"
echo "========================================"

make O="$OUT_DIR" ARCH=arm64 "$DEFCONFIG"

make O="$OUT_DIR" ARCH=arm64 olddefconfig

=========================================

BUILD

=========================================

echo "========================================"
echo "🚀 BUILDING KERNEL"
echo "========================================"

if ! make -j"$(nproc)" 
O="$OUT_DIR" 
ARCH=arm64 
CC=clang 
HOSTCC=gcc 
HOSTCXX=g++ 
LD=ld.lld 
LLVM=1 
LLVM_IAS=1 
CLANG_TRIPLE=aarch64-linux-gnu- 
CROSS_COMPILE=aarch64-linux-gnu- 
AR=llvm-ar 
NM=llvm-nm 
OBJCOPY=llvm-objcopy 
OBJDUMP=llvm-objdump 
STRIP=llvm-strip 
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

=========================================

IMAGE CHECK

=========================================

IMG=$(find "$OUT_DIR/arch/arm64/boot" 
-name "Image*" | head -n 1)

if [ ! -f "$IMG" ]; then

echo "========================================"
echo "❌ IMAGE NOT FOUND"
echo "========================================"

send_msg "

❌ <b>Kernel Image Missing</b>
"

send_file "$OUT_DIR/build.log" \
"❌ Missing Kernel Image"

exit 1

fi

echo "========================================"
echo "✅ BUILD SUCCESS"
echo "========================================"

=========================================

PACKAGING

=========================================

echo "========================================"
echo "📦 PACKAGING ZIP"
echo "========================================"

cp "$IMG" "$ANYKERNEL_DIR/zImage"

cd "$ANYKERNEL_DIR"

zip -r9 "$ZIPNAME" ./* 
-x ".git*" README.md "*.zip" > /dev/null

=========================================

FINISH

=========================================

END=$(date +%s)
DIFF=$((END - START))

send_msg "
✅ <b>Build Success</b>

📦 <code>$ZIPNAME</code>
⏱ <code>${DIFF}s</code>
👤 <code>$KBUILD_BUILD_USER</code>
"

send_file "$ANYKERNEL_DIR/$ZIPNAME" 
"
✅ <b>BunnyX Kernel Build Success</b>

📦 <code>$ZIPNAME</code>
⏱ <code>${DIFF}s</code>
⚙️ <code>$COMPILER</code>
"

echo "========================================"
echo "🎉 BUILD COMPLETED"
echo "========================================"
