# ubuntu-mkosi -- Build Ubuntu Images with mkosi

Practical examples and configurations for building Ubuntu images using [mkosi](https://github.com/systemd/mkosi), a tool for generating bespoke OS images. mkosi is a fancy wrapper around `apt` (and `dnf`, `pacman`, `zypper`) that generates customized disk images with a number of bells and whistles.

This repository is designed to help you get started building Ubuntu images with mkosi through working examples you can use directly or adapt for your own needs.

## What is mkosi?

**mkosi** (*Make Operating System Image*) generates OS images by:

1. Installing distribution packages into a fresh OS tree (using `apt` for Ubuntu)
2. Packaging that tree into various output formats (disk images, directories, tarballs, etc.)
3. Optionally booting the result in `qemu` or `systemd-nspawn`

Supported output formats include:

| Format | Description |
|--------|-------------|
| `directory` | Plain directory containing the OS tree |
| `disk` | GPT disk image built with `systemd-repart` |
| `tar` | Tar archive of the OS tree |
| `cpio` | CPIO archive (for initramfs images) |
| `uki` | Unified Kernel Image |
| `sysext` | System extension image |

## Prerequisites

### Install mkosi

The recommended way to install mkosi is via `pipx` from git to get the latest version:

```bash
# Install pipx if you don't have it
brew install pipx
pipx ensurepath

# Install mkosi from git (latest development version)
pipx install git+https://github.com/systemd/mkosi.git

# Verify installation
mkosi --version
```

You can also install mkosi from your distribution's package manager, but make sure it's **v16 or newer** (`mkosi --version` to check). If your distro packages an older version, use the `pipx` method above.

### Host Requirements

mkosi needs `bubblewrap` for sandboxing. Install it on your host:

```bash
# Fedora / CentOS / RHEL
sudo dnf install bubblewrap

# Debian / Ubuntu
sudo apt install bubblewrap

# Arch Linux
sudo pacman -S bubblewrap
```

### Building Ubuntu Images from a Non-Ubuntu Host

mkosi can cross-build Ubuntu images from any Linux distribution. If your host doesn't have `apt` installed (e.g., you're on Fedora, Arch, or CentOS), mkosi will need the `ubuntu-keyring` package or you can enable `RepositoryKeyFetch=yes` in your config.

On RPM-based hosts, the simplest approach is to let mkosi handle everything:

```ini
[Distribution]
Distribution=ubuntu
Release=noble
```

mkosi will automatically fetch Ubuntu's GPG keys when needed. If you run into key issues, install the keyring package for your host distro (e.g., `distribution-gpg-keys` on Fedora).

### Unprivileged User Namespaces (Ubuntu Hosts Only)

If you're running mkosi **on** an Ubuntu host (23.10+), you may need to enable unprivileged user namespaces:

```bash
sudo sysctl -w kernel.apparmor_restrict_unprivileged_unconfined=0
sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0
```

To persist across reboots, create `/etc/sysctl.d/unprivileged-userns.conf`:

```conf
kernel.apparmor_restrict_unprivileged_unconfined=0
kernel.apparmor_restrict_unprivileged_userns=0
```

## Quick Start

Clone this repository and build a basic Ubuntu Noble image:

```bash
git clone https://github.com/castrojo/ubuntu-mkosi.git
cd ubuntu-mkosi

# Build the default image (directory format)
mkosi

# Drop into a shell inside the image
mkosi shell

# Or boot the image in a systemd-nspawn container
mkosi boot
```

To rebuild after changes, add `-f` to force a rebuild:

```bash
mkosi -f
```

## Repository Structure

```
ubuntu-mkosi/
├── mkosi.conf                    # Base Ubuntu Noble configuration
├── mkosi.conf.d/
│   └── 10-ubuntu-repos.conf     # Enables universe repository
├── mkosi.profiles/
│   ├── minimal/                 # Minimal server profile
│   ├── desktop/                 # GNOME desktop profile
│   └── bootable/                # Bootable GPT disk image profile
├── mkosi.extra/
│   └── etc/motd                 # Custom MOTD injected into images
├── examples/
│   ├── 01-minimal-server/       # Simplest Ubuntu image
│   ├── 02-bootable-disk/        # Bootable GPT disk image
│   ├── 03-container/            # Container-optimized image
│   ├── 04-custom-packages/      # Web server stack with extra repos
│   ├── 05-development/          # Dev image with build scripts
│   ├── 06-sysext/               # System extension image
│   ├── 07-extra-files/          # Custom config files via mkosi.extra
│   └── 08-multi-release/        # Multiple Ubuntu releases via profiles
├── AGENTS.md                    # Instructions for AI agents
└── README.md                    # This file
```

## Using Profiles

This repository includes three profiles that customize the base configuration:

### Minimal Server

A stripped-down server image with SSH:

```bash
mkosi --profile minimal
mkosi --profile minimal shell
```

### Desktop (GNOME)

Full Ubuntu desktop with GNOME:

```bash
mkosi --profile desktop
```

### Bootable Disk Image

A GPT disk image you can boot in qemu or write to a USB drive:

```bash
# Build the disk image
mkosi --profile bootable

# Boot in qemu
mkosi --profile bootable vm

# Boot in systemd-nspawn
mkosi --profile bootable boot

# Write to a USB drive (CAREFUL - this overwrites the device!)
mkosi --profile bootable burn /dev/sdX
```

## Examples

Each example in the `examples/` directory is a self-contained mkosi project. To use an example, `cd` into its directory and run `mkosi`:

```bash
cd examples/01-minimal-server
mkosi
```

### Example 1: Minimal Server

**Directory:** `examples/01-minimal-server/`

The simplest possible Ubuntu image -- just systemd, networking, and SSH. A good starting point for understanding mkosi.

```bash
cd examples/01-minimal-server
mkosi              # Build
mkosi shell         # Interactive shell
mkosi boot          # Boot in systemd-nspawn
```

**Configuration highlights:**
```ini
[Distribution]
Distribution=ubuntu
Release=noble

[Output]
Format=directory

[Content]
Packages=systemd, udev, dbus, openssh-server, sudo
```

### Example 2: Bootable Disk Image

**Directory:** `examples/02-bootable-disk/`

A full GPT disk image with EFI boot support. Can be booted in qemu/KVM or written to physical media.

```bash
cd examples/02-bootable-disk
mkosi              # Build disk image
mkosi vm            # Boot in qemu
mkosi burn /dev/sdX # Write to USB drive
```

**Key settings:**
- `Format=disk` -- produces a GPT disk image
- `Bootable=yes` -- installs bootloader and generates UKIs
- `linux-image-generic` -- the Ubuntu kernel
- `systemd-boot-efi` -- required for systemd-boot on Debian/Ubuntu

### Example 3: Container Image

**Directory:** `examples/03-container/`

A lightweight directory image optimized for `systemd-nspawn` containers. No kernel or bootloader -- just the userspace.

```bash
cd examples/03-container
mkosi              # Build
mkosi boot          # Boot in systemd-nspawn container
mkosi shell         # Interactive shell without booting
```

**Key settings:**
- `Format=directory` -- no disk image overhead
- `Bootable=no` -- skip kernel and bootloader

### Example 4: Custom Packages

**Directory:** `examples/04-custom-packages/`

Demonstrates enabling extra Ubuntu repositories and installing a curated web server stack (nginx, PostgreSQL, Redis, Python).

```bash
cd examples/04-custom-packages
mkosi
mkosi shell
```

**Ubuntu repository components:**
| Component | Description |
|-----------|-------------|
| `main` | Canonical-supported free software (always enabled) |
| `universe` | Community-maintained free software |
| `restricted` | Proprietary drivers |
| `multiverse` | Software with usage restrictions |

Enable them with:
```ini
[Distribution]
Repositories=universe,multiverse
```

### Example 5: Development Image

**Directory:** `examples/05-development/`

Demonstrates mkosi's build script support for compiling source code against the image. Build dependencies are installed in an overlay and don't end up in the final image.

```bash
cd examples/05-development
mkosi
mkosi shell
```

**Key concepts:**
- `BuildPackages=` -- packages installed in a build overlay (gcc, cmake, etc.)
- `mkosi.build.chroot` -- script that runs inside the image to compile your project
- `$SRCDIR` -- your source code directory (mounted from host)
- `$DESTDIR` -- where to install build output
- `$BUILDDIR` -- persistent build directory for incremental builds

### Example 6: System Extension (sysext)

**Directory:** `examples/06-sysext/`

Builds a base Ubuntu image and a Docker system extension that layers on top. System extensions allow extending a read-only base OS without modifying it.

```bash
cd examples/06-sysext
mkosi              # Builds both base and sysext

# The sysext image will be in mkosi.output/
# Apply it at runtime with systemd-sysext
```

**Key settings:**
- `mkosi.images/base/` -- the base Ubuntu image
- `mkosi.images/docker-sysext/` -- the Docker extension
- `Format=sysext` and `Overlay=yes` -- only includes files added on top of the base
- `BaseTrees=%O/base` -- references the base image output
- `CleanPackageMetadata=no` -- keeps apt metadata in base for extension installs

### Example 7: Extra Files

**Directory:** `examples/07-extra-files/`

Demonstrates injecting custom configuration files into the image using `mkosi.extra/`. Files are copied into the image root after packages are installed.

```bash
cd examples/07-extra-files
mkosi
mkosi shell
cat /etc/motd                # Custom MOTD
cat /etc/sysctl.d/99-custom.conf  # Custom sysctl
```

**How it works:** Place files in `mkosi.extra/` mirroring the filesystem layout:
```
mkosi.extra/
├── etc/
│   ├── motd                    # → /etc/motd in the image
│   └── sysctl.d/
│       └── 99-custom.conf      # → /etc/sysctl.d/99-custom.conf
```

### Example 8: Multiple Ubuntu Releases

**Directory:** `examples/08-multi-release/`

Uses mkosi profiles to build images for different Ubuntu releases from the same base configuration.

```bash
cd examples/08-multi-release
mkosi --profile noble      # Ubuntu 24.04 LTS
mkosi --profile jammy      # Ubuntu 22.04 LTS
mkosi --profile plucky     # Ubuntu 25.04
```

## mkosi Configuration Reference

### Key Settings for Ubuntu

| Setting | Description | Example |
|---------|-------------|---------|
| `Distribution=` | Target distribution | `ubuntu` |
| `Release=` | Ubuntu release codename | `noble`, `jammy`, `plucky` |
| `Repositories=` | Enable extra repo components | `universe`, `multiverse`, `restricted` |
| `Mirror=` | Custom package mirror URL | `http://archive.ubuntu.com` |
| `Format=` | Output format | `directory`, `disk`, `tar`, `cpio` |
| `Bootable=` | Include kernel and bootloader | `yes`, `no`, `auto` |
| `Packages=` | Packages to install | `systemd, openssh-server` |
| `BuildPackages=` | Build-only packages (overlay) | `gcc, cmake` |
| `ExtraTrees=` | Extra files to copy into image | `mkosi.extra/` (auto-detected) |
| `Bootloader=` | EFI bootloader to use | `systemd-boot`, `uki`, `grub` |

### Configuration File Hierarchy

mkosi reads configuration in this order (later overrides earlier):

1. Command line arguments (highest priority)
2. `mkosi.local.conf` and `mkosi.local/` (gitignored, local overrides)
3. `mkosi.conf` (main configuration)
4. `mkosi.conf.d/*.conf` (drop-in files, alphabetical order)
5. Profile configs from `mkosi.profiles/<name>/`

### Important Files and Directories

| Path | Purpose |
|------|---------|
| `mkosi.conf` | Main configuration file |
| `mkosi.conf.d/` | Drop-in configuration directory |
| `mkosi.profiles/` | Named configuration profiles |
| `mkosi.extra/` | Extra files copied into image after package install |
| `mkosi.skeleton/` | Files copied before package install |
| `mkosi.build` | Build script (runs on host in sandbox) |
| `mkosi.build.chroot` | Build script (runs inside the image) |
| `mkosi.output/` | Build output directory |
| `mkosi.cache/` | Package download cache (speeds up rebuilds) |
| `mkosi.builddir/` | Out-of-tree build directory |
| `mkosi.repart/` | Custom systemd-repart partition definitions |

### Useful Commands

```bash
mkosi                  # Build the image (default verb)
mkosi -f               # Force rebuild (remove previous output first)
mkosi -ff              # Force rebuild + clear incremental cache
mkosi summary          # Show resolved configuration (dry run)
mkosi shell            # Interactive shell in the image (no boot)
mkosi boot             # Boot image in systemd-nspawn container
mkosi vm               # Boot image in qemu virtual machine
mkosi ssh              # SSH into a running VM
mkosi burn /dev/sdX    # Write disk image to block device
mkosi clean            # Remove build artifacts
mkosi genkey           # Generate SecureBoot keys
mkosi serve            # Serve output directory via HTTP
```

## Troubleshooting

### "Repository not found" or GPG key errors

If building Ubuntu images from a non-Ubuntu host, mkosi needs the Ubuntu GPG keys. Options:

1. Install `ubuntu-keyring` on your host (if available)
2. Install `distribution-gpg-keys` (Fedora/CentOS)
3. mkosi will try to fetch keys automatically (`RepositoryKeyFetch=` is enabled by default on Ubuntu)

### "Operation not permitted" or namespace errors

mkosi uses user namespaces for unprivileged builds. If you see permission errors:

- **Ubuntu host:** See the [Unprivileged User Namespaces](#unprivileged-user-namespaces-ubuntu-hosts-only) section above
- **Other systems:** Check `sysctl kernel.unprivileged_userns_clone` and ensure it's set to `1`

### KVM not available in `mkosi vm`

On Debian/Ubuntu hosts, `/dev/kvm` is restricted to the `kvm` group. Since mkosi uses user namespaces, group membership is lost. Workaround:

```bash
# Temporary fix
sudo chmod 0666 /dev/kvm

# Permanent fix: copy and modify the tmpfiles config
sudo cp /usr/lib/tmpfiles.d/static-nodes-permissions.conf /etc/tmpfiles.d/
# Edit /etc/tmpfiles.d/static-nodes-permissions.conf and change
# the mode of /dev/kvm from 0660 to 0666
```

### Slow builds

Speed up rebuilds with caching:

```bash
# Create a package cache directory (automatic if it exists)
mkdir mkosi.cache

# Use incremental builds (reuse installed packages between builds)
# Add to mkosi.conf:
#   [Build]
#   Incremental=yes

# Force rebuild but keep cache:
mkosi -f

# Force rebuild and clear all caches:
mkosi -fff
```

## References

- [mkosi GitHub repository](https://github.com/systemd/mkosi)
- [mkosi documentation (man page)](https://github.com/systemd/mkosi/blob/main/mkosi/resources/man/mkosi.1.md)
- [mkosi website](https://mkosi.systemd.io/)
- [A re-introduction to mkosi](https://0pointer.net/blog/a-re-introduction-to-mkosi-a-tool-for-generating-os-images.html) -- Detailed blog post by the mkosi maintainer
- [Building RHEL and RHEL UBI images with mkosi](https://fedoramagazine.org/create-images-directly-from-rhel-and-rhel-ubi-package-using-mkosi/) -- Fedora Magazine article
- [mkosi Matrix channel](https://matrix.to/#/#mkosi:matrix.org) -- Community chat

## License

This project is provided as-is for educational purposes. The mkosi configurations and examples are free to use and adapt.
