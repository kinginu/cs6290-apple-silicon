# CS6290 SESC environment for Apple Silicon (single container)

The course VM is VirtualBox/x86 only. The community Docker images split the work across two
containers with different CPU architectures:

| image | arch | contains |
|---|---|---|
| `jsachs123/sesc` | arm64 only | SESC source (builds and runs natively on Apple Silicon) |
| `jsachs123/cs6290` | amd64 only | the MIPS cross compiler (gcc 4.6.3; its binaries are 32-bit **i386**) |

This image merges them: it starts from the arm64 SESC image and copies in the **unmodified**
i386 cross toolchain plus its i386 runtime libraries. Every i386 executable is wrapped with
`qemu-i386-static`, so it works on Docker Desktop, OrbStack, Colima, etc. — no host binfmt setup.

Because the compiler binaries are byte-for-byte the originals, the `.mipseb` files it produces are
identical to the ones from `jsachs123/cs6290`. Checked: Splash2 `lu.mipseb` and the handout's
`hello.mipseb` (`-O0 -g ...`) have the same md5, and `lu -n256 -p1` gives the same `clockTicks`.

## Use

```bash
docker compose up -d
docker exec -it cs6290 bash

cd ~/sesc && make                      # build the simulator (~1.5 min, native arm64)
cd ~/sesc/apps/Splash2/lu && make      # cross-compile a benchmark (same shell!)
~/sesc/sesc.opt -fn256.rpt -c ~/sesc/confs/cmp4-noc.conf -olu.out -elu.err lu.mipseb -n256 -p1
```

Build the image yourself instead of pulling: `docker build --platform linux/arm64 -t cs6290-unified .`
(OrbStack only: `--build-arg USE_QEMU=0` gives a smaller image that relies on OrbStack's i386 binfmt.)

On an x86_64 Linux machine you don't need this: `jsachs123/cs6290` alone runs natively.

## Things that change your numbers (measured)

- **How you spell the binary.** SESC copies the program's argv onto the simulated stack, so
  `lu.mipseb`, `./lu.mipseb` and an absolute path give different cycle counts. Run from the
  benchmark directory with the bare name, exactly as the handout says. (`-o`/`-e`/`-f` don't matter.)
- **Report files are appended, not overwritten.** Delete `sesc_*.rpt` before re-running with the
  same `-f` name, or `report.pl` will silently show the first run's numbers.
- **An empty `.err` does not mean success.** SESC creates the `-o`/`-e` files even when it fails
  to start. Also check that the `.out` file has content.
- **Multi-file Splash2 apps** (barnes, ocean, water-*, ...) link objects in `$(wildcard)` order,
  which depends on the filesystem. Single-file apps (lu, fft, radix) are unaffected.

## Notes

- Based on `jsachs123/sesc@sha256:a99fa07d…` and `jsachs123/cs6290@sha256:57753f1d…` (pinned in the Dockerfile).
- This repo only contains the environment — no course solutions.
