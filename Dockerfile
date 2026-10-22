# syntax=docker/dockerfile:1
# check=skip=FromPlatformFlagConstDisallowed
#
# SESC environment for OMSCS CS6290, built only from sources you can vouch for:
#
#   * the official Ubuntu 20.04 image (Docker Hub library, digest-pinned below)
#   * the course's own VirtualBox VM ("CS6290 Project VM.ova", Ubuntu 12.04.3): the
#     SESC source tree, the MIPS sysroot and the i386 cross compiler (gcc 4.6.3) are
#     copied out of it byte for byte by ./extract-vm.sh into ./vm/ (not committed)
#   * GNU make 3.81 and SCons 2.1.0, the stock Ubuntu 12.04 packages the VM uses,
#     fetched from Ubuntu's official old-releases archive and SHA256-checked
#   Nothing is taken from third-party Docker Hub images.
#
# The i386 tools run natively on amd64 (with the i386 glibc from Ubuntu's own
# archive) and through qemu-i386-static wrappers on arm64, so the same Dockerfile
# serves x86_64 Linux hosts and Apple Silicon. Compiled .mipseb files are identical
# to the VM's (same compiler bytes, same make 3.81 which sorts $(wildcard), hence
# the same link order).
#
# Build:  ./extract-vm.sh "/path/to/CS6290 Project VM.ova"   # once, produces ./vm/
#         docker build -t cs6290-unified .                   # or: docker compose build

ARG UBUNTU=ubuntu:20.04@sha256:8feb4d8ca5354def3d8fce243717141ce31e2c428701f6682bd2fafe15388214

# ---- i386 runtime for the cross compiler, from Ubuntu's official archive ----------
FROM --platform=linux/amd64 ${UBUNTU} AS i386libs
RUN dpkg --add-architecture i386 \
 && apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      libc6:i386 libstdc++6:i386 libgcc-s1:i386 \
 && rm -rf /var/lib/apt/lists/*

# ---- the environment ----------------------------------------------------------------
FROM ${UBUNTU}
ARG TARGETARCH
ENV TZ=America/New_York
RUN ln -fs /usr/share/zoneinfo/$TZ /etc/localtime \
 && apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      bison flex g++ gdb swig python2 python-is-python2 libdatetime-perl \
      sudo file less vim-tiny ca-certificates curl \
      $( [ "$TARGETARCH" = arm64 ] && echo qemu-user-static ) \
 && rm -rf /var/lib/apt/lists/*

# i386 glibc/libstdc++/libgcc (amd64 runs i386 binaries natively; arm64 via qemu)
COPY --from=i386libs /usr/lib/i386-linux-gnu /usr/lib/i386-linux-gnu
RUN ln -sf i386-linux-gnu/ld-2.31.so /usr/lib/ld-linux.so.2 && test -e /lib/ld-linux.so.2

# Course VM contents (see extract-vm.sh): MIPS sysroot + i386 cross compiler
ADD vm/mipsroot.tar /
RUN echo /mipsroot/cross-tools/lib > /etc/ld.so.conf.d/mipsroot.conf && ldconfig

# GNU make 3.81 and SCons 2.1.0: the Ubuntu 12.04 (precise) packages, from the official
# archive. make is the i386 build so that the same bytes run on amd64 (natively) and
# arm64 (qemu). Installed under /usr/local so they shadow Ubuntu 20.04's make/scons.
# (make 4.2.1 would return $(wildcard) unsorted and change the benchmarks' link order.)
RUN set -eu; cd /tmp; A=http://old-releases.ubuntu.com/ubuntu/pool/main; \
    curl -fsSLO $A/m/make-dfsg/make_3.81-8.1ubuntu1.1_i386.deb; \
    curl -fsSLO $A/s/scons/scons_2.1.0-1_all.deb; \
    echo "0ea094ed08e36afa558db1346f7019609caa85730e84c3713956763233fe5299  make_3.81-8.1ubuntu1.1_i386.deb" | sha256sum -c; \
    echo "363f54f1e838140e953dd1bede2d66bcf8e05b3ad7085b105f371fe95218b32c  scons_2.1.0-1_all.deb" | sha256sum -c; \
    mkdir x; dpkg-deb -x make_3.81-8.1ubuntu1.1_i386.deb x; dpkg-deb -x scons_2.1.0-1_all.deb x; \
    install -m755 x/usr/bin/make /usr/local/bin/make; \
    install -m755 x/usr/bin/scons /usr/local/bin/scons; \
    cp -a x/usr/lib/scons /usr/local/lib/scons; \
    rm -rf /tmp/x /tmp/*.deb

# On arm64 every i386 executable gets a qemu wrapper at its original path
COPY wrap-i386.sh /usr/local/sbin/wrap-i386.sh
RUN if [ "$TARGETARCH" = arm64 ]; then \
      sh /usr/local/sbin/wrap-i386.sh /mipsroot/cross-tools \
   && sh /usr/local/sbin/wrap-i386.sh /usr/local/bin ; \
    fi

# Same user as the VM (uid 1000, passwordless sudo)
RUN useradd -ms /bin/bash cs6290 && usermod -aG sudo cs6290 \
 && echo 'cs6290 ALL=(ALL) NOPASSWD:ALL' > /etc/sudoers.d/cs6290
ADD --chown=cs6290:cs6290 vm/sesc.tar /home/cs6290/
# Two edits to the VM's tree so it builds with Ubuntu 20.04's gcc 9 (the VM used gcc 4.6):
#   SConstruct: add -fpermissive (SESC's C++ is pre-C++11 and gcc 9 rejects it otherwise)
#   RunHelper.mk: fix the "t2. base" typo. Neither touches the simulated behaviour.
RUN sed -i "s/main.Append(CXXFLAGS=\['-std=c++0x'\])/main.Append(CXXFLAGS=['-std=c++0x', '-fpermissive'])/" /home/cs6290/sesc/SConstruct \
 && sed -i 's/^t2\. base      =/t2.base       =/' /home/cs6290/sesc/apps/scripts/RunHelper.mk \
 && grep -q fpermissive /home/cs6290/sesc/SConstruct && grep -q '^t2.base' /home/cs6290/sesc/apps/scripts/RunHelper.mk

ENV PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/mipsroot/cross-tools/bin
LABEL org.opencontainers.image.source="https://github.com/kinginu/cs6290-apple-silicon" \
      org.opencontainers.image.description="SESC + MIPS cross compiler for CS6290, built from the course VM and Ubuntu only"
USER cs6290
WORKDIR /home/cs6290
CMD ["bash"]
