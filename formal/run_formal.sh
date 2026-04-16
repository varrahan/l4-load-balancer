#!/usr/bin/env bash
# =============================================================================
# formal/run_formal.sh
# Run all SymbiYosys formal verification targets
# =============================================================================
# Usage:
#   bash formal/run_formal.sh              # run all targets
#   bash formal/run_formal.sh sync_fifo    # run one target by name
#
# Exit code: 0 if all targets pass, 1 if any fail.
# =============================================================================

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FORMAL_DIR="${REPO_ROOT}/formal"

TARGETS=(
    sync_fifo
    meta_fifo
    tuple_extractor
    toeplitz_core
    header_modifier
    fib_bram_controller
    token_bucket_limiter
)

# If an argument is given, run only that target
if [[ $# -ge 1 ]]; then
    TARGETS=("$1")
fi

PASS=()
FAIL=()

for target in "${TARGETS[@]}"; do
    sby_file="${FORMAL_DIR}/${target}/${target}.sby"

    if [[ ! -f "${sby_file}" ]]; then
        echo "[SKIP] ${target}: ${sby_file} not found"
        continue
    fi

    echo ""
    echo "========================================================"
    echo "  Running: ${target}"
    echo "========================================================"

    # sby must be invoked from repo root so relative paths in [files] resolve
    if sby -f "${sby_file}" --workdir "${FORMAL_DIR}/${target}/work"; then
        PASS+=("${target}")
        echo "[PASS] ${target}"
    else
        FAIL+=("${target}")
        echo "[FAIL] ${target}  (see ${FORMAL_DIR}/${target}/work/)"
    fi
done

echo ""
echo "========================================================"
echo "  Formal Verification Summary"
echo "========================================================"
echo "  PASS (${#PASS[@]}): ${PASS[*]:-none}"
echo "  FAIL (${#FAIL[@]}): ${FAIL[*]:-none}"
echo "========================================================"

if [[ ${#FAIL[@]} -gt 0 ]]; then
    exit 1
fi
exit 0
