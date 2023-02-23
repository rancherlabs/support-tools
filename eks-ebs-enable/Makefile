BIN_DIR := .bin

export PATH := $(abspath $(BIN_DIR)):$(PATH)

GO_INSTALL := ./scripts/go-install.sh

$(BIN_DIR):
	mkdir -p $@

SYFT_VER := v0.73.0
SYFT_BIN := syft
SYFT := $(abspath $(BIN_DIR)/$(SYFT_BIN))
SYFT_PKG := github.com/anchore/syft/cmd/syft

GORELEASER_VER := v1.15.2
GORELEASER_BIN := goreleaser
GORELEASER := $(abspath $(BIN_DIR)/$(GORELEASER_BIN))
GORELEASER_PKG := github.com/goreleaser/goreleaser

SYFT := $(BIN_DIR)/syft
GORELEASER := $(BIN_DIR)/goreleaser

.PHONY: release-local
release-local: $(SYFT) $(GORELEASER)
	$(GORELEASER) release --snapshot --clean

.PHONY: $(SYFT_BIN)
$(SYFT_BIN): $(SYFT) ## Build a local copy of syft.

.PHONY: $(GORELEASER_BIN)
$(GORELEASER_BIN): $(GORELEASER) ## Build a local copy of goreleaser.

$(SYFT): # Build syft from bin folder.
	CGO_ENABLED=0 GOBIN=$(abspath $(BIN_DIR)) $(GO_INSTALL) $(SYFT_PKG) $(SYFT_BIN) $(SYFT_VER)

$(GORELEASER): # Build goreleaser from bin folder.
	CGO_ENABLED=0 GOBIN=$(abspath $(BIN_DIR)) $(GO_INSTALL) $(GORELEASER_PKG) $(GORELEASER_BIN) $(GORELEASER_VER)


