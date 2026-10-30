#!/usr/bin/env bash
set -u

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "ERROR: Run inside kernel repository."
    exit 1
}
cd "$ROOT"

GREEN='\033[1;32m'
RED='\033[1;31m'
YELLOW='\033[1;33m'
CYAN='\033[1;36m'
RESET='\033[0m'

# Seven main SUSFS inline-hook targets
FILES=(
  "fs/exec.c"
  "fs/open.c"
  "fs/read_write.c"
  "fs/stat.c"
  "kernel/reboot.c"
  "kernel/sys.c"
  "drivers/input/input.c"
)

# Evidence patterns. A match is not by itself proof of runtime behavior.
INLINE_RE='susfs_inline_hook|inline_hook_susfs|susfs.*inline_hook|inline_hook.*susfs'
MANUAL_RE='CONFIG_KSU_MANUAL_HOOK|ksu_handle_execveat|ksu_handle_vfs_read|ksu_handle_vfs_stat|ksu_handle_sys_reboot|ksu_handle_setuid|ksu_handle_setresuid|ksu_handle_input_event|ksu_handle_faccessat'

check_file() {
    local file="$1"
    local inline manual

    if [[ ! -f "$file" ]]; then
        printf "  %-25s ${RED}✗ MISSING${RESET}             ${RED}✗ MISSING${RESET}\n" "$file"
        return
    fi

    if grep -Eiq "$INLINE_RE" "$file"; then
        inline="${GREEN}✓ MATCH${RESET}"
    else
        inline="${RED}✗ NO MARKER${RESET}"
    fi

    if grep -Eiq "$MANUAL_RE" "$file"; then
        manual="${GREEN}✓ MATCH${RESET}"
    else
        manual="${RED}✗ NO MATCH${RESET}"
    fi

    printf "  %-25s " "$file"
    printf "%b" "$inline"
    printf "              "
    printf "%b\n" "$manual"
}

echo
printf "${CYAN}========== KERNEL HOOK DIAGNOSTIC ==========${RESET}\n"
echo "Repository: $ROOT"
echo "Branch: $(git branch --show-current)"
echo
printf "%-25s %-22s %s\n" "TARGET FILE" "INLINE EVIDENCE" "MANUAL EVIDENCE"
echo "----------------------------------------------------------------"

for file in "${FILES[@]}"; do
    check_file "$file"
done

echo
printf "${CYAN}========== CONFIGURATION ==========${RESET}\n"

CONFIG=""
for candidate in \
    out/.config \
    arch/arm64/configs/atoll_defconfig \
    arch/arm64/configs/atoll-perf_defconfig
do
    if [[ -f "$candidate" ]]; then
        CONFIG="$candidate"
        break
    fi
done

if [[ -n "$CONFIG" ]]; then
    echo "Config file: $CONFIG"
    for symbol in CONFIG_KSU_MANUAL_HOOK CONFIG_KSU_TRACEPOINT_HOOK CONFIG_KSU_SUSFS; do
        value="$(grep -E "^${symbol}=" "$CONFIG" | tail -n 1 || true)"
        if [[ -n "$value" ]]; then
            printf "  ${GREEN}✓${RESET} %s\n" "$value"
        elif grep -q "^# ${symbol} is not set" "$CONFIG"; then
            printf "  ${RED}✗${RESET} %s is not set\n" "$symbol"
        else
            printf "  ${YELLOW}?${RESET} %s absent/unknown\n" "$symbol"
        fi
    done
else
    echo "Config file not found; configuration status is UNKNOWN."
fi

echo
printf "${YELLOW}NOTE:${RESET} MATCH means source evidence only."
echo "It does not prove the hook was newly patched or executes correctly."
echo "Inline hook markers may be implemented differently in this kernel."
echo "Review the patch diff and compile log before concluding."
