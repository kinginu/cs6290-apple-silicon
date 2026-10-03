#!/bin/sh
# Replace every i386 ELF executable under $1 with a shell wrapper that runs
# the original bytes (renamed <name>.i386) through qemu-i386-static.
set -e
root=${1:-/mipsroot/cross-tools}
find "$root" -type f -perm -u+x | while read -r f; do
  case "$f" in *.so|*.so.*|*.i386) continue;; esac
  # ELF magic + EI_CLASS=1 (32-bit) + e_machine=3 (Intel 80386)
  hdr=$(od -An -tx1 -N20 "$f" 2>/dev/null | tr -d ' \n')
  case "$hdr" in 7f454c4601*) ;; *) continue;; esac
  mach=$(echo "$hdr" | cut -c37-40)
  etype=$(echo "$hdr" | cut -c33-36)
  [ "$mach" = 0300 ] || continue
  [ "$etype" = 0200 ] || continue   # ET_EXEC only (not shared objects)
  mv "$f" "$f.i386"
  printf '#!/bin/sh\nexec /usr/bin/qemu-i386-static -L / "$0.i386" "$@"\n' > "$f"
  chmod 755 "$f"
  echo "wrapped $f"
done
