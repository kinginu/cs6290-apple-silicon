# CS6290 SESC environment in Docker (Apple Silicon and x86_64)

The course ships a VirtualBox VM (Ubuntu 12.04, x86) that does not run on Apple Silicon.
This repo builds an equivalent Docker image from that VM and official Ubuntu packages, with
the MIPS cross compiler and SESC in **one container**:

| what | where it comes from |
|---|---|
| base OS | `ubuntu:20.04` |
| SESC simulator + Splash2 benchmarks (`~/sesc`) | the course VM, by `extract-vm.sh` |
| MIPS sysroot and the i386 cross compiler gcc 4.6.3 (`/mipsroot`) | the course VM, by `extract-vm.sh` |
| GNU make 3.81, SCons 2.1.0 | the Ubuntu 12.04 packages the VM uses, from `old-releases.ubuntu.com` |
| i386 runtime for the cross compiler | Ubuntu 20.04's `libc6:i386` etc. |

Because the compiler and make are the VM's own, the `.mipseb` files and the simulation
counters are the same as in the VM / the two-container setup from Ed.

## Build and use

```bash
./extract-vm.sh "/path/to/CS6290 Project VM.ova"   # once; writes ./vm/ (git-ignored, ~1.2 GB, a few minutes)
docker compose up -d --build                        # builds the image, starts container "cs6290"
docker exec -it cs6290 bash

cd ~/sesc && make                      # build the simulator (~1.5 min)
cd ~/sesc/apps/Splash2/lu && make      # cross-compile a benchmark, same shell
~/sesc/sesc.opt -fn256.rpt -c ~/sesc/confs/cmp4-noc.conf -olu.out -elu.err lu.mipseb -n256 -p1
```

`extract-vm.sh` only needs Docker: it reads the `.ova` inside a Debian container and copies the
files out of the VM's disk. No VirtualBox needed. It also writes `vm/MANIFEST.md5` and
`vm/vm-info.txt` so you can see exactly what was taken.

On arm64 the i386 tools run through `qemu-i386-static`, hidden behind wrappers that keep the
original names and paths, so you use `mips-unknown-linux-gnu-gcc` and `make` as usual. SESC
itself runs natively. On x86_64 (`docker build --platform linux/amd64 .`) everything is native.

Two edits are applied to the VM's SESC tree so it builds with gcc 9: `-fpermissive` in
`SConstruct`, and a typo fix in `apps/scripts/RunHelper.mk`. Neither changes simulated behaviour.

## Things that change your numbers (measured)

- **How you spell the binary.** SESC copies the program's argv onto the simulated stack, so
  `lu.mipseb`, `./lu.mipseb` and an absolute path give different cycle counts. Run from the
  benchmark directory with the bare name, exactly as the handout says. (`-o`/`-e`/`-f` don't matter.)
- **Report files are appended, not overwritten.** Delete `sesc_*.rpt` before re-running with the
  same `-f` name, or `report.pl` will silently show the first run's numbers.
- **An empty `.err` does not mean success.** SESC creates the `-o`/`-e` files even when it fails
  to start. Also check that the `.out` file has content.
- **GNU make version.** Multi-file benchmarks (fmm, raytrace, barnes, ...) link objects in
  `$(wildcard)` order. make 3.81 sorts that list; make 3.82–4.2 returns directory order, which
  gives a different `.mipseb` and cycle counts off by a few percent. `make --version` inside the
  container must say 3.81.

## Notes

- The built image contains course material (SESC and the toolchain), so it is not published.
  This repo only holds the build recipe.
- Feedback and fixes are welcome: please open a GitHub issue.
