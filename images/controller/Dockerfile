ARG TAG

FROM golang:1.23-alpine as builder
ARG TAG=$TAG
RUN apk add --no-cache git make bash
RUN git clone --branch controller-${TAG} --depth 1 https://github.com/kubernetes/ingress-nginx /src
WORKDIR /src
RUN wget -O- https://github.com/kubernetes/ingress-nginx/pull/11843.diff | git apply -
RUN make build DOCKER_IN_DOCKER_ENABLED=true ARCH=amd64
RUN apk add --no-cache libcap
RUN setcap cap_net_bind_service+ep /src/rootfs/bin/amd64/nginx-ingress-controller

FROM registry.k8s.io/ingress-nginx/controller:$TAG

USER root

# required packages to build lua and run luarocks
RUN apk add --no-cache make gcc musl-dev

COPY lua/* /etc/nginx/lua/
COPY patches /patches

ARG LUA_ROCKS_VER="3.0.0"
RUN cd /tmp \
 && wget https://luarocks.org/releases/luarocks-${LUA_ROCKS_VER}.tar.gz \
 && tar zxf luarocks-${LUA_ROCKS_VER}.tar.gz \
 && cd luarocks-${LUA_ROCKS_VER} \
 && ./configure \
 && make build \
 && make install \
 && cd /tmp \
 && rm -rf /tmp/* \
 && mkdir -p /tmp/nginx && chown www-data: /tmp/nginx \
 && luarocks install lua-protobuf 0.4.1-1 \
 && luarocks install lua-iconv 7-3 \
 && patch /etc/nginx/template/nginx.tmpl < /patches/nginx-tmpl.patch

USER www-data

COPY --from=builder /src/rootfs/bin/amd64/nginx-ingress-controller /nginx-ingress-controller
