# Description

This build of the NGINX Ingress controller is built with:

* [kubernetes/ingress-nginx@controller-v1.11.2](https://github.com/kubernetes/ingress-nginx/tree/controller-v1.11.2) ([permalink](https://github.com/kubernetes/ingress-nginx/tree/d3bb2b4f8757816f1d7c6268e02e433887373a3b)).
* [Lua modules](./etc/nginx/lua) for exporting metrics and for geohashing ([source](https://github.com/deckhouse/deckhouse/tree/49744cd7e11f86aacf493be4dec391901348ddda/modules/402-ingress-nginx/images/controller-1-10/rootfs/etc/nginx/lua)).
* A patched `nginx.conf` [template](./etc/nginx/template/nginx.tmpl). The patch is based on [deckhouse/deckhouse@91482468](https://raw.githubusercontent.com/deckhouse/deckhouse/91482468489526bc59623bd7fbd31228cd6a6b22/modules/402-ingress-nginx/images/controller-1-10/patches/nginx-tmpl.patch) sans the HTTP3 features.
* [kubernetes/ingress-nginx#11843](./patches/11843.diff) ([source](https://github.com/kubernetes/ingress-nginx/pull/11843)).
* A [backport](./patches/13068.diff) for [CVE-2025-1974](https://github.com/advisories/GHSA-mgvx-rpfc-9mpv) and friends ([source](https://github.com/kubernetes/ingress-nginx/pull/13068)). Parts of this patch are already included in [`etc/nginx/template/nginx.tmpl`](./etc/nginx/template/nginx.tmpl). Patches for test files are omitted.
