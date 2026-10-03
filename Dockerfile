# check=skip=FromPlatformFlagConstDisallowed
# Unified arm64 image: native SESC (from jsachs123/sesc) + the exact i386
# MIPS cross toolchain bytes from jsachs123/cs6290, run via binfmt/qemu.
FROM --platform=linux/amd64 jsachs123/cs6290@sha256:57753f1da851b2e7f165a6624879f356f405b0cb97771efc31ee1c2fb0a5336e AS x86

FROM --platform=linux/arm64 jsachs123/sesc@sha256:a99fa07d63689f2776be45173543e0d0fad5d59c63d1ad83a5d792384d96f6fe
USER root
COPY --from=x86 /mipsroot/cross-tools /mipsroot/cross-tools
COPY --from=x86 /usr/lib/i386-linux-gnu /usr/lib/i386-linux-gnu
RUN ln -sf i386-linux-gnu/ld-2.31.so /usr/lib/ld-linux.so.2 \
 && test -e /lib/ld-linux.so.2 \
 && echo /mipsroot/cross-tools/lib > /etc/ld.so.conf.d/mipsroot.conf \
 && ldconfig
COPY wrap-i386.sh /usr/local/sbin/wrap-i386.sh
ARG USE_QEMU=1
RUN if [ "$USE_QEMU" = 1 ]; then \
      apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends qemu-user-static file \
      && rm -rf /var/lib/apt/lists/* && sh /usr/local/sbin/wrap-i386.sh /mipsroot/cross-tools ; \
    fi
ENV PATH=${PATH}:/mipsroot/cross-tools/bin
USER cs6290
WORKDIR /home/cs6290
