.PHONY=update
update:
	rm -rf images/protobuf-exporter && \
	rm -rf images/controller/lua images/controller/patches && \
	DIR=$$(mktemp -d) && \
	git clone -n --depth=1 --filter=tree:0 https://github.com/deckhouse/deckhouse "$$DIR" && \
	git -C "$$DIR" sparse-checkout set --no-cone modules/402-ingress-nginx/images && \
	git -C "$$DIR" checkout && \
	cp -r $$DIR/modules/402-ingress-nginx/images/controller-*/rootfs/etc/nginx/lua ./images/controller/ && \
	mkdir -p images/controller/patches && \
	cp $$DIR/modules/402-ingress-nginx/images/controller-*/patches/nginx-tmpl.patch ./images/controller/patches/ && \
	cp -r $$DIR/modules/402-ingress-nginx/images/protobuf-exporter ./images/ && \
	rm -rf "$$DIR" && \
	git checkout images/protobuf-exporter/rootfs/var/files/telemetry_config.yml && \
	sed -i images/protobuf-exporter/Dockerfile \
		-e 's|$$BASE_DISTROLESS|scratch|g' \
		-e 's|^.* as artifact$$|FROM golang:alpine3.16 as artifact|' \
		-e '/^ARG/d'
