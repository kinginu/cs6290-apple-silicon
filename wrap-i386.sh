#!/bin/sh
# Make the i386 cross toolchain run on any arm64 Docker host without the user
# ever noticing qemu.
#
# For every i386 ELF executable under $1:
#   - move the original bytes to <dir>/.i386/<name>   (hidden: not in ls / tab completion)
#   - put a tiny wrapper at the original path that runs it through qemu-i386-static
#     with argv[0] set to the original path (-0), so the tool sees its normal name:
#     error messages say "mips-unknown-linux-gnu-gcc: ..." and gcc locates cc1/as/ld
#     relative to its usual install prefix, exactly as on a real i386 host.
set -e
root=${1:-/mipsroot/cross-tools}
find "$root" -type f -perm -u+x -not -path '*/.i386/*' | while read -r f; do
  case "$f" in *.so|*.so.*) continue;; esac
  # ELF magic + EI_CLASS=1 (32-bit) + e_machine=3 (Intel 80386) + e_type=2 (ET_EXEC)
  hdr=$(od -An -tx1 -N20 "$f" 2>/dev/null | tr -d ' \n')
  case "$hdr" in 7f454c4601*) ;; *) continue;; esac
  [ "$(echo "$hdr" | cut -c37-40)" = 0300 ] || continue
  [ "$(echo "$hdr" | cut -c33-36)" = 0200 ] || continue
  dir=$(dirname "$f"); name=$(basename "$f")
  mkdir -p "$dir/.i386"
  mv "$f" "$dir/.i386/$name"
  printf '#!/bin/sh\nexec /usr/bin/qemu-i386-static -L / -0 "$0" "%s/.i386/%s" "$@"\n' "$dir" "$name" > "$f"
  chmod 755 "$f"
done
