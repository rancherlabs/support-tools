BUILD_DATE := $(shell date +%Y-%m-%dT%H:%M:%SZ)
GIT_COMMIT := $(shell git rev-parse --short HEAD)

BIN_DIR := .bin

$(BIN_DIR):
	mkdir -p $@

WIRE := $(BIN_DIR)/wire

.PHONY: generate-di
generate-di: $(WIRE)
	$(WIRE) gen github.com/rancherlabs/support-tools/eks-ebs-enable/internal/inject

$(WIRE): $(BIN_DIR)
	cd $(BIN_DIR); go build -o wire github.com/google/wire/cmd/wire


