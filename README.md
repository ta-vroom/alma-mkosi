# ι Iota

An immutable, A/B-updatable Linux operating system image based on **AlmaLinux 10**, built with [`mkosi`](https://github.com/systemd/mkosi), `systemd-repart`, `systemd-sysupdate`, `systemd-boot` Unified Kernel Images (UKIs), `erofs` + `dm-verity`, and **SELinux in Enforcing mode**.

> Originally forked from `castrojo/ubuntu-mkosi` as a sandbox for testing `mkosi`, A/B image layouts, and update hosting via Github releases; since redesigned around AlmaLinux 10, with an updated systemd from CentOS Hyperscale SIG, and patterns from `systemd/particleos`.

---

## Architecture & Key Features

### 1. Partition Layout & First-Boot Repartitioning

Iota builds a minimal, read-only Slot A image at build time and delegates Slot B and persistent storage creation to `systemd-repart` on first boot in the initrd.

| The initrd can be further customized by editing the files within mkosi.images/initrd

**Build-time partitions (`mkosi.repart/`):**
- **ESP (`00-esp.conf`)** — `vfat`, `512M`–`1G`, populated with `systemd-boot` and the UKI.
- **Root Verity (`11-root-verity.conf`)** — `root-verity` (`%M_%A_verity`), minimized hash tree for Slot A.
- **Root (`12-root.conf`)** — `erofs` (LZ4HC compressed, read-only, `%M_%A`), minimized and bound to `root-verity` via `VerityMatchKey=root`.

| In my testing Fedora and Alma's kernels did not have zstd compression for erofs enabled.

**First-boot initrd expansion (`mkosi.images/initrd/mkosi.extra/usr/lib/repart.d/` & `mkosi.extra/usr/lib/repart.d/`):**
On first boot, `systemd-repart.service` (ordered after `sysroot.mount` with `TMPDIR=/tmp`) expands the partition table into available disk space:
- Keeps Slot A (`00-esp.conf`, `11-root-verity.conf`, `12-root.conf` at `2G`).
- Creates empty Slot B partitions labeled `_empty`:
  - `21-root-verity.conf` (`64M`, `root-verity`)
  - `22-root.conf` (`2G`, `root`)
- Creates and formats persistent `/var` (`50-var.conf`, XFS, `Label=var`, `SizeMinBytes=300M`, `GrowFileSystem=yes`) with `/home`, `/etc`, `/.etc-work`, `/opt`, `/roothome`, `/mnt`, and `/srv`.

### 2. Immutable Root & Persistent State

- **Read-only `/`:** `/` is mounted from the `dm-verity` protected EROFS image (`/dev/mapper/root`).
- **Persistent `/var`:** Mounted in the initrd (`sysroot-var.mount`) and post-switch-root (`var.mount`) from `/dev/disk/by-partlabel/var`.
- **Writable `/etc` overlay:** `sysroot-etc-overlay.service` runs `/usr/libexec/mount-etc-overlay` in the initrd, mounting an OverlayFS over `/sysroot/etc` using `/sysroot/var/etc` as the upper directory and `/sysroot/var/.etc-work` as the work directory (falling back to `/run/etc-*` if `/sysroot/var` is absent).
- **Persistent top-level directories:** `/home`, `/root`, `/mnt`, `/opt`, and `/srv` are symlinked into `var/*` (`var/home`, `var/roothome`, `var/mnt`, `var/opt`, `var/srv`) and initialized via `usr/lib/tmpfiles.d/50-var-dirs.conf`.
- **Stateless PAM stack:** `/etc/pam.d` is moved to `/usr/lib/pam.d` during image build, with obsolete `pam_shells.so` and `pam_securetty.so` lines removed.

### 3. Atomic A/B Updates & Automatic Rollback

`mkosi.conf` produces split artifacts (`SplitArtifacts=uki,partitions`):
- Full compressed disk image: `iota_<version>_<arch>.raw.zst`
- Unified Kernel Image (with embedded initrd): `iota_<version>_<arch>.efi`
- Split verity-linked root & hash partitions: `iota_<version>_<arch>.root-<arch>.<uuid>.raw.zst` and `iota_<version>_<arch>.root-<arch>-verity.<uuid>.raw.zst`

Updates are managed by `systemd-sysupdate` using three transfer definitions in `mkosi.extra/usr/lib/sysupdate.d/`:
- `00-uki.transfer` — installs the UKI to `/EFI/Linux` on the ESP with `TriesLeft=3`, `TriesDone=0`, and `InstancesMax=2`.
- `10-root-verity.transfer` — writes the verity hash image to the spare `root-verity` slot (`%M_@v_verity`).
- `11-root.transfer` — writes the root EROFS image to the spare `root` slot (`%M_@v`).

All transfers set `ProtectVersion=%A` to prevent overwriting the currently booted version. On reboot:
1. `systemd-boot` selects the new `+3-0` UKI and decrements the try counter (`+2-1`).
2. Once the boot succeeds (`boot-complete.target`), `systemd-bless-boot.service` marks the entry good and strips the `+tries` suffix.
3. If the new version fails to complete boot and exhausts its tries (`+0-*`), `systemd-boot` automatically falls back to the previous working slot.

### 4. Security & Runtime Defaults

- **SELinux Enforcing:** `lsm=selinux` on the kernel command line, `SELINUX=enforcing` (`targeted` policy) in `/etc/selinux/config`, build-time labeling via `SELinuxRelabel=yes`, and first-boot `/var` labeling in `/usr/libexec/mount-etc-overlay` via `setfiles`.
- **Custom `iota_bless` SELinux module (`mkosi.extra/usr/share/selinux/iota/iota_bless.te`):** Compiled and installed at image build time (`checkmodule`, `semodule_package`, `semodule -n -i`) so `systemd-bless-boot` (`init_t`) can read, write, rename, and unlink UKI files on the `dosfs_t` ESP under Enforcing mode.
- **Minimal attack surface:** Package managers (`dnf`, `dnf-data`, `dnf-plugins-core`, `yum`, `dracut`) are removed from the runtime image (`RemovePackages=`).
- **Base services & tools:** `systemd-networkd`, `systemd-resolved`, `systemd-timesyncd`, socket-activated `sshd.socket`, `firewalld`, `podman`, `wireguard-tools`, `fish`, `vim` (`EDITOR`/`VISUAL`), and `bat` (`PAGER`).
- **Repositories:** AlmaLinux 10 + EPEL + CentOS Stream Hyperscale SIG `systemd` repo (`mkosi.sandbox/etc/yum.repos.d/centos-hyperscale-systemd.repo`).

---

## Repository Structure

```text
.
├── mkosi.conf                          # Main AlmaLinux 10 + Iota image definition
├── mkosi.postinst.chroot               # PAM cleanup, GPG trust, symlinks, iota_bless SELinux module, os-release/issue
├── mkosi.repart/                       # Build-time disk image partition definitions (ESP, root-verity, root)
├── mkosi.sandbox/                      # Sandbox repo & GPG key for CentOS Hyperscale SIG systemd
├── mkosi.extra/                        # Files injected into the root image
│   ├── efi/loader/loader.conf          # systemd-boot loader config
│   ├── etc/
│   │   ├── kernel/tries                # Initial boot-count tries (3)
│   │   ├── profile.d/                  # Default EDITOR=vim, PAGER=bat
│   │   ├── selinux/config              # SELINUX=enforcing, SELINUXTYPE=targeted
│   │   └── systemd/import-pubring.gpg  # sysupdate verification keyring
│   └── usr/
│       ├── lib/
│       │   ├── repart.d/               # Runtime partition definitions (Slot A, _empty Slot B, /var)
│       │   ├── systemd/                # var.mount & service presets (networkd, sshd.socket, bless-boot)
│       │   ├── sysupdate.d/            # Transfer definitions for UKI, root-verity, and root
│       │   └── tmpfiles.d/             # Persistent /var directory layout
│       └── share/
│           ├── keyrings/               # sysupdate release GPG keyring
│           └── selinux/iota/           # iota_bless.te SELinux module source
├── mkosi.images/
│   └── initrd/                         # Dedicated CPIO initrd image definition
│       ├── mkosi.conf                  # Initrd packages (systemd, cryptsetup, veritysetup, xfsprogs, etc.)
│       ├── mkosi.postinst.chroot       # Enables sysroot-var.mount and sysroot-etc-overlay.service
│       ├── mkosi.finalize              # Strips caches/docs from initrd
│       └── mkosi.extra/                # Initrd repart.d/, mount-etc-overlay, systemd-repart override
├── mkosi.profiles/                     # Inherited upstream mkosi profile drop-ins (not enabled by default)
└── .github/workflows/
    ├── test.yml                        # Full QEMU/OVMF E2E test (repart, sysupdate A->B, bless-boot, rollback)
    ├── build.yml                       # Runs tests, builds signed artifacts, publishes GitHub Release
    └── shell.yml                       # Checks latest release RPM DB for upstream updates & triggers build
```

---

## Building & Booting Locally

### Prerequisites

Install `mkosi` (CI uses `systemd/mkosi@v27`) along with virtualization, partitioning, filesystem, and SELinux tools on the build host:

- `mkosi` and `bubblewrap`
- `systemd-boot`, `systemd-repart`, `systemd-ukify`
- `erofs-utils`, `xfsprogs`, `zstd`, `mtools`, `binutils`
- `policycoreutils`, `python3-pefile`, `dnf`
- `qemu-system-x86`, `qemu-utils`, `ovmf` (for local VM testing)

### Build the Image

Inspect the resolved configuration:

```bash
mkosi summary
```

Build the initrd and main disk image (`RootPassword=root` is set in `mkosi.conf` for local testing):

```bash
sudo mkosi --image-version=1.0.0 --force build
```

Build artifacts are written to `mkosi.output/`, including:
- `iota_1.0.0_x86-64.raw.zst` (compressed GPT disk image)
- `iota_1.0.0_x86-64.efi` (Unified Kernel Image)
- `iota_1.0.0_x86-64.root-x86-64.<uuid>.raw.zst` and `iota_1.0.0_x86-64.root-x86-64-verity.<uuid>.raw.zst`

### Boot in QEMU (UEFI)

Decompress the disk image and add free space (`+6G` or more) so `systemd-repart` can create the `_empty` Slot B partitions and the XFS `/var` partition on first boot:

```bash
zstd -d mkosi.output/iota_1.0.0_x86-64.raw.zst -o disk-test.raw
qemu-img resize -f raw disk-test.raw +6G
```

Boot with OVMF (copying `OVMF_VARS_4M.fd` so EFI variables persist across reboots):

```bash
cp /usr/share/OVMF/OVMF_VARS_4M.fd ./ovmf_vars.fd
qemu-system-x86_64 \
  -enable-kvm -cpu host -m 2G -smp 2 \
  -drive if=pflash,format=raw,readonly=on,file=/usr/share/OVMF/OVMF_CODE_4M.fd \
  -drive if=pflash,format=raw,file=./ovmf_vars.fd \
  -drive file=./disk-test.raw,format=raw,if=virtio \
  -net nic,model=virtio \
  -net user,hostfwd=tcp:127.0.0.1:2222-:22 \
  -nographic
```

> Note: `mkosi.conf` does not enable serial console output by default (`logo.nologo lsm=selinux`); pass `console=ttyS0,115200n8` on the kernel command line if you want serial console output in `-nographic` mode.

---

## Verifying State, Updating & Rollback

Once booted into the VM:

```bash
# Verify SELinux, OS identity, partition layout, and mounts
getenforce
cat /usr/lib/os-release
lsblk -o NAME,PARTLABEL,PARTUUID,MOUNTPOINTS,SIZE
findmnt / /var /etc

# Inspect systemd-sysupdate components and available releases
/usr/lib/systemd/systemd-sysupdate components
/usr/lib/systemd/systemd-sysupdate list

# Stage an update into the _empty Slot B and install the boot-counted UKI
/usr/lib/systemd/systemd-sysupdate update
systemctl reboot
```

After rebooting into the updated slot:

```bash
# Verify boot-blessing status and active slot
/usr/lib/systemd/systemd-bless-boot status
bootctl status
```

If a new UKI fails to reach `boot-complete.target` before its 3 boot tries expire, `systemd-boot` automatically falls back to the previous slot while preserving `/var` and the `/etc` overlay.

---

## CI/CD Workflows

- **Verify (`test.yml`):** Runs on pull requests and manual dispatch. Builds `1.0.0` and `1.0.1`, resizes the disk by `+6G`, boots `1.0.0` in QEMU/OVMF, validates `systemd-repart`, `_empty` Slot B, `/var`, `/etc` overlay, and SELinux `Enforcing`, serves `1.0.1` over HTTP, runs `systemd-sysupdate update --verify=no`, reboots into Slot B (`iota_1.0.1`), verifies `systemd-bless-boot` and state persistence, and simulates a failed boot (`+1-0`) to confirm automatic rollback to `iota_1.0.0`.
- **Build & Release (`build.yml`):** Runs on pushes to `main`, `workflow_dispatch`, or calls from `shell.yml`. Runs `test.yml`, builds date-versioned artifacts (`YYYYMMDD` / `YYYYMMDD.N`), signs `SHA256SUMS` with GPG, and publishes a GitHub Release.
- **Update Check (`shell.yml`):** On `workflow_dispatch`, downloads the latest released root partition image, mounts it, and runs `dnf check-update` against `/usr/lib/sysimage/rpm/rpmdb.sqlite` inside an `almalinux` container. If package updates are available, it invokes `build.yml` with generated package diff release notes.
