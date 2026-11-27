#!/bin/bash

# ============================================================
# Pre-build checks for required toolchains and AnyKernel3
# ============================================================

# Paths
CLANG_DIR=~/toolchains/clang
GCC_DIR=~/toolchains/gcc-aarch64-linux-gnu-9.3
ANYKERNEL_DIR=~/AnyKernel3

# Use system clang/ld.lld if available (GitHub ubuntu-latest runners have them pre-installed)
# Only clone from LineageOS as fallback when system tools are missing.
if command -v clang >/dev/null 2>&1 && command -v ld.lld >/dev/null 2>&1; then
  echo -e "\n✅ \033[1;32mSystem clang and ld.lld found. Using system toolchain.\033[0m"
  CLANG_PATH=$(dirname "$(command -v clang)")
  # Find llvm-ar, llvm-nm, etc. alongside clang
  export LLVM_PATH="$CLANG_PATH"
else
  echo -e "\n🔍 \033[1;33mSystem clang/ld.lld not found. Cloning LineageOS toolchain...\033[0m"
  git config --global --unset url."https://github.com/".insteadOf 2>/dev/null || true
  git clone --depth=1 --branch lineage-20.0 \
    https://github.com/LineageOS/android_prebuilts_clang_kernel_linux-x86_clang-r416183b.git "$CLANG_DIR" 2>/dev/null || \
    echo -e "\n⚠️  \033[1;33mClang clone failed, will try system clang.\033[0m"
  CLANG_PATH=$CLANG_DIR/bin
  export LLVM_PATH=$CLANG_DIR/bin
fi

if [ ! -d "$GCC_DIR" ]; then
  echo -e "\n🔍 \033[1;33mGCC toolchain not found. Cloning...\033[0m"
  git config --global --unset url."https://github.com/".insteadOf 2>/dev/null || true
  git clone --depth=1 --branch lineage-24.0 \
    https://github.com/LineageOS/android_prebuilts_gcc_linux-x86_aarch64_aarch64-linux-gnu-9.3.git "$GCC_DIR" 2>/dev/null || \
    echo -e "\n⚠️  \033[1;33mGCC clone failed, GCC not required for Clang build.\033[0m"
else
  echo -e "\n✅ \033[1;32mGCC toolchain already present.\033[0m"
fi

GCC_PATH=$GCC_DIR/bin

if [ ! -d "$ANYKERNEL_DIR" ]; then
  echo -e "\n🔍 \033[1;33mAnyKernel3 not found. Cloning...\033[0m"
  git config --global --unset url."https://github.com/".insteadOf 2>/dev/null || true
  git clone --depth=1 https://github.com/theshaenix/AnyKernel3.git "$ANYKERNEL_DIR" 2>/dev/null || \
    echo -e "\n❌ \033[1;31mAnyKernel3 clone failed!\033[0m" && exit 1
else
  echo -e "\n✅ \033[1;32mAnyKernel3 folder already present.\033[0m"
fi

# ============================================================
# Build Script
# ============================================================

# Kernel build configuration
KERNEL_NAME="Bunny-X-Zenith-BakaSU"
DEVICE="RMX2061"
VARIANT="perf"
BUILD_TYPE="KSU"
VERSION_NUMBER="v1.0.0"

DATE=$(date +%Y%m%d)
TIME=$(date +%H%M)
BASE_ZIPNAME="${KERNEL_NAME}-${VARIANT}-${DEVICE}-${BUILD_TYPE}-${TIME}-${DATE}-${VERSION_NUMBER}"
ZIPNAME="${BASE_ZIPNAME}.zip"

# Paths
export KERNEL_ROOT="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
export CLANG_PATH
export GCC_PATH
export ANYKERNEL_DIR=$ANYKERNEL_DIR
export OUT_DIR=out

export PATH=$CLANG_PATH:$GCC_PATH:$PATH
export ARCH=arm64
export CLANG_TRIPLE=aarch64-linux-gnu-
export CROSS_COMPILE=aarch64-linux-gnu-

# Verify clang is available
if ! command -v clang >/dev/null 2>&1; then
  echo -e "\n❌ \033[1;31mclang not found in PATH. Cannot build kernel.\033[0m"
  exit 1
fi

# Allow constrained builders to lower parallelism without editing this script.
JOBS="${JOBS:-$(nproc)}"

# The filtered live output keeps routine builds readable, while build.log keeps
# the complete compiler output.  When a target fails, show the first failure
# and the preceding lines from that raw log; this is usually where clang (or a
# host tool) explains why the subsequent missing-object errors occurred.
show_first_failure_context() {
  local failure_line context_start context_end

  failure_line=$(grep -n -m1 -E \
    '(^|: )(fatal )?error:|fatal:|clang:.*(unable|crash)|make(\[[0-9]+\])?: \*\*\*' \
    "$OUT_DIR/build.log" | cut -d: -f1)

  if [ -n "$failure_line" ]; then
    context_start=$((failure_line > 40 ? failure_line - 40 : 1))
    context_end=$((failure_line + 20))
    echo -e "\n🔎 \033[1;36mFirst failure context from $OUT_DIR/build.log:\033[0m"
    sed -n "${context_start},${context_end}p" "$OUT_DIR/build.log"
  fi
}

# =====================[ START PROCESS ]=====================

echo -e "\n🛠️  \033[1;34mStarting Kernel Build: $BASE_ZIPNAME\033[0m"

echo -e "\n🧹 \033[1;33mCleaning output and ccache...\033[0m"
rm -rf $OUT_DIR/*
rm -f "$ANYKERNEL_DIR/zImage"
ccache -C > /dev/null 2>&1

echo -e "\n🔧 \033[1;36mCompiler Info:\033[0m"
clang --version | head -n 1
aarch64-linux-gnu-gcc --version | head -n 1

echo -e "\n📱 \033[1;32mTarget Device: $DEVICE\033[0m"
echo -e "🧵 \033[1;36mParallel build jobs: $JOBS\033[0m"

# =====================[ DEFCONFIG ]=====================

echo -e "\n📄 \033[1;36mSetting up defconfig...\033[0m"
make O=$OUT_DIR ARCH=arm64 LLVM=1 LLVM_IAS=1 CC=clang LD=ld.lld atoll_defconfig

if [ $? -ne 0 ]; then
  echo -e "\n❌ \033[1;31mDefconfig failed. Exiting.\033[0m"
  exit 1
fi

# =====================[ COMPILING ]=====================

echo -e "\n🚀 \033[1;35mStarting compilation...\033[0m"
make -j"$JOBS" O=$OUT_DIR \
  ARCH=arm64 \
  LLVM=1 \
  LLVM_IAS=1 \
  CC=clang \
  LD=ld.lld \
  AR=llvm-ar \
  NM=llvm-nm \
  OBJCOPY=llvm-objcopy \
  OBJDUMP=llvm-objdump \
  STRIP=llvm-strip \
  CLANG_TRIPLE=$CLANG_TRIPLE \
  CROSS_COMPILE=$CROSS_COMPILE \
  2>&1 | tee out/build.log | grep --line-buffered -E \
  "warning:|error:|fatal:|Killed|No space left|Segmentation fault|clang:.*(unable|crash)|make(\[[0-9]+\])?: \*\*\*" | sed \
  -e 's/warning:/\x1b[1;33mwarning:\x1b[0m/g' \
  -e 's/error:/\x1b[1;31merror:\x1b[0m/g'

BUILD_STATUS=${PIPESTATUS[0]}
if [ "$BUILD_STATUS" -ne 0 ]; then
  show_first_failure_context
  echo -e "\n❌ \033[1;31mKernel compilation failed (see $OUT_DIR/build.log).\033[0m"
  exit "$BUILD_STATUS"
fi

# =====================[ CHECK IMAGE ]=====================

KERNEL_IMG=$OUT_DIR/arch/arm64/boot/Image.gz-dtb
if [ ! -f "$KERNEL_IMG" ]; then
  echo -e "\n❌ \033[1;31mBuild failed: Image.gz-dtb not found!\033[0m"
  exit 1
fi

echo -e "\n✅ \033[1;32mKernel image compiled successfully.\033[0m"

# =====================[ PACKAGING ]=====================

echo -e "\n📦 \033[1;34mPacking kernel into flashable zip...\033[0m"
cp "$KERNEL_IMG" "$ANYKERNEL_DIR/zImage"

cd $ANYKERNEL_DIR || exit 1
zip -r9 "$ZIPNAME" * -x "*.zip" "*.git*" README.md > /dev/null

if [ $? -eq 0 ]; then
  echo -e "\n🎉 \033[1;32mFlashable zip created: $ANYKERNEL_DIR/$ZIPNAME\033[0m"
else
  echo -e "\n❌ \033[1;31mFailed to create zip.\033[0m"
  exit 1
fi
