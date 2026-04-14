# Nethereum bflat-riscv64

Fork of [NethermindEth/bflat-riscv64](https://github.com/NethermindEth/bflat-riscv64) which is itself a fork of [MichalStrehovsky/bflat](https://github.com/bflattened/bflat) — a C# NativeAOT compiler.

## What this is

A complete toolchain for compiling C# to fully static RISC-V64 binaries that run inside zero-knowledge virtual machines (zkVMs). Used by [Nethereum](https://github.com/Nethereum/Nethereum) to execute the Ethereum Virtual Machine inside [Zisk](https://github.com/0xPolygonHermez/zisk) and generate ZK proofs of EVM execution.

## What's in this fork

### From MichalStrehovsky (original bflat)
The C# NativeAOT compiler — Roslyn + ILC + LLD bundled into a single tool.

### From Nethermind
RISC-V64 support for zkVMs (304 commits):
- **13 modules** — replace the operating system for bare-metal execution (memory allocator, thread-local storage, bootstrap, GC, signal stubs, FP stubs)
- **Patched .NET runtime** — 18 patches to the .NET 10 runtime for soft-float, no compressed instructions, no jump tables ([dotnet-riscv](https://github.com/NethermindEth/dotnet-riscv))
- **patch_elf.py** — ELF post-processor (removes EH frames, splits code from data)
- **Module build system** — compiles C/C++/ASM modules with riscv64-gcc
- **Zisk linker scripts** — memory layout for Zisk's architecture

### From Nethereum (this fork)
Fixes discovered while running the Nethereum EVM on Zisk:

| Fix | What | Why |
|-----|------|-----|
| **TSS reduction** | `TSS_MAX_TYPEMANAGERS` 1024→32, `TSS_MAX_SLOTS` 4096→256 in `modules/rhp/module.c` | Original values create 33.8MB BSS that exceeds Zisk's 4M instruction ROM limit. 32×256 is sufficient for single-threaded zkVM execution. |
| **calloc fix** | `calloc(1, total)` → `malloc(total) + memset` in `modules/rhp/module.c` | musl's `calloc` calls internal `malloc` via `mmap`/`brk` syscalls unavailable in Zisk. Using `malloc` resolves through `pal.o`'s existing `__wrap` symbol. |
| **PIE fix** | Explicit `--no-pie` passed to lld linker in `BuildCommand.cs` | Previously only omitted `-pie` flag; lld defaults to PIE. Explicit `--no-pie` forces EXEC output required by Zisk. |
| **Signal patching** | `docker/signal_patch.sh` patches `__block_app_sigs`, `__restore_sigs`, `__block_all_sigs` to `ret` | musl signal functions use raw `ecall` (syscall 135) which loops infinitely in Zisk. |

These fixes are needed by **any** .NET program targeting Zisk, not just Nethereum. We encourage Nethermind to adopt them upstream.

## Docker image

Build the complete toolchain as a Docker image:

```bash
docker build -t nethereum/bflat-riscv64 .
```

The image contains:
- bflat compiler (built from this repo)
- All modules compiled with riscv64-gcc (with our fixes)
- Pre-built .NET runtime DLLs from [dotnet-riscv](https://github.com/NethermindEth/dotnet-riscv) v10.0.0.b17
- patch_elf.py + signal patching script
- Python3 + lief + riscv64 toolchain

### Usage

The image exposes three commands:

```bash
# Compile C# to RISC-V64
docker run --rm -v $(pwd):/src nethereum/bflat-riscv64 bflat build <files.cs> \
    --os linux --arch riscv64 --libc zisk \
    --no-globalization --no-pthread -Os --no-pie \
    -o /src/output_raw

# Post-process ELF for Zisk
docker run --rm -v $(pwd):/src nethereum/bflat-riscv64 \
    patch_elf /src/output_raw /src/output_elf \
    --fix-init-array --fix-tdata --remove-eh --split-code-data

# Patch signal functions
docker run --rm -v $(pwd):/src nethereum/bflat-riscv64 \
    signal_patch /src/output_elf
```

## Dependencies

| Dependency | Source | Why |
|-----------|--------|-----|
| .NET 10 runtime DLLs | [NethermindEth/dotnet-riscv](https://github.com/NethermindEth/dotnet-riscv) releases | 228 DLLs patched for RISC-V soft-float. Multi-hour build — we use pre-built releases. Will shrink as Microsoft upstreams riscv64 support. |
| libziskos | [NethermindEth/bflat-libziskos](https://github.com/NethermindEth/bflat-libziskos) | Zisk hardware precompile bindings (keccak, secp256k1, BN254, BLS12-381). Linked via `--extlib`. |
| uGC | [NethermindEth/uGC](https://github.com/NethermindEth/uGC) v1.0.4 | Zero-GC bump allocator for zkVM. Downloaded during module build. |

## License

GNU Affero GPL v3 (same as original bflat).

## Contributing

Contributions welcome. If you find issues running .NET on Zisk, please open an issue or PR. We aim to contribute fixes upstream to both [bflattened/bflat](https://github.com/bflattened/bflat) and [NethermindEth/bflat-riscv64](https://github.com/NethermindEth/bflat-riscv64).
