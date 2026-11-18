#!/bin/bash
#
# Rebuilds the nginx binary of the upstream controller image with extra
# patches on top, and nothing else.
#
# Runs inside the upstream controller image (see the `nginx` stage of the
# Dockerfile), so the binary is compiled against the very LuaJIT and
# libmodsecurity that image ships, and configured with the exact arguments its
# own nginx reports. Every source version comes from upstream's
# images/nginx/rootfs/build.sh at the same controller tag, passed in as $1;
# nothing is pinned twice.
#
#   $1  upstream images/nginx/rootfs directory (build.sh + patches/)
#   $2  directory holding the extra patches, applied after upstream's

set -euo pipefail

UPSTREAM=$1
EXTRA_PATCHES=$2

# Version pins and BUILD_PATH. The export block sits at the top of build.sh and
# ends at BUILD_PATH; later exports are build flags we do not want.
eval "$(sed -n '/^export NGINX_VERSION=/,/^export BUILD_PATH=/p' "$UPSTREAM/build.sh" | grep '^export ')"
BROTLI_COMMIT=$(sed -n 's/^git reset --hard \([0-9a-f]\{40\}\)$/\1/p' "$UPSTREAM/build.sh")
: "${NGINX_VERSION:?}" "${BUILD_PATH:?}" "${BROTLI_COMMIT:?}"

# The configure line the shipped binary was built with. It already carries the
# per-architecture flags (-m64 on x86_64, --with-file-aio off aarch64) and
# names the module sources under $BUILD_PATH, which is where they go below.
CONFIGURE_ARGS=$(nginx -V 2>&1 | sed -n 's/^configure arguments: //p')
SHIPPED_VERSION=$(nginx -v 2>&1 | sed -n 's|^nginx version: nginx/||p')
if [[ "$SHIPPED_VERSION" != "$NGINX_VERSION" ]]; then
  echo "base image ships nginx $SHIPPED_VERSION, build.sh pins $NGINX_VERSION" >&2
  exit 1
fi

mkdir -p "$BUILD_PATH"
cd "$BUILD_PATH"

get_src() {
  mkdir "$BUILD_PATH/$2"
  curl -fsSL "$1" | tar xz -C "$BUILD_PATH/$2" --strip-components=1
}

get_src "https://nginx.org/download/nginx-$NGINX_VERSION.tar.gz" "nginx-$NGINX_VERSION"
get_src "https://github.com/vision5/ngx_devel_kit/archive/$NDK_VERSION.tar.gz" ngx_devel_kit
get_src "https://github.com/openresty/set-misc-nginx-module/archive/$SETMISC_VERSION.tar.gz" set-misc-nginx-module
get_src "https://github.com/openresty/headers-more-nginx-module/archive/$MORE_HEADERS_VERSION.tar.gz" headers-more-nginx-module
get_src "https://github.com/yaoweibin/ngx_http_substitutions_filter_module/archive/$NGINX_SUBSTITUTIONS.tar.gz" ngx_http_substitutions_filter_module
get_src "https://github.com/openresty/lua-nginx-module/archive/$LUA_NGX_VERSION.tar.gz" lua-nginx-module
get_src "https://github.com/openresty/stream-lua-nginx-module/archive/$LUA_STREAM_NGX_VERSION.tar.gz" stream-lua-nginx-module
get_src "https://github.com/openresty/lua-upstream-nginx-module/archive/$LUA_UPSTREAM_VERSION.tar.gz" lua-upstream-nginx-module
get_src "https://github.com/atomx/nginx-http-auth-digest/archive/$NGINX_DIGEST_AUTH.tar.gz" nginx-http-auth-digest
get_src "https://github.com/SpiderLabs/ModSecurity-nginx/archive/$MODSECURITY_VERSION.tar.gz" ModSecurity-nginx
get_src "https://github.com/leev/ngx_http_geoip2_module/archive/$GEOIP2_VERSION.tar.gz" ngx_http_geoip2_module

git clone --quiet https://github.com/google/ngx_brotli.git
git -C ngx_brotli checkout --quiet "$BROTLI_COMMIT"
git -C ngx_brotli submodule update --quiet --init

# Same fix upstream's build.sh applies: gcc 14 rejects the implicit printf of
# ModSecurity-nginx's feature test.
sed -i "s/ngx_feature_test='printf(\"hello\");'/ngx_feature_test='msc_init();'/" ModSecurity-nginx/config

cd "nginx-$NGINX_VERSION"

# Upstream's patches first, in upstream's order and with upstream's rule for
# .txt patches, then ours. `patch` exits non-zero on a rejected hunk, which
# fails the build rather than shipping an unpatched binary.
for p in $(ls "$UPSTREAM/patches") ; do
  echo "Patch (upstream): $p"
  if [[ "$p" == *.txt ]]; then
    patch -p0 < "$UPSTREAM/patches/$p"
  else
    patch -p1 < "$UPSTREAM/patches/$p"
  fi
done
for p in $(ls "$EXTRA_PATCHES") ; do
  echo "Patch (extra): $p"
  patch -p1 < "$EXTRA_PATCHES/$p"
done

export LUAJIT_LIB=/usr/local/lib
export LUAJIT_INC=/usr/local/include/luajit-2.1

eval ./configure "$CONFIGURE_ARGS"

# Only the binary. The dynamic modules have to be configured, since they are
# part of the configure line, but the image already carries them and none of
# the patches touch them; --with-compat keeps them loadable.
make -j"$(nproc)" -f objs/Makefile binary

BUILT_ARGS=$(objs/nginx -V 2>&1 | sed -n 's/^configure arguments: //p')
if [[ "$BUILT_ARGS" != "$CONFIGURE_ARGS" ]]; then
  echo "configure arguments differ from the shipped binary" >&2
  diff <(echo "$CONFIGURE_ARGS" | tr ' ' '\n') <(echo "$BUILT_ARGS" | tr ' ' '\n') >&2 || true
  exit 1
fi

install -m 0755 objs/nginx /nginx
