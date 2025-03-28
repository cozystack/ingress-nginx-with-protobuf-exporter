.PHONY=update
update:
	mv images/protobuf-exporter/Dockerfile images.protobuf-exporter.Dockerfile && \
	rm -rf images/protobuf-exporter && \
	DIR=$$(mktemp -d) && \
	git clone -n --depth=1 --filter=tree:0 https://github.com/deckhouse/deckhouse "$$DIR" && \
	git -C "$$DIR" sparse-checkout set --no-cone modules/402-ingress-nginx/images && \
	git -C "$$DIR" checkout && \
	mkdir images/protobuf-exporter && \
	cp -r $$DIR/modules/402-ingress-nginx/images/protobuf-exporter/src/* ./images/protobuf-exporter/ && \
	cp -r $$DIR/modules/402-ingress-nginx/images/protobuf-exporter/rootfs ./images/protobuf-exporter/ && \
	rm -rf "$$DIR" && \
	git checkout images/protobuf-exporter/rootfs/var/files/telemetry_config.yml && \
	mv images.protobuf-exporter.Dockerfile images/protobuf-exporter/Dockerfile
