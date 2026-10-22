#!/usr/bin/env bash
# Pull the course-provided pieces out of the official CS6290 VirtualBox VM (.ova)
# so the Docker image can be built from them instead of from third-party images.
#
#   ./extract-vm.sh "/path/to/CS6290 Project VM.ova" [outdir]
#
# Produces in outdir (default ./vm, git-ignored):
#   mipsroot.tar    /mipsroot        MIPS sysroot (tools) + i386 cross compiler (cross-tools)
#   sesc.tar        sesc/            the SESC simulator + Splash2 tree from /home/cs6290
#   build-mipsroot.tar  sesc/scripts/build-mipsroot: the script and upstream GNU source
#                   tarballs (gcc 4.6.3, binutils 2.21.1, eglibc 2.13, ...) the cross
#                   toolchain was built from. Kept for provenance, not put in the image.
#   MANIFEST.md5    md5 of every extracted file, VM-side paths
#   vm-info.txt     what the VM is (OS, disk layout, versions of make/scons/gcc/python)
#   dpkg-status.txt the VM's package list (make 3.81 and scons 2.1.0 are stock Ubuntu 12.04
#                   packages; the Dockerfile fetches those from old-releases.ubuntu.com)
#
# Everything runs inside an official Debian container with qemu-utils (vmdk -> raw),
# p7zip (split the raw disk into partition images) and e2fsprogs (debugfs rdump keeps
# file modes and symlinks). No root/loop devices needed. The .ova is treated as data;
# nothing from it is executed.
set -euo pipefail

OVA=${1:?usage: $0 <path to .ova> [outdir]}
OUT=$(cd "$(dirname "${2:-$(dirname "$0")/vm}")" 2>/dev/null && pwd)/$(basename "${2:-vm}")
[ -r "$OVA" ] || { echo "cannot read $OVA" >&2; exit 1; }
mkdir -p "$OUT"
WORK=$(mktemp -d "$OUT/.work.XXXXXX")
trap 'chmod -R u+w "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT

echo "==> unpacking OVA into $WORK"
tar -xf "$OVA" -C "$WORK"
ls -l "$WORK"
grep -oE '<(Name|vssd:VirtualSystemType|OperatingSystemSection[^>]*|Description)>[^<]*' "$WORK"/*.ovf | head -5 > "$OUT/vm-info.txt" || true
[ -n "$(ls "$WORK"/*.vmdk 2>/dev/null)" ] || { echo "no .vmdk inside the OVA" >&2; exit 1; }

DEBIAN=debian:bookworm@sha256:17122fe3d66916e55c0cbd5bbf54bb3f87b3582f4d86a755a0fd3498d360f91b

echo "==> extracting inside a Debian container (this takes a few minutes)"
docker run --rm -v "$WORK:/w" -v "$OUT:/out" "$DEBIAN" bash -eu -o pipefail -c '
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq >/dev/null
  apt-get install -y -qq --no-install-recommends qemu-utils p7zip-full e2fsprogs fdisk >/dev/null
  cd /w
  vmdk=$(ls *.vmdk | head -1)
  echo "--- $vmdk"; qemu-img info "$vmdk" | sed -n "1,4p"
  qemu-img convert -O raw "$vmdk" disk.raw
  echo "--- partitions"; sfdisk -l disk.raw | tee -a /out/vm-info.txt
  mkdir -p parts
  7z x -y -oparts disk.raw >/dev/null
  ls -l parts
  root=""
  for p in parts/*; do
    if debugfs -R "ls -l /home/cs6290" "$p" 2>/dev/null | grep -q sesc; then root=$p; break; fi
  done
  [ -n "$root" ] || { echo "no ext filesystem with /home/cs6290/sesc found (LVM?)" >&2; exit 1; }
  echo "--- root filesystem: $root" | tee -a /out/vm-info.txt
  # Extract on the container filesystem (case-sensitive): the VM has files that differ
  # only by case (water-sp/Input vs input, xt_MARK.h vs xt_mark.h) which a macOS
  # bind mount would silently merge. Only the tars go to /out.
  R=/x/root; mkdir -p $R/home/cs6290 $R/mipsroot $R/etc $R/var/lib/dpkg
  rd() { debugfs -R "rdump $1 $2" "$root" 2>&1 | grep -v "^debugfs" || true; }
  rd /home/cs6290/sesc $R/home/cs6290
  rd /mipsroot/tools   $R/mipsroot
  rd /mipsroot/cross-tools $R/mipsroot
  for f in os-release lsb-release hostname issue passwd group apt/sources.list; do
    mkdir -p "$R/etc/$(dirname $f)"; debugfs -R "cat /etc/$f" "$root" > "$R/etc/$f" 2>/dev/null || true
  done
  debugfs -R "cat /var/lib/dpkg/status" "$root" > $R/var/lib/dpkg/status 2>/dev/null || true
  grep -E "^cs6290" $R/etc/passwd > /out/passwd-cs6290 || true
  cp $R/var/lib/dpkg/status /out/dpkg-status.txt
  echo "--- os"; cat $R/etc/lsb-release $R/etc/os-release 2>/dev/null | sort -u | tee -a /out/vm-info.txt
  echo "--- key packages (dpkg status)" | tee -a /out/vm-info.txt
  for pk in make scons gcc g++ binutils python2.7 libc6 perl bison flex m4 libdatetime-perl; do
    v=$( (grep -A12 -x "Package: $pk" $R/var/lib/dpkg/status || true) | (grep -m1 "^Version:" || true) | cut -d" " -f2)
    if [ -n "$v" ]; then echo "$pk $v"; fi
  done | tee -a /out/vm-info.txt
  echo "--- sizes"; du -sh $R/home/cs6290/sesc $R/mipsroot/*
  echo "--- md5 manifest"
  (cd $R && find home mipsroot -type f -exec md5sum {} + | sort -k2) > /out/MANIFEST.md5
  wc -l /out/MANIFEST.md5
  tar -C $R -cf /out/mipsroot.tar mipsroot
  # sesc.tar = what the image needs; build-mipsroot.tar = the toolchain build recipe and
  # upstream source tarballs the VM keeps under sesc/scripts/build-mipsroot (provenance)
  tar -C $R/home/cs6290 --exclude="sesc/scripts/build-mipsroot" --exclude=".DS_Store" --exclude="._*" -cf /out/sesc.tar sesc
  tar -C $R/home/cs6290 -cf /out/build-mipsroot.tar sesc/scripts/build-mipsroot
  chown -R --reference=/out /out 2>/dev/null || true
  ls -l /out
'
echo "==> done: $OUT"
cat "$OUT/vm-info.txt"
