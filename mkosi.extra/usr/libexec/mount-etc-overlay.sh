#!/bin/sh
set -eu

mkdir -p /sysroot/var
if ! mount /dev/disk/by-label/var /sysroot/var 2>/dev/null; then
    # Fallback: boot with ephemeral tmpfs if /var cannot be mounted yet
    mkdir -p /run/etc-upper /run/etc-work
    mount -t overlay overlay /sysroot/etc \
        -o lowerdir=/sysroot/etc,upperdir=/run/etc-upper,workdir=/run/etc-work
    exit 0
fi

mkdir -p /sysroot/var/etc /sysroot/var/.etc-work

mount -t overlay overlay /sysroot/etc \
    -o lowerdir=/sysroot/etc,upperdir=/sysroot/var/etc,workdir=/sysroot/var/.etc-work