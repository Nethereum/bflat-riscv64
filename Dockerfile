# =============================================================================
# Nethereum bflat-riscv64 Docker Image
#
# Builds the complete C# → RISC-V64 toolchain from source:
#   - bflat compiler (from this repo)
#   - All modules compiled with riscv64-gcc (includes TSS + calloc fixes)
#   - Pre-built .NET runtime DLLs (from NethermindEth/dotnet-riscv)
#   - Post-processing tools (patch_elf.py, signal patching)
#
# Build:  docker build -t nethereum/bflat-riscv64 .
# Usage:  docker run --rm -v $(pwd):/src nethereum/bflat-riscv64 [args]
#
# Based on NethermindEth/bflat-riscv64 (AGPL v3)
# Nethermind patches: RISC-V modules, runtime helpers, OS abstraction
# Nethereum patches: TSS reduction (33.8MB→64KB), calloc fix for Zisk
# =============================================================================

FROM ubuntu:24.04

# --- System dependencies ---
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget unzip git ca-certificates \
    gcc-riscv64-linux-gnu g++-riscv64-linux-gnu binutils-riscv64-linux-gnu \
    llvm \
    python3 python3-pip \
    yq \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install lief pyelftools --break-system-packages

# --- .NET SDK (for building the bflat compiler itself) ---
ENV DOTNET_VERSION=10.0.100
RUN wget -q https://builds.dotnet.microsoft.com/dotnet/Sdk/${DOTNET_VERSION}/dotnet-sdk-${DOTNET_VERSION}-linux-x64.tar.gz \
    && mkdir -p /root/dotnet \
    && tar zxf dotnet-sdk-${DOTNET_VERSION}-linux-x64.tar.gz -C /root/dotnet \
    && rm dotnet-sdk-${DOTNET_VERSION}-linux-x64.tar.gz
ENV DOTNET_ROOT=/root/dotnet
ENV PATH="$PATH:/root/dotnet"

# --- Pre-built runtime DLLs from NethermindEth/dotnet-riscv ---
# These are the 228 .NET DLLs patched for RISC-V64 soft-float/no-compressed
# Multi-hour build — we use their release artifacts
ENV DOTNET_RISCV_VERSION=v10.0.0.b15
RUN mkdir -p /tmp/runtime && cd /tmp/runtime \
    && wget -q https://github.com/NethermindEth/dotnet-riscv/releases/download/${DOTNET_RISCV_VERSION}/bflat-libs-linux-musl-riscv64.zip \
    && wget -q https://github.com/NethermindEth/dotnet-riscv/releases/download/${DOTNET_RISCV_VERSION}/bflat-refs.zip \
    && wget -q https://github.com/NethermindEth/dotnet-riscv/releases/download/${DOTNET_RISCV_VERSION}/bflat-compiler-native-linux-glibc-x64.zip \
    && wget -q https://github.com/NethermindEth/dotnet-riscv/releases/download/${DOTNET_RISCV_VERSION}/compiler-linux-glibc-x64.zip \
    && mkdir -p /runtime/libs /runtime/refs /runtime/compiler-native /runtime/compiler \
    && unzip -q bflat-libs-linux-musl-riscv64.zip -d /runtime/libs \
    && unzip -q bflat-refs.zip -d /runtime/refs \
    && unzip -q bflat-compiler-native-linux-glibc-x64.zip -d /runtime/compiler-native \
    && unzip -q compiler-linux-glibc-x64.zip -d /runtime/compiler \
    && rm -rf /tmp/runtime

# --- Copy our bflat source (with Nethereum patches) ---
COPY . /build/bflat

# --- Build bflat compiler ---
WORKDIR /build/bflat
RUN dotnet build src/bflat/bflat.csproj -p:Flavor=riscv64

# --- Build modules with riscv64-gcc ---
RUN bash build.sh modules riscv64

# --- Assemble the toolchain at /share/bflat ---
RUN mkdir -p /share/bflat/bin \
    && mkdir -p /share/bflat/lib/linux/riscv64/musl \
    && mkdir -p /share/bflat/lib/linux/riscv64/zisk \
    && mkdir -p /share/bflat/ref \
    # Compiler
    && cp -r src/bflat/bin/Debug/net10.0/* /share/bflat/ \
    # Runtime DLLs
    && cp /runtime/libs/*.dll /share/bflat/lib/linux/riscv64/musl/ 2>/dev/null || true \
    && cp -r /runtime/libs/linux-riscv64/* /share/bflat/lib/linux/riscv64/musl/ 2>/dev/null || true \
    && cp /runtime/refs/*.dll /share/bflat/ref/ 2>/dev/null || true \
    # Compiler native (JIT + LLD)
    && cp /runtime/compiler-native/* /share/bflat/bin/ 2>/dev/null || true \
    && cp /runtime/compiler/* /share/bflat/bin/ 2>/dev/null || true \
    && chmod +x /share/bflat/bin/* 2>/dev/null || true \
    # Compiled modules
    && cp src/bflat/modules/*/module.o /share/bflat/lib/linux/riscv64/zisk/ 2>/dev/null || true \
    # Linker scripts
    && cp -r src/bflat/modules/zkvm_zisk /share/bflat/lib/linux/riscv64/zisk/ 2>/dev/null || true \
    && cp -r src/bflat/modules/zkvm_zisk_sim /share/bflat/lib/linux/riscv64/zisk/ 2>/dev/null || true \
    # Post-processing tools
    && cp src/bflat/scripts/patch_elf.py /share/bflat/

ENV PATH="$PATH:/share/bflat"

# --- Signal patching script ---
COPY docker/signal_patch.sh /share/bflat/signal_patch.sh
RUN chmod +x /share/bflat/signal_patch.sh

# --- Entrypoint ---
COPY docker/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

WORKDIR /src
ENTRYPOINT ["/entrypoint.sh"]
