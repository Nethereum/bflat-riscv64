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
# Nethereum patches: TSS reduction (33.8MB→64KB), calloc fix for Zisk (now upstreamed)
# =============================================================================

FROM ubuntu:24.04

# --- System dependencies ---
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget unzip git ca-certificates curl \
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
# Downloaded automatically by bflat's build system (bflat.csproj)
# Version pinned in the csproj — currently v10.0.0.b19

# --- Copy our bflat source (with Nethereum patches) ---
COPY . /build/bflat

# --- Fix line endings (Windows git may convert to CRLF) ---
WORKDIR /build/bflat
RUN find . -name "*.sh" -o -name "*.py" -o -name "*.c" -o -name "*.cpp" -o -name "*.S" -o -name "*.ld" | xargs sed -i 's/\r$//'

# --- Build modules first (bflat build copies module.o files) ---
RUN bash build.sh modules riscv64

# --- Build bflat compiler ---
RUN dotnet build src/bflat/bflat.csproj -p:Flavor=riscv64

# --- Assemble the toolchain at /share/bflat ---
# bflat's build system puts everything in bin/Debug/net10.0 including
# downloaded runtime DLLs, compiled modules, and linker scripts
RUN mkdir -p /share \
    && cp -r src/bflat/bin/Debug/net10.0 /share/bflat \
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
