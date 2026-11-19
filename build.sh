
#!/bin/bash
set -Eeuo pipefail

# ============================================================
# BUNNYBLADEX PERF - KAZESU BUILD SYSTEM
# Realme 6 Pro (RMX2061) | ARM64 | Linux 4.14
# ============================================================

WORKDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$WORKDIR"

OUT_DIR="$WORKDIR/out"
TOOLCHAINS_DIR="$WORKDIR/toolchains"

NEUTRON_TAG="${NEUTRON_TAG:-06092026}"
NEUTRON_DIR="$TOOLCHAINS_DIR/neutron-clang-${NEUTRON_TAG}"
NEUTRON_URL="https://github.com/Neutron-Toolchains/clang-build-catalogue/releases/download/${NEUTRON_TAG}/neutron-clang-${NEUTRON_TAG}.tar.zst"

CLANG_REPO="https://gitlab.com/crdroidandroid/android_prebuilts_clang_host_linux-x86_clang-r547379.git"
CLANG_DIR="$TOOLCHAINS_DIR/clang-r547379"
BINUTILS_DIR="$TOOLCHAINS_DIR/llvm-binutils-stable"

ANYKERNEL_DIR="$WORKDIR/AnyKernel3"

DEVICE="RMX2061"
DEFCONFIG="${DEFCONFIG:-atoll_defconfig}"
KERNEL_NAME="BunnyBladeX-Perf-KazeSU"
VERSION="v1.0.0"
BUILD_TYPE="${BUILD_TYPE:-Release}"

DATE="$(date +%Y%m%d)"
TIME="$(date +%H%M)"

ZIPNAME="${KERNEL_NAME}-${DEVICE}-${TIME}-${DATE}-${VERSION}.zip"
KERNEL_FULL_NAME="${KERNEL_NAME}-${DEVICE}-${TIME}-${DATE}-${VERSION}"

# ============================================================
# COLORS
# ============================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# ============================================================
# ENVIRONMENT
# ============================================================

export ARCH=arm64
export SUBARCH=arm64

export USE_CCACHE=1
export CCACHE_DIR="${CCACHE_DIR:-$WORKDIR/.ccache}"

mkdir -p "$OUT_DIR" "$TOOLCHAINS_DIR" "$CCACHE_DIR"

ccache -M 15G >/dev/null 2>&1 || true

if [[ -n "${GITHUB_ENV:-}" ]]; then
    echo "KERNEL_FULL_NAME=$KERNEL_FULL_NAME" >> "$GITHUB_ENV"
fi

# ============================================================
# TELEGRAM
# ============================================================

BOT_TOKEN="${TELEGRAM_TOKEN:-}"
CHAT_ID="${TELEGRAM_CHAT_ID:-}"

send_msg() {
    if [[ -n "$BOT_TOKEN" && -n "$CHAT_ID" ]]; then
        curl -fsS -X POST \
            "https://api.telegram.org/bot${BOT_TOKEN}/sendMessage" \
            -d "chat_id=${CHAT_ID}" \
            -d "text=$1" >/dev/null || true
    fi
}

send_file() {
    local file="$1"
    local caption="$2"

    if [[ -n "$BOT_TOKEN" && -n "$CHAT_ID" && -f "$file" ]]; then
        curl -fsS -X POST \
            "https://api.telegram.org/bot${BOT_TOKEN}/sendDocument" \
            -F "chat_id=${CHAT_ID}" \
            -F "document=@${file}" \
            -F "caption=${caption}" >/dev/null || true
    fi
}

# ============================================================
# ERROR HANDLING
# ============================================================

on_error() {
    local status=$?
    echo -e "${RED}BUILD FAILED: exit code $status${NC}"

    if [[ -f "$OUT_DIR/build.log" ]]; then
        echo "========== LAST BUILD ERRORS =========="
        tail -n 100 "$OUT_DIR/build.log"
        send_file "$OUT_DIR/build.log" "KazeSU Build Error"
    fi

    send_msg "KazeSU Build Failed: exit code $status"
    exit "$status"
}

trap on_error ERR

# ============================================================
# BUILD INFORMATION
# ============================================================

echo -e "${CYAN}"
echo "=========================================="
echo "       BUNNYBLADEX PERF KAZESU"
echo "=========================================="
echo -e "${NC}"

echo "Device:       $DEVICE"
echo "Branch:       ${GITHUB_REF_NAME:-Local}"
echo "Defconfig:    $DEFCONFIG"
echo "Kernel:       $KERNEL_NAME"
echo "Version:      $VERSION"
echo "Build Type:   $BUILD_TYPE"
echo "CPU Cores:    $(nproc)"
echo "Date:         $(date)"
echo

# ============================================================
# TOOLCHAIN - NEUTRON CLANG
# ============================================================

NEUTRON_BIN=""

if [[ -x "$NEUTRON_DIR/bin/clang" ]]; then

    NEUTRON_BIN="$NEUTRON_DIR/bin"
    echo -e "${GREEN}Using cached Neutron Clang${NC}"

else

    echo -e "${YELLOW}Downloading Neutron Clang $NEUTRON_TAG${NC}"

    ARCHIVE="$TOOLCHAINS_DIR/neutron-clang-${NEUTRON_TAG}.tar.zst"
    EXTRACT_DIR="$TOOLCHAINS_DIR/neutron-extract-${NEUTRON_TAG}"

    rm -rf "$EXTRACT_DIR"
    mkdir -p "$EXTRACT_DIR"

    if curl -fL --retry 5 --retry-delay 5 \
        --connect-timeout 20 \
        -o "$ARCHIVE" "$NEUTRON_URL"; then

        if tar --zstd -xf "$ARCHIVE" -C "$EXTRACT_DIR"; then

            FOUND_CLANG="$(find "$EXTRACT_DIR" -maxdepth 6 \
                \( -type f -o -type l \) \
                -path '*/bin/clang' -print -quit)"

            if [[ -n "$FOUND_CLANG" ]]; then

                FOUND_ROOT="$(dirname "$(dirname "$FOUND_CLANG")")"

                mkdir -p "$NEUTRON_DIR"

                cp -a "$FOUND_ROOT/." "$NEUTRON_DIR/"

                if [[ -x "$NEUTRON_DIR/bin/clang" ]]; then
                    NEUTRON_BIN="$NEUTRON_DIR/bin"
                fi
            fi
        fi
    fi

    rm -rf "$EXTRACT_DIR"
    rm -f "$ARCHIVE"
fi

# ============================================================
# FALLBACK CLANG
# ============================================================

if [[ -n "$NEUTRON_BIN" && -x "$NEUTRON_BIN/clang" ]]; then

    TOOLCHAIN_BIN="$NEUTRON_BIN"
    echo -e "${GREEN}Selected: Neutron Clang $NEUTRON_TAG${NC}"

else

    echo -e "${YELLOW}Neutron unavailable. Using fallback Clang.${NC}"

    if [[ ! -d "$CLANG_DIR" ]]; then
        git clone --depth=1 "$CLANG_REPO" "$CLANG_DIR"
    fi

    if [[ ! -x "$CLANG_DIR/bin/clang" ]]; then
        echo "ERROR: Fallback Clang missing"
        exit 1
    fi

    if [[ ! -d "$BINUTILS_DIR" ]]; then
        git clone --depth=1 \
            https://android.googlesource.com/toolchain/llvm-binutils-stable \
            "$BINUTILS_DIR"
    fi

    export PATH="$BINUTILS_DIR/bin:$PATH"
    TOOLCHAIN_BIN="$CLANG_DIR/bin"

fi

export PATH="$TOOLCHAIN_BIN:$PATH"

export CC=clang
export LD=ld.lld
export AR=llvm-ar
export NM=llvm-nm
export STRIP=llvm-strip
export OBJCOPY=llvm-objcopy
export OBJDUMP=llvm-objdump

# ============================================================
# COMPILER VALIDATION
# ============================================================

for tool in clang ld.lld llvm-ar llvm-nm llvm-strip llvm-objcopy llvm-objdump gcc g++; do

    if ! command -v "$tool" >/dev/null 2>&1; then
        echo -e "${RED}Missing required tool: $tool${NC}"
        exit 1
    fi

done

echo
echo "========== COMPILER INFORMATION =========="

clang --version | sed -n '1p'
ld.lld --version | sed -n '1p'

if command -v aarch64-linux-gnu-gcc >/dev/null 2>&1; then
    aarch64-linux-gnu-gcc --version | sed -n '1p'
else
    echo "Cross GCC: Not installed (LLVM target tools selected)"
fi

# ============================================================
# ANYKERNEL3
# ============================================================

if [[ ! -d "$ANYKERNEL_DIR" ]]; then

    git clone --depth=1 --branch master \
        https://github.com/JOD-BUNNY07/AnyKernel3.git \
        "$ANYKERNEL_DIR"

fi

# ============================================================
# BUILD START
# ============================================================

START="$(date +%s)"

send_msg "KazeSU Build Started
Device: $DEVICE
Defconfig: $DEFCONFIG
Compiler: $(clang --version | sed -n '1p')"

echo
echo -e "${CYAN}========== KAZESU BUILD START ==========${NC}"

# ============================================================
# CLEAN STALE OUTPUT
# ============================================================

rm -f "$ANYKERNEL_DIR/zImage"
rm -f "$ANYKERNEL_DIR"/*.zip

rm -f "$OUT_DIR/arch/arm64/boot/Image"
rm -f "$OUT_DIR/arch/arm64/boot/Image.gz"
rm -f "$OUT_DIR/arch/arm64/boot/Image.gz-dtb"

# Force KazeSU composite object to relink.
rm -f "$OUT_DIR/drivers/kernelsu/kernelsu.o"

# ============================================================
# KAZESU CONFIGURATION
# ============================================================

echo
echo "========== GENERATING KAZESU CONFIG =========="

CONFIG="$OUT_DIR/.config"
CONFIG_TOOL="$WORKDIR/scripts/config"

# Generate the selected device defconfig first.
if ! make O="$OUT_DIR" ARCH=arm64 "$DEFCONFIG" \
    >"$OUT_DIR/config.log" 2>&1; then
    cat "$OUT_DIR/config.log"
    echo "ERROR: Defconfig generation failed"
    exit 1
fi

# scripts/config is part of the Linux kernel source tree.
if [[ ! -f "$CONFIG_TOOL" ]]; then
    echo "ERROR: $CONFIG_TOOL is missing"
    echo "Cannot safely enable KazeSU configuration."
    exit 1
fi

# KPROBES depends on MODULES and HAVE_KPROBES.
# KSU depends on KPROBES and EXT4_FS.
bash "$CONFIG_TOOL" --file "$CONFIG" \
    --enable MODULES \
    --enable KPROBES \
    --enable EXT4_FS \
    --enable KSU

# Resolve all Kconfig dependencies. HAVE_KPROBES is an architecture
# capability and must be selected by the arm64 Kconfig definitions.
# KAZESU_SUSFS_CONFIG_PATCH_35045_V3
echo ""
echo "========== KAZESU + SUSFS CONFIGURATION =========="

CONFIG_TOOL="${CONFIG_TOOL:-$WORKDIR/scripts/config}"
if [ ! -f "$CONFIG_TOOL" ]; then
    echo "ERROR: scripts/config not found: $CONFIG_TOOL"
    exit 1
fi
chmod +x "$CONFIG_TOOL"

# Request the core KSU/SUSFS options before olddefconfig resolves dependencies.
for config in MODULES HAVE_KPROBES KPROBES EXT4_FS KSU KSU_SUSFS \
    KSU_SUSFS_SUS_PATH KSU_SUSFS_SUS_MOUNT KSU_SUSFS_SUS_KSTAT \
    KSU_SUSFS_SPOOF_UNAME KSU_SUSFS_ENABLE_LOG \
    KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS \
    KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG \
    KSU_SUSFS_OPEN_REDIRECT KSU_SUSFS_SUS_MAP \
    KSU_SUSFS_PRIORITY_UID_FILTER; do
    "$CONFIG_TOOL" --file "$OUT_DIR/.config" --enable "$config"
done
echo "KazeSU/SUSFS options requested."
if ! make O="$OUT_DIR" ARCH=arm64 olddefconfig \
    >>"$OUT_DIR/config.log" 2>&1; then
    cat "$OUT_DIR/config.log"
    echo "ERROR: olddefconfig failed"
    exit 1
fi
# KAZESU_SUSFS_CONFIG_VALIDATION_35045_V3
echo ""
echo "========== FINAL KAZESU + SUSFS CONFIG =========="
grep -E '^(CONFIG_(MODULES|HAVE_KPROBES|KPROBES|EXT4_FS|KSU|KSU_SUSFS|KSU_SUSFS_SUS_PATH|KSU_SUSFS_SUS_MOUNT|KSU_SUSFS_SUS_KSTAT|KSU_SUSFS_SPOOF_UNAME|KSU_SUSFS_ENABLE_LOG|KSU_SUSFS_HIDE_KSU_SUSFS_SYMBOLS|KSU_SUSFS_SPOOF_CMDLINE_OR_BOOTCONFIG|KSU_SUSFS_OPEN_REDIRECT|KSU_SUSFS_SUS_MAP|KSU_SUSFS_PRIORITY_UID_FILTER))=' \
    "$OUT_DIR/.config" || true

for config in MODULES HAVE_KPROBES KPROBES EXT4_FS KSU KSU_SUSFS; do
    if ! grep -qx "CONFIG_${config}=y" "$OUT_DIR/.config"; then
        echo "ERROR: CONFIG_${config}=y is missing after olddefconfig."
        echo "The corresponding Kconfig dependency is not satisfied."
        exit 1
    fi
done
echo "SUCCESS: mandatory KazeSU + SUSFS config is enabled."
echo "================================================="

echo
echo "========== FINAL KAZESU CONFIG =========="

grep -E '^(CONFIG_(MODULES|HAVE_KPROBES|KPROBES|EXT4_FS|KSU)=|# CONFIG_(MODULES|HAVE_KPROBES|KPROBES|EXT4_FS|KSU) is not set)' \
    "$CONFIG" || true

# Validate the final, dependency-resolved configuration.
for config in CONFIG_MODULES CONFIG_HAVE_KPROBES CONFIG_KPROBES CONFIG_EXT4_FS CONFIG_KSU; do
    if ! grep -qx "${config}=y" "$CONFIG"; then
        echo
        echo "ERROR: ${config}=y is required but is not enabled."
        echo "Check the Kconfig dependency and $OUT_DIR/config.log."
        exit 1
    fi
    echo "[OK] ${config}=y"
done

echo "SUCCESS: KazeSU config and dependencies are enabled."
echo "================================================"

# ============================================================
# BUILD
# ============================================================

echo
echo -e "${CYAN}========== COMPILING KERNEL ==========${NC}"

JOBS="$(nproc)"

if [[ "$JOBS" -lt 2 ]]; then
    JOBS=2
fi

if ! make -j"$JOBS" \
    O="$OUT_DIR" \
    ARCH=arm64 \
    CC=clang \
    HOSTCC=gcc \
    HOSTCXX=g++ \
    LD=ld.lld \
    AR=llvm-ar \
    NM=llvm-nm \
    OBJCOPY=llvm-objcopy \
    OBJDUMP=llvm-objdump \
    STRIP=llvm-strip \
    LLVM=1 \
    LLVM_IAS=1 \
    CLANG_TRIPLE=aarch64-linux-gnu- \
    CROSS_COMPILE=aarch64-linux-gnu- \
    2>&1 | tee "$OUT_DIR/build.log"; then

    echo -e "${RED}Kernel compilation failed${NC}"
    exit 1

fi

# ============================================================
# KAZESU OBJECT VALIDATION
# ============================================================

echo
echo "========== KAZESU OBJECT VALIDATION =========="

KSU_OBJECT="$OUT_DIR/drivers/kernelsu/kernelsu.o"

if [[ ! -s "$KSU_OBJECT" ]]; then

    echo -e "${RED}ERROR: KazeSU kernelsu.o missing!${NC}"

    find "$OUT_DIR/drivers/kernelsu" -maxdepth 2 \
        -type f -name '*.o' 2>/dev/null || true

    exit 1

fi

echo -e "${GREEN}[OK] KazeSU kernelsu.o generated${NC}"
ls -lh "$KSU_OBJECT"

# ============================================================
# FINAL KERNEL VALIDATION
# ============================================================

echo
echo "========== FINAL KERNEL VALIDATION =========="

VMLINUX="$OUT_DIR/vmlinux"
IMG="$OUT_DIR/arch/arm64/boot/Image.gz-dtb"

if [[ ! -s "$VMLINUX" ]]; then
    echo -e "${RED}ERROR: vmlinux missing${NC}"
    exit 1
fi

echo -e "${GREEN}[OK] vmlinux generated${NC}"
ls -lh "$VMLINUX"

if [[ ! -s "$IMG" ]]; then
    echo -e "${RED}ERROR: Image.gz-dtb missing${NC}"
    exit 1
fi

echo -e "${GREEN}[OK] Image.gz-dtb generated${NC}"
ls -lh "$IMG"

# ============================================================
# FINAL CONFIG CHECK
# ============================================================

required_configs=(
    CONFIG_AS_IS_LLVM
    CONFIG_CC_IS_CLANG
    CONFIG_CFI_CLANG
    CONFIG_HIDRAW
    CONFIG_HID_PLAYSTATION
    CONFIG_KFENCE
    CONFIG_LD_IS_LLD
    CONFIG_NET_ACT_BPF
    CONFIG_NET_ACT_POLICE
    CONFIG_NET_CLS_MATCHALL
    CONFIG_NET_SCH_TBF
    CONFIG_PLAYSTATION_FF
    CONFIG_RD_LZ4
    CONFIG_SHADOW_CALL_STACK
    CONFIG_SECURITY_NETWORK
    CONFIG_SECURITY_SELINUX
    CONFIG_CGROUPS
    CONFIG_CGROUP_SCHED
    CONFIG_FAIR_GROUP_SCHED
)

echo
echo "========== FCM CONFIG VALIDATION =========="

for config in "${required_configs[@]}"; do

    if ! grep -qx "${config}=y" "$CONFIG"; then

        echo -e "${RED}Missing required config: ${config}${NC}"
        exit 1

    fi

    echo "[OK] $config"

done

# ============================================================
# PACKAGING
# ============================================================

echo
echo -e "${CYAN}========== PACKAGING ==========${NC}"

cp "$IMG" "$ANYKERNEL_DIR/zImage"

cd "$ANYKERNEL_DIR"

zip -r9q "$ZIPNAME" * \
    -x ".git*" \
    -x "README.md" \
    -x "*.zip"

ZIP_PATH="$ANYKERNEL_DIR/$ZIPNAME"

if [[ ! -s "$ZIP_PATH" ]]; then
    echo "ERROR: Kernel ZIP missing"
    exit 1
fi

ZIP_SIZE="$(du -h "$ZIP_PATH" | cut -f1)"

echo -e "${GREEN}ZIP generated: $ZIPNAME${NC}"
echo "Size: $ZIP_SIZE"

# ============================================================
# BUILD COMPLETE
# ============================================================

END="$(date +%s)"
DIFF=$((END - START))

MINS=$((DIFF / 60))
SECS=$((DIFF % 60))

echo
echo -e "${GREEN}=========================================="
echo "          KAZESU BUILD SUCCESS"
echo "==========================================${NC}"

echo "Kernel: $KERNEL_NAME"
echo "Device: $DEVICE"
echo "Version: $VERSION"
echo "ZIP: $ZIPNAME"
echo "Size: $ZIP_SIZE"
echo "Time: ${MINS}m ${SECS}s"

# ============================================================
# TELEGRAM SUCCESS
# ============================================================

send_file "$ZIP_PATH" \
"Build Success

Kernel: $KERNEL_NAME
Device: $DEVICE
Version: $VERSION
ZIP: $ZIPNAME
Size: $ZIP_SIZE
Time: ${MINS}m ${SECS}s"

# ============================================================
# GITHUB ARTIFACT OUTPUT
# ============================================================

mv "$ZIP_PATH" "$OUT_DIR/"

echo
echo -e "${GREEN}Artifact ready:${NC}"
echo "$OUT_DIR/$ZIPNAME"

echo
echo "========== FINAL KAZESU STATUS =========="
echo "CONFIG_KSU: $(grep '^CONFIG_KSU=' "$CONFIG")"
echo "KSU_OBJECT: PRESENT"
echo "VMLINUX: PRESENT"
echo "IMAGE: PRESENT"
echo "ZIP: PRESENT"
echo
echo -e "${GREEN}BUILD COMPLETED SUCCESSFULLY${NC}"
