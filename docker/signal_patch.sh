#!/bin/bash
# Patch musl signal functions to 'ret' for Zisk compatibility
# These functions use raw ecall (syscall 135 = rt_sigprocmask) which
# loops infinitely in Zisk. Patching to ret (0x00008067) is safe
# because signal handling doesn't exist in a zkVM.
ELF="$1"
if [ -z "$ELF" ]; then echo "Usage: $0 <elf>"; exit 1; fi

for sym in __block_app_sigs __restore_sigs __block_all_sigs; do
    ADDR=$(riscv64-linux-gnu-nm "$ELF" 2>/dev/null | grep -E " [tT] ${sym}$" | awk '{print $1}' | head -1)
    if [ -n "$ADDR" ]; then
        FILE_OFF=$(($((16#$ADDR)) - 0x80000000 + 0x1000))
        printf '\x67\x80\x00\x00' | dd of="$ELF" bs=1 seek=$FILE_OFF conv=notrunc 2>/dev/null
        echo "[PATCH] Signal: $sym at 0x$ADDR → ret"
    fi
done
