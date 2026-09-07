#!/bin/sh
set -eu

# 1. Custom unlock / mount for /var
# Replace this with your bespoke decryption/mapping commands if encrypted
mkdir -p /sysroot/var
if ! mount /dev/disk/by-label/var /sysroot/var 2>/dev/null; then
    # Fallback: boot with ephemeral tmpfs if /var cannot be mounted yet
    mkdir -p /run/etc-upper /run/etc-work
    mount -t overlay overlay /sysroot/etc \
        -o lowerdir=/sysroot/etc,upperdir=/run/etc-upper,workdir=/run/etc-work
    exit 0
fi

# 2. Ensure directories exist on the persistent backing filesystem
mkdir -p /sysroot/var/etc /sysroot/var/.etc-work

# 3. Mount overlay over /sysroot/etc
mount -t overlay overlay /sysroot/etc \
    -o lowerdir=/sysroot/etc,upperdir=/sysroot/var/etc,workdir=/sysroot/var/.etc-work