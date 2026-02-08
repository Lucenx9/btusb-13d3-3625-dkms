# btusb-13d3-3625-dkms

DKMS module that adds USB device `13d3:3625` (IMC Networks / MediaTek MT7922) to the Linux `btusb` driver with the correct `BTUSB_MEDIATEK | BTUSB_WIDEBAND_SPEECH` flags.

## Why

The device `13d3:3625` is not yet in the upstream kernel's `btusb` device table. Without a matching entry, the driver won't use the MediaTek-specific initialization path and the Bluetooth adapter won't work.

This module patches `btusb.c` at build time instead of bundling a full copy, so it stays compatible across kernel updates.

## How it works

1. `pre_build.sh` fetches `btusb.c` and its local headers from the local kernel tree or, if unavailable (e.g. Arch/CachyOS), downloads them from kernel.org for the target kernel version.
2. If `13d3:3625` is already present in the source (merged upstream), the patch is **skipped automatically**.
3. Otherwise, it applies a unified patch (`--fuzz=0`). If the context doesn't match the kernel version, a perl fallback inserts the entry after the `/* MediaTek MT7922 Bluetooth devices */` comment.
4. The patched `btusb.ko` is compiled out-of-tree and installed to `/updates/dkms/`, which takes priority over the in-tree module.

## Install

```bash
# Copy source to /usr/src
sudo cp -r btusb-13d3-3625-1.0 /usr/src/

# Register and install
sudo dkms add btusb-13d3-3625/1.0
sudo dkms install btusb-13d3-3625/1.0

# Reload the module
sudo modprobe -r btusb && sudo modprobe btusb
```

## Verify

```bash
# DKMS status
dkms status | grep btusb

# Confirm the DKMS module is loaded (not the in-tree one)
modinfo btusb | grep filename
# Expected: /lib/modules/.../updates/dkms/btusb.ko.zst
```

## Uninstall

```bash
sudo dkms remove btusb-13d3-3625/1.0 --all
sudo rm -rf /usr/src/btusb-13d3-3625-1.0
```

## Files

| File | Purpose |
|------|---------|
| `dkms.conf` | DKMS configuration |
| `pre_build.sh` | Fetches sources, applies patch, handles fallback |
| `patches/0001-btusb-add-13d3-3625.patch` | Unified diff adding the device entry |

## Notes

- Tested on CachyOS (Arch-based) with kernel 6.18.x.
- On Arch, kernel headers don't include driver `.c` files, so `pre_build.sh` downloads them from kernel.org. An internet connection is required during the first build for each kernel version.
- `AUTOINSTALL="yes"` ensures automatic rebuild on kernel upgrades via the DKMS pacman hook.
- Once `13d3:3625` lands upstream, the module will detect it and skip patching — no manual intervention needed.

## License

The patch modifies GPL-licensed kernel code (`drivers/bluetooth/btusb.c`). This project is distributed under the same [GPL-2.0](https://www.gnu.org/licenses/old-licenses/gpl-2.0.html) license.
