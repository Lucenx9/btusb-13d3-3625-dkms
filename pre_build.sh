#!/bin/bash
# pre_build.sh — Fetch kernel btusb sources, patch, and prepare for build.
# Called by DKMS via PRE_BUILD from the build directory (PWD).
# Available env: $kernelver
set -euo pipefail

: "${kernelver:?ERROR: kernelver is not set}"

# ── Paths ──────────────────────────────────────────────────────────────
KERNEL_BT_SRC="/usr/lib/modules/${kernelver}/build/drivers/bluetooth"
BUILD_DIR="$(pwd)"
BUILD_BT_DIR="${BUILD_DIR}/drivers/bluetooth"
PATCH_FILE="${BUILD_DIR}/patches/0001-btusb-add-13d3-3625.patch"
DEVICE_RE='0x13[dD]3,\s*0x3625'

# Extract upstream version (e.g. "6.18.9" from "6.18.9-2-cachyos")
KVER_BASE="$(echo "${kernelver}" | grep -oP '^\d+\.\d+(\.\d+)?')"
[ -n "${KVER_BASE}" ] || { echo "ERROR: Could not parse base version from: ${kernelver}" >&2; exit 1; }
KORG_URL="https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/plain/drivers/bluetooth"
KORG_TAG="v${KVER_BASE}"

[ -f "${PATCH_FILE}" ] || { echo "ERROR: Patch not found: ${PATCH_FILE}" >&2; exit 1; }

mkdir -p "${BUILD_BT_DIR}"

# ── 1. Get btusb sources ──────────────────────────────────────────────
if [ -f "${KERNEL_BT_SRC}/btusb.c" ]; then
    # Prefer local kernel tree when full sources are available
    echo "Copying btusb sources from local kernel tree ..."
    cp -a "${KERNEL_BT_SRC}"/*.c "${BUILD_BT_DIR}/" 2>/dev/null || true
    cp -a "${KERNEL_BT_SRC}"/*.h "${BUILD_BT_DIR}/" 2>/dev/null || true
else
    # Download from kernel.org stable tree
    echo "Local btusb.c not found — downloading from kernel.org (${KORG_TAG}) ..."

    # Fetch btusb.c first
    if ! curl -sSfL "${KORG_URL}/btusb.c?h=${KORG_TAG}" -o "${BUILD_BT_DIR}/btusb.c"; then
        echo "ERROR: Failed to download btusb.c for tag ${KORG_TAG}." >&2
        exit 1
    fi

    # Parse local #include "..." headers and fetch them
    grep -oP '#include\s+"\K[^"]+' "${BUILD_BT_DIR}/btusb.c" | while read -r hdr; do
        echo "  Fetching ${hdr} ..."
        curl -sSfL "${KORG_URL}/${hdr}?h=${KORG_TAG}" -o "${BUILD_BT_DIR}/${hdr}" || \
            echo "  WARNING: ${hdr} not found (may be OK if provided by kernel headers)"
    done || true

    echo "Download complete."
fi

# Out-of-tree module Makefile
echo 'obj-m := btusb.o' > "${BUILD_BT_DIR}/Makefile"

# ── 2. Skip if device ID is already upstream ──────────────────────────
if grep -qP "${DEVICE_RE}" "${BUILD_BT_DIR}/btusb.c"; then
    echo "INFO: Device 13d3:3625 already present in btusb.c — patch skipped."
    exit 0
fi

# ── 3. Insert device ID ───────────────────────────────────────────────
echo "Patching btusb.c to add device 13d3:3625 ..."

# Try patch with --fuzz=0 first (strict context match, no misplacement)
if patch -d "${BUILD_DIR}" -p1 --forward --batch --fuzz=0 \
        < "${PATCH_FILE}" 2>/dev/null; then
    echo "Patch applied successfully."
else
    # Fallback: insert after the exact "MT7922 Bluetooth devices" comment
    # (anchored to avoid matching "MT7922A Bluetooth devices")
    echo "Patch context mismatch — using perl insertion ..."
    perl -i -pe '
        if (m{/\* MediaTek MT7922 Bluetooth devices \*/}) {
            $_ .= "\t{ USB_DEVICE(0x13d3, 0x3625), .driver_info = BTUSB_MEDIATEK |\n"
                 . "\t\t\t\t\t\t     BTUSB_WIDEBAND_SPEECH },\n";
        }
    ' "${BUILD_BT_DIR}/btusb.c"
fi

# ── 4. Verify ─────────────────────────────────────────────────────────
if ! grep -qP "${DEVICE_RE}" "${BUILD_BT_DIR}/btusb.c"; then
    echo "ERROR: Failed to add device 13d3:3625 to btusb.c." >&2
    exit 1
fi
echo "Verification passed: device 13d3:3625 present in btusb.c."
