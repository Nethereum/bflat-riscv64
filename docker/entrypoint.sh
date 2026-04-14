#!/bin/bash
# =============================================================================
# Nethereum bflat-riscv64 Entrypoint
# Generic C# → RISC-V64 compiler with post-processing tools
#
# Usage:
#   docker run --rm -v $(pwd):/src nethereum/bflat-riscv64 bflat build [args...]
#   docker run --rm -v $(pwd):/src nethereum/bflat-riscv64 patch_elf [args...]
#   docker run --rm -v $(pwd):/src nethereum/bflat-riscv64 signal_patch <elf>
#   docker run --rm -v $(pwd):/src nethereum/bflat-riscv64 bash /src/scripts/my_build.sh
# =============================================================================

case "$1" in
    bflat)
        shift
        exec bflat "$@"
        ;;
    patch_elf)
        shift
        exec python3 /share/bflat/patch_elf.py "$@"
        ;;
    signal_patch)
        shift
        exec bash /share/bflat/signal_patch.sh "$@"
        ;;
    *)
        # Pass through — run whatever command was given
        exec "$@"
        ;;
esac
