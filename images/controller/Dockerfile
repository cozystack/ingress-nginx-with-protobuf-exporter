ARG TAG

FROM --platform=$BUILDPLATFORM golang:1.24-alpine as builder
# The controller is pure Go with CGO off, so it cross-compiles on the build host
# for every target; only the RUN steps on the upstream controller base run
# emulated.
ARG TAG=$TAG
ARG TARGETARCH
RUN apk add --no-cache git
RUN git clone --branch controller-${TAG} --depth 1 https://github.com/kubernetes/ingress-nginx /src
WORKDIR /src
COPY patches/* .
RUN git apply *.diff
# This is the script `make build` ends up running. The make target is skipped
# because on its way it installs ginkgo for ARCH and then looks it up on PATH,
# which fails whenever ARCH is not the build host's architecture.
RUN PKG=k8s.io/ingress-nginx ARCH=${TARGETARCH} TAG=${TAG} \
    COMMIT_SHA=git-$(git rev-parse --short HEAD) \
    REPO_INFO=$(git config --get remote.origin.url) \
    build/build.sh
RUN mv /src/rootfs/bin/${TARGETARCH}/nginx-ingress-controller /nginx-ingress-controller
RUN apk add --no-cache libcap
RUN setcap cap_net_bind_service+ep /nginx-ingress-controller

# lua-protobuf needs -fno-strict-aliasing. pb.c violates strict aliasing, gcc 13
# did not act on it and gcc 14 at -O2 does, and the pb.so that comes out makes
# nginx's cache manager and cache loader children segfault continuously, tens per
# second and indefinitely. The workers are unaffected, so the pod stays Ready
# with no restarts and the failure is invisible. Alpine 3.21 is where gcc 14
# arrived, and this base carries it.
#
# -O1 and -O0 also produce working modules, which is what points at the source
# rather than at the compiler version. lua-iconv is unaffected and keeps the
# default flags. The durable fix belongs upstream in lua-protobuf.
#
# The rocks get their own stage, on the same base as the runtime image so the
# LuaJIT and musl they compile against are identical by construction. It also
# keeps apk out of the runtime image, where installing musl-dev upgrades musl
# underneath the nginx that base image already built.
FROM registry.k8s.io/ingress-nginx/controller:$TAG as rocks

USER root

# required packages to build lua and run luarocks. git is needed because the
# rock sources below are fetched from git rather than a source tarball.
RUN apk add --no-cache make gcc musl-dev git

# What this stage builds is loaded by nginx, so its sources are pinned: the
# luarocks tarball by sha256, each rock's source by commit. The rockspecs in
# rocks/ are the ones published on luarocks.org, and they name their sources by
# git tag, which can be moved. So each source is checked out at a fixed commit
# instead, and `luarocks make` builds the rockspec from that checkout without
# fetching anything.
ARG LUA_ROCKS_VER="3.0.0"
ARG LUA_ROCKS_SHA256="a43fffb997100f11cccb529a3db5456ce8dab18171a5cb3645f948147b6f64a1"
# The commits of lua-protobuf tag 0.4.1 and lua-iconv tag v7.1.0.
ARG LUA_PROTOBUF_COMMIT="2a2b0b95117642ad9470bfe0add7dd6ce82f3869"
ARG LUA_ICONV_COMMIT="dbdd9d9ab8620de87ab19d7084d553302660a321"
COPY rocks /rocks
RUN cd /tmp \
 && wget https://luarocks.org/releases/luarocks-${LUA_ROCKS_VER}.tar.gz \
 && echo "${LUA_ROCKS_SHA256}  luarocks-${LUA_ROCKS_VER}.tar.gz" | sha256sum -c - \
 && tar zxf luarocks-${LUA_ROCKS_VER}.tar.gz \
 && cd luarocks-${LUA_ROCKS_VER} \
 && ./configure \
 && make build \
 && make install \
 && git clone --quiet https://github.com/starwing/lua-protobuf.git /tmp/lua-protobuf \
 && git -C /tmp/lua-protobuf checkout --quiet ${LUA_PROTOBUF_COMMIT} \
 && cd /tmp/lua-protobuf \
 && luarocks make /rocks/lua-protobuf-0.4.1-1.rockspec CFLAGS="-O2 -fPIC -fno-strict-aliasing" \
 && git clone --quiet https://github.com/lunarmodules/lua-iconv.git /tmp/lua-iconv \
 && git -C /tmp/lua-iconv checkout --quiet ${LUA_ICONV_COMMIT} \
 && cd /tmp/lua-iconv \
 && luarocks make /rocks/lua-iconv-7.1.0-1.rockspec \
 && cd / \
 && rm -rf /tmp/*

# nginx itself, rebuilt with security fixes the upstream image lacks.
#
# kubernetes/ingress-nginx is archived and will not publish another 1.11.x, so
# the nginx 1.25.5 in its controller image stays as released. This stage
# compiles that same nginx again, from upstream's own sources, patches, module
# pins and configure line, with the backported fixes in nginx/patches applied
# last, and the binary replaces the shipped one below. Everything else in the
# image is upstream's, byte for byte. nginx/build.sh has the details.
#
# It runs on the upstream controller image so the binary links against the
# LuaJIT and libmodsecurity that image already carries. The -dev packages
# installed here may move musl and OpenSSL forward by a patch release within
# Alpine 3.21; that stays in this stage, and both keep their ABI across patch
# releases.
FROM registry.k8s.io/ingress-nginx/controller:$TAG as nginx

USER root

RUN apk add --no-cache bash curl git patch gcc make musl-dev linux-headers \
      openssl-dev pcre-dev zlib-dev libmaxminddb-dev libcap

COPY --from=builder /src/images/nginx/rootfs/build.sh /upstream/build.sh
COPY --from=builder /src/images/nginx/rootfs/patches /upstream/patches
COPY nginx/patches /extra-patches
COPY nginx/build.sh /build-nginx.sh

RUN /build-nginx.sh /upstream /extra-patches \
 && chown www-data:www-data /nginx \
 && setcap cap_net_bind_service=+ep /nginx \
 && setcap -v cap_net_bind_service=+ep /nginx

FROM registry.k8s.io/ingress-nginx/controller:$TAG

USER root

RUN mkdir -p /tmp/nginx && chown www-data: /tmp/nginx

USER www-data

# pb.so also answers require("pb.buffer") through Lua's all-in-one C loader, and
# protoc.lua is the pure-Lua half of lua-protobuf. pbmetrics.lua requires all
# three, plus iconv.
COPY --from=rocks /usr/local/lib/lua/5.1/pb.so /usr/local/lib/lua/5.1/pb.so
COPY --from=rocks /usr/local/lib/lua/5.1/iconv.so /usr/local/lib/lua/5.1/iconv.so
COPY --from=rocks /usr/local/share/lua/5.1/protoc.lua /usr/local/share/lua/5.1/protoc.lua

# Build-time smoke test, and the one a miscompiled pb.so fails. Loading protoc
# runs enough of pb.so's own code to hit the aliasing bug, and the process then
# dies with SIGSEGV on exit, so a bad build fails here instead of shipping an
# image that segfaults nginx's cache children in production.
RUN luajit -e 'require "protoc"; require "iconv"'

COPY --from=builder /nginx-ingress-controller /nginx-ingress-controller

# /usr/bin/nginx is a symlink to this path, so both pick up the rebuilt binary.
COPY --from=nginx /nginx /usr/local/nginx/sbin/nginx

# Fails the build if the rebuilt binary cannot start on this image.
RUN nginx -V

COPY --chown=www-data:www-data ./etc/nginx /etc/nginx

LABEL org.opencontainers.image.source="https://github.com/cozystack/ingress-nginx-with-protobuf-exporter"
