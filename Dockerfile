# Copyright (C) 2026  Henrique Almeida
# This file is part of cgit slim.
#
# cgit slim is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# cgit slim is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with cgit slim.  If not, see <https://www.gnu.org/licenses/>.

################################################################################

ARG CGIT_VERSION="09d24d7cd0b7e85633f2f43808b12871bb209d69"
ARG GIT_VERSION="2.52.0"
ARG FCGIWRAP_VERSION="1.1.0"
ARG OPENSSH_VERSION="10.2p1"

ARG USER="1000"
ARG GROUP="1000"

ARG CGIT_ROOT="/var/www/cgit"

################################################################################
# Base Build Stage
FROM alpine:3.23@sha256:865b95f46d98cf867a156fe4a135ad3fe50d2056aa3f25ed31662dff6da4eb62 AS base

RUN apk add \
  build-base \
  openssl-dev \
  openssl-libs-static \
  zlib-dev \
  zlib-static \
  ca-certificates

################################################################################
# Common autotools dependencies
FROM base AS autotools-base

RUN apk add \
  automake \
  autoconf \
  libtool \
  git

FROM base AS git-base

RUN apk add \
  curl-dev \
  curl-static \
  brotli-static \
  zstd-static \
  pcre2-dev \
  nghttp2-static \
  nghttp3-static \
  libpsl-static \
  libidn2-static \
  libunistring-static \
  c-ares-dev \
  expat-dev \
  expat-static \
  pkgconf

################################################################################
# cgit Build Stage
FROM git-base AS cgit-builder
ARG CGIT_VERSION
ARG CGIT_ROOT

RUN apk add curl

WORKDIR /build
ADD "https://git.zx2c4.com/cgit/snapshot/cgit-${CGIT_VERSION}.tar.xz" "/build/cgit.tar.xz"
RUN tar -xf /build/cgit.tar.xz

WORKDIR /build/cgit-${CGIT_VERSION}
RUN make get-git

RUN make LDFLAGS="-static" \
  EXTLIBS="-lnghttp2 -lssl -lcrypto -lz -lbrotlidec -lbrotlicommon -lzstd -lpsl -lidn2 -lunistring -lcares" \
  NO_LUA=1 NO_REGEX=NeedsStartEnd NO_GETTEXT=YesPlease NO_TCLTK=YesPlease -j$(nproc)

RUN mkdir -p /rootfs/${CGIT_ROOT} /rootfs/bin && \
  cp cgit /rootfs/bin/cgit && \
  cp cgit.css cgit.png cgit.js favicon.ico /rootfs/${CGIT_ROOT}/

################################################################################
# fcgiwrap Build Stage
FROM autotools-base AS fcgiwrap-builder
ARG FCGIWRAP_VERSION

RUN apk add fcgi-dev

WORKDIR /build
RUN git clone -b "${FCGIWRAP_VERSION}" --depth 1 https://github.com/gnosek/fcgiwrap.git
WORKDIR /build/fcgiwrap
# Force static link of libfcgi
RUN autoreconf -i && \
  ./configure LDFLAGS="-static" && \
  make LDFLAGS="-static" LDLIBS="-lfcgi" CFLAGS="-std=gnu99 -Wall -O2"

################################################################################
# OpenSSH Client Build Stage
FROM base AS openssh-builder
ARG OPENSSH_VERSION

RUN apk add \
  linux-headers \
  libedit-dev \
  libedit-static \
  ncurses-dev \
  ncurses-static

ADD "https://cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/openssh-${OPENSSH_VERSION}.tar.gz" .
RUN tar -xzf "openssh-${OPENSSH_VERSION}.tar.gz" && \
  cd "openssh-${OPENSSH_VERSION}" && \
  ./configure --enable-static --without-pie \
  --with-ldflags="-static" \
  --with-libs="-lssl -lcrypto -lz" \
  --disable-pkcs11 \
  --disable-security-key && \
  make -j$(nproc) ssh && \
  mkdir -p /build && \
  cp ssh /build/ssh

################################################################################
# Git Build Stage
FROM git-base AS git-builder
ARG GIT_VERSION

RUN apk add linux-headers

ADD "https://www.kernel.org/pub/software/scm/git/git-${GIT_VERSION}.tar.xz" "git.tar.xz"
RUN tar -xf git.tar.xz && \
  cd git-${GIT_VERSION} && \
  export LIBS="$(pkg-config --static --libs libcurl expat openssl)" && \
  ./configure LDFLAGS="-static" \
  --without-tcltk --without-python --with-curl --with-openssl --with-expat && \
  make LDFLAGS="-static" \
  EXTLIBS="$LIBS" \
  -j$(nproc) && \
  make install

RUN mkdir -p /rootfs/bin /rootfs/libexec/git-core && \
  cp /usr/local/bin/git /rootfs/bin/git && \
  cp -r /usr/local/libexec/git-core/git-remote* /rootfs/libexec/git-core

################################################################################
# Helpers Build Stage
FROM base AS helpers-builder
COPY init.c sync.c ./
RUN gcc -static -O2 -o /init ./init.c && \
  gcc -static -O2 -o /mirror-sync ./sync.c

################################################################################
# Nginx Stage
FROM h3nc4/nginx-slim:latest@sha256:350019151689a674d2baeefac77e2df8ac73167a2eeba4ca44ebced9713f579c AS nginx

################################################################################
# Assemble Root Filesystem
FROM alpine:3.23@sha256:865b95f46d98cf867a156fe4a135ad3fe50d2056aa3f25ed31662dff6da4eb62 AS rootfs-builder
ARG CGIT_VERSION
ARG CGIT_ROOT
ARG USER
ARG GROUP

# Directory structure
RUN mkdir -p \
  /rootfs/var/lib/git \
  /rootfs/${CGIT_ROOT} \
  /rootfs/etc/cgit \
  /rootfs/run \
  /rootfs/tmp \
  /rootfs/run/.ssh

# User and config
RUN echo "cgit:x:${USER}:${GROUP}:cgit User:/run:/bin/sh" >/rootfs/etc/passwd && \
  echo "cgit:x:${GROUP}:" >/rootfs/etc/group
RUN echo "Host *" >/rootfs/run/.ssh/config && \
  echo "  StrictHostKeyChecking accept-new" >>/rootfs/run/.ssh/config && \
  touch /rootfs/run/.ssh/known_hosts && \
  chmod 700 /rootfs/run/.ssh && \
  chmod 600 /rootfs/run/.ssh/*

# Copy Artifacts
COPY --from=cgit-builder /rootfs /rootfs
COPY --from=git-builder /rootfs /rootfs
COPY --from=fcgiwrap-builder /build/fcgiwrap/fcgiwrap /rootfs/bin/fcgiwrap
COPY --from=openssh-builder /build/ssh /rootfs/bin/ssh
COPY --from=nginx /nginx /rootfs/bin/nginx
COPY --from=base /etc/ssl/certs/ca-certificates.crt /rootfs/etc/ssl/certs/ca-certificates.crt

# Configuration and binaries
COPY --from=helpers-builder /init /rootfs/bin/init
COPY --from=helpers-builder /mirror-sync /rootfs/bin/mirror-sync
COPY ./cgitrc /rootfs/etc/cgitrc
COPY ./nginx.conf /rootfs/etc/nginx.conf

RUN chown -R "${USER}:${GROUP}" /rootfs/run /rootfs/var/lib/git /rootfs/${CGIT_ROOT} /rootfs/run /rootfs/tmp

################################################################################
# Final Image
FROM scratch AS final
ARG USER
ARG GROUP

COPY --from=rootfs-builder /rootfs /

# Environment and execution
ENV GIT_EXEC_PATH=/libexec/git-core
ENV HOME=/run

USER "${USER}:${GROUP}"
WORKDIR /var/lib/git
ENTRYPOINT ["/bin/init"]

LABEL org.opencontainers.image.title="cgit slim" \
  org.opencontainers.image.description="A minimal cgit container built from scratch" \
  org.opencontainers.image.authors="Henrique Almeida <me@h3nc4.com>" \
  org.opencontainers.image.vendor="Henrique Almeida" \
  org.opencontainers.image.licenses="GPL-3.0-or-later" \
  org.opencontainers.image.source="https://github.com/h3nc4/cgit-slim"
