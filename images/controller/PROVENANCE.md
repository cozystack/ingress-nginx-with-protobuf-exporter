# Description

This build of the NGINX Ingress controller is built with:

* [kubernetes/ingress-nginx@controller-v1.11.5](https://github.com/kubernetes/ingress-nginx/tree/controller-v1.11.5) ([permalink](https://github.com/kubernetes/ingress-nginx/tree/795b6964d3cbcdebf5c857faca12750d76158920)).
* [Lua modules](./etc/nginx/lua) for exporting metrics and for geohashing ([source](https://github.com/deckhouse/deckhouse/tree/49744cd7e11f86aacf493be4dec391901348ddda/modules/402-ingress-nginx/images/controller-1-10/rootfs/etc/nginx/lua)).
* A patched `nginx.conf` [template](./etc/nginx/template/nginx.tmpl). The patch is based on [deckhouse/deckhouse@91482468](https://raw.githubusercontent.com/deckhouse/deckhouse/91482468489526bc59623bd7fbd31228cd6a6b22/modules/402-ingress-nginx/images/controller-1-10/patches/nginx-tmpl.patch) sans the HTTP3 features. Dropping those is not cosmetic: `buildHTTP3Listener` is a deckhouse-only template function, and `text/template` fails at parse time on an unknown function, so keeping the blocks would break config rendering outright even with `UseHTTP3` off.
* [kubernetes/ingress-nginx#11843](./patches/11843.diff) ([source](https://github.com/kubernetes/ingress-nginx/pull/11843)).
* An nginx binary rebuilt with [backported security fixes](./nginx/patches), described below.

## The rebuilt nginx

`kubernetes/ingress-nginx` was archived in March 2026, so no further 1.11.x controller image will be published and the nginx 1.25.5 inside it would otherwise stay as released. The `nginx` stage of the Dockerfile compiles that nginx again and the binary replaces `/usr/local/nginx/sbin/nginx` in the upstream image; nothing else in the image changes.

Reproducing the binary rather than reinventing it is the point, so [`nginx/build.sh`](./nginx/build.sh) takes every input from upstream at the same controller tag: the module versions from `images/nginx/rootfs/build.sh`, the OpenResty patch set from `images/nginx/rootfs/patches`, and the configure line from `nginx -V` of the shipped binary itself, which already carries the per-architecture flags. It runs on the upstream controller image, so the binary links against the LuaJIT and libmodsecurity already there, and the build fails if the configure arguments of the result differ from the shipped ones. Only the binary is rebuilt: the dynamic modules in the image are untouched by the patches and stay loadable through `--with-compat`.

The patches in `nginx/patches` are applied after upstream's, and each is the upstream nginx commit unchanged, taken from the 1.30 stable branch:

| Patch | nginx commit | Fixes |
| --- | --- | --- |
| `32_nginx-1.25.5-http2-reusable-connection-stream.patch` | [`0c87dd1d`](https://github.com/nginx/nginx/commit/0c87dd1db413e440a4e3ef7ee8acc518509e8809) | CVE-2026-123633, HTTP/2 use-after-free when `worker_connections` run out |
| `33_nginx-1.25.5-http2-window-update-queued.patch` | [`b89c4100`](https://github.com/nginx/nginx/commit/b89c4100bf6762a45e4a6463eaf4b70368277c94) | CVE-2026-123007, HTTP/2 flow control window overflow |
| `34_nginx-1.25.5-request-body-again.patch` | [`1b723277`](https://github.com/nginx/nginx/commit/1b723277aa556ba4c6e40cc8f0f0b465e29c0a13) | CVE-2026-118899, endless loop while reading a request body over SSL |
| `35_nginx-1.25.5-http3-request-body-again.patch` | [`d1640655`](https://github.com/nginx/nginx/commit/d1640655f46c5a2d32fefc2c818583f203e47536) | CVE-2026-118899, the same for HTTP/3 |
| `36_nginx-1.25.5-resolver-cname-restart-failure.patch` | [`338f6231`](https://github.com/nginx/nginx/commit/338f6231e347c17a07c381802b1bc3c20c55b529) | CVE-2026-123634, resolver use-after-free, with the next patch |
| `37_nginx-1.25.5-resolver-non-current-finalization.patch` | [`7426c29f`](https://github.com/nginx/nginx/commit/7426c29f140c330dd6c6cdfeb2943be1978c69e0) | CVE-2026-123634, resolver use-after-free |
| `38_nginx-1.25.5-quic-main-connection-reuse.patch` | [`c58d2a22`](https://github.com/nginx/nginx/commit/c58d2a22d12350766185c94f2245bf4be5bcfb7d) | CVE-2026-121810, HTTP/3 use-after-free when `worker_connections` run out |
| `39_nginx-1.25.5-try-files-script-underwrite.patch` | [`b99b6b52`](https://github.com/nginx/nginx/commit/b99b6b528b64e93354b5c3453e45701e70c461a8) | CVE-2026-125283, buffer overflow with `try_files` and `alias` |

All were released in nginx 1.30.7 and 1.31.9. Patches 34-39 apply in the order of the stable branch, after 32 and 33 from the first rebuild (on stable-1.30, 33 comes after 37, but it touches only HTTP/2 files), all at line offsets. Patch 39 alone needs fuzz 1: 1.25.5 lacks the `ngx_http_script_check_length` block that nginx 1.30.4 added next to it in 326b17b0, so it fixes the underwrite case only, without the overrun protection that commit brought. The condition behind CVE-2026-123633 dates from nginx 1.19.7. The other fixes of 1.30.7 are left out: the mail module is not built, and the controller's template uses neither SSL in the stream module nor `ssl_preread`. `nginx -V` still reports 1.25.5, since that is the code base; the image tag carries the rebuild suffix instead.

Image tags are the upstream controller version, with a `-cozystack.N` suffix for a rebuild of that version: `v1.11.6-cozystack.1` is upstream v1.11.6 with patches 32 and 33, `v1.11.6-cozystack.2` with all of the above. The workflow strips the suffix to pick what it builds.

## Notes on the 1.11.2 → 1.11.5 move

The `build-v1.11.2` branch carried an extra patch, [`13068.diff`](https://github.com/kubernetes/ingress-nginx/pull/13068), backporting the fix for [CVE-2025-1974](https://github.com/advisories/GHSA-mgvx-rpfc-9mpv) and friends onto 1.11.2. That patch is dropped here because 1.11.5 already contains the fix upstream — it no longer applies to this tree.

The template needed no edit at all. On 1.11.2 the `| quote` hardening of `CertificateAuth.MatchCN`, `externalAuth.URL` and `Mirror.Source` was carried here by hand; 1.11.5 ships it upstream. Regenerating the file from the 1.11.5 template plus the deckhouse patch reproduces the vendored one byte for byte, which is a useful check in both directions: the hardening is now inherited rather than maintained locally, and the vendored file is confirmed to be exactly upstream-plus-patch with nothing else in it.

`11843.diff` is vendored rather than fetched at build time. The upstream pull request is still open, so a `wget` of its `.diff` would let the build change under us without any commit here; the controller is built with `enable-ssl-passthrough`, which is exactly what that patch fixes for fragmented ClientHello.

The builder image is `golang:1.24-alpine`: 1.11.5 declares `go 1.24.1` in its `go.mod`, where 1.11.2 declared `go 1.22.6`.

## Regenerating the vendored template

`make update` refreshes the deckhouse inputs — the Lua modules and `patches/nginx-tmpl.patch` — but it does not produce `etc/nginx/template/nginx.tmpl`; that file is vendored by hand, as it was on `build-v1.11.2`. To rebuild it for a new upstream version, take that version's `rootfs/etc/nginx/template/nginx.tmpl`, apply `patches/nginx-tmpl.patch`, and then delete the three HTTP3 blocks it introduces (two `buildHTTP3Listener` calls and the `Alt-Svc` header). The deletion is required, not optional — see the note on HTTP3 above.
