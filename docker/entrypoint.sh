#!/bin/bash
# =============================================================================
# Nethereum bflat-riscv64 Entrypoint
# Compiles C# source to a Zisk-ready RISC-V64 ELF binary
#
# Usage: docker run --rm -v $(pwd):/src nethereum/bflat-riscv64 [bflat args...]
#
# If no args: builds Nethereum.EVM.Zisk from /src using default settings
# If args: passes them directly to bflat (expert mode)
# =============================================================================
set -e

if [ $# -gt 0 ]; then
    # Expert mode: pass args directly to bflat
    exec bflat "$@"
fi

# Default mode: build Nethereum EVM for Zisk
echo "============================================="
echo "  Nethereum EVM → Zisk Build"
echo "============================================="

OUTPUT_NAME="${OUTPUT_NAME:-nethereum_evm}"
OUTPUT_DIR="/src/scripts/zisk-output"
mkdir -p "$OUTPUT_DIR"

# Check if libziskos manifest exists
EXTLIB_FLAG=""
if [ -f /src/scripts/libziskos/libziskos.bflat.manifest ]; then
    EXTLIB_FLAG="--extlib /src/scripts/libziskos/libziskos.bflat.manifest"
fi

# Collect source files (mirrors Nethereum.EVM.Zisk.csproj)
SRC=""

# Zisk.Core
for f in $(find /src/src/Nethereum.Zisk.Core -name "*.cs" -not -path "*/obj/*" -not -path "*/bin/*" 2>/dev/null); do SRC="$SRC $f"; done

# EVM-Zisk bridge
for f in /src/src/Nethereum.EVM.Zisk/Zisk/*.cs; do [ -f "$f" ] && SRC="$SRC $f"; done
for f in $(find /src/src/Nethereum.EVM.Zisk/Zisk/Backends -name "*.cs" 2>/dev/null); do SRC="$SRC $f"; done

# Util (minimal)
for util in EvmUInt256 EvmInt256 AddressUtil AddressExtensions ContractUtils Sha3Keccack ByteUtil EvmUInt256RLPExtensions; do
    [ -f "/src/src/Nethereum.Util/${util}.cs" ] && SRC="$SRC /src/src/Nethereum.Util/${util}.cs"
done
[ -f /src/src/Nethereum.Util/Keccak/KeccakDigest.cs ] && SRC="$SRC /src/src/Nethereum.Util/Keccak/KeccakDigest.cs"
[ -f /src/src/Nethereum.Util/HashProviders/IHashProvider.cs ] && SRC="$SRC /src/src/Nethereum.Util/HashProviders/IHashProvider.cs"
[ -f /src/src/Nethereum.Util/HashProviders/Sha3KeccackHashProvider.cs ] && SRC="$SRC /src/src/Nethereum.Util/HashProviders/Sha3KeccackHashProvider.cs"

# Hex
SRC="$SRC /src/src/Nethereum.Hex/HexConvertors/Extensions/HexByteConvertorExtensions.cs"

# EVM.Core (all)
for f in $(find /src/src/Nethereum.EVM.Core -name "*.cs" -not -path "*/obj/*" -not -path "*/bin/*"); do SRC="$SRC $f"; done

# Merkle Patricia (no proof verification)
for f in $(find /src/src/Nethereum.Merkle.Patricia -name "*.cs" -not -path "*/obj/*" -not -path "*/bin/*" -not -name "*ProofVerification*.cs" 2>/dev/null); do SRC="$SRC $f"; done

# CoreChain
for cc in PatriciaStateRootCalculator PatriciaMerkleTreeBuilder PatriciaBlockRootCalculator; do
    [ -f "/src/src/Nethereum.CoreChain/${cc}.cs" ] && SRC="$SRC /src/src/Nethereum.CoreChain/${cc}.cs"
done

# Model types
for model in \
    AccessListItem IBlockEncodingProvider RlpBlockEncodingProvider \
    Authorisation7702Signed Signature ISignature DefaultValues \
    Account AccountEncoder Receipt ReceiptEncoder Log LogEncoder LogBloomFilter \
    BlockHeader BlockHeaderEncoder \
    TransactionFactory TransactionType TransactionTypeEncoder \
    ISignedTransaction ITransactionTypeDecoder \
    SignedTransaction SignedTypeTransaction SignedLegacyTransaction \
    SignedTransactionBase SignedTransactionExtensions SignatureExtensions \
    VRecoveryAndChainCalculations \
    LegacyTransaction LegacyTransactionChainId \
    Transaction1559 Transaction1559Encoder \
    Transaction2930 Transaction2930Encoder \
    Transaction7702 Transaction7702Encoder \
    RLPSignedDataHashBuilder RLPSignedDataDecoder SignedData \
    AccessListRLPEncoderDecoder AuthorisationListRLPEncoderDecoder \
    Authorisation7702RLPEncoderAndHasher RLPSignedDataEncoder
do
    [ -f "/src/src/Nethereum.Model/${model}.cs" ] && SRC="$SRC /src/src/Nethereum.Model/${model}.cs"
done

# RLP (all)
for f in $(find /src/src/Nethereum.RLP -name "*.cs" -not -path "*/obj/*" -not -path "*/bin/*" -not -path "*/Properties/*" 2>/dev/null); do SRC="$SRC $f"; done

FILECOUNT=$(echo $SRC | wc -w)
echo "[BUILD] Compiling $FILECOUNT source files..."

bflat build $SRC \
    --os linux --arch riscv64 --libc zisk \
    --no-globalization --no-pthread --no-stacktrace-data \
    --no-exception-messages \
    -Os --no-pie \
    -d EVM_SYNC \
    $EXTLIB_FLAG \
    -o "${OUTPUT_DIR}/${OUTPUT_NAME}_raw"

echo "[BUILD] Compilation complete"

# Post-process
echo "[PATCH] Running patch_elf.py..."
python3 /share/bflat/patch_elf.py \
    "${OUTPUT_DIR}/${OUTPUT_NAME}_raw" \
    "${OUTPUT_DIR}/${OUTPUT_NAME}_elf" \
    --fix-init-array --fix-tdata --remove-eh --split-code-data

echo "[PATCH] Patching signal functions..."
bash /share/bflat/signal_patch.sh "${OUTPUT_DIR}/${OUTPUT_NAME}_elf"

echo ""
file "${OUTPUT_DIR}/${OUTPUT_NAME}_elf"
ls -lh "${OUTPUT_DIR}/${OUTPUT_NAME}_elf"
echo ""
echo "============================================="
echo "  BUILD COMPLETE: scripts/zisk-output/${OUTPUT_NAME}_elf"
echo "============================================="
