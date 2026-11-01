SHELL := /bin/bash

CHARTS_DIR := charts
CHARTS     := $(notdir $(wildcard $(CHARTS_DIR)/*))
RELEASE    := test-release

BIN_DIR := .bin

# Tool pins. Each *_CHECKSUMS_SHA256 is the sha256 of that release's published
# checksums file; scripts/fetch-verified.sh checks the file against it, then the
# downloaded asset against the file. Bump the version and the hash together:
#   curl -fsSL <checksums-url> | sha256sum
OS   := $(shell uname -s | tr '[:upper:]' '[:lower:]')
ARCH := $(shell uname -m | sed -e 's/x86_64/amd64/' -e 's/aarch64/arm64/')

KUBECONFORM_VERSION          := v0.8.0
KUBECONFORM_CHECKSUMS_SHA256 := 235fc6d8801ca0b6dba3ff3d49b8751e27c7ec92f4414fe052b283ec50cca0af
KUBECONFORM_RELEASE          := https://github.com/yannh/kubeconform/releases/download/$(KUBECONFORM_VERSION)
KUBECONFORM_DIR              := $(BIN_DIR)/kubeconform-$(KUBECONFORM_VERSION)
KUBECONFORM                  := $(KUBECONFORM_DIR)/kubeconform

HELM_UNITTEST_VERSION          := 1.1.2
HELM_UNITTEST_CHECKSUMS_SHA256 := 978de67c89f5f92894bf56b8994dcb90dd659dece9bca9caa2a3a4f744cd0f6e
HELM_UNITTEST_RELEASE          := https://github.com/helm-unittest/helm-unittest/releases/download/v$(HELM_UNITTEST_VERSION)
HELM_UNITTEST_OS               := $(subst darwin,macos,$(OS))
HELM_UNITTEST_ASSET            := helm-unittest-$(HELM_UNITTEST_OS)-$(ARCH)-$(HELM_UNITTEST_VERSION).tgz

BASE                  ?= origin/main
HELM_CHART            ?=
HELM_UNITTEST_FILE    ?= tests/**/*.yaml

ifeq ($(strip $(HELM_CHART)),)
UNITTEST_CHARTS := $(CHARTS)
else
UNITTEST_CHARTS := $(HELM_CHART)
endif

.PHONY: help lint template kubeconform validate helm-unittest-plugin helm-unittest test check-version package clean $(CHARTS)

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

lint: ## helm lint every chart (same as CI's "Lint Helm charts" step)
	@for c in $(CHARTS); do \
		echo "==> helm lint $(CHARTS_DIR)/$$c"; \
		if [ "$$c" = "common" ]; then \
			helm lint $(CHARTS_DIR)/$$c || exit 1; \
			helm lint -f $(CHARTS_DIR)/$$c/ci/ingress-values.yaml $(CHARTS_DIR)/$$c || exit 1; \
		elif [ "$$c" = "firstdime-helm" ]; then \
			helm lint -f $(CHARTS_DIR)/$$c/ci/test-values.yaml $(CHARTS_DIR)/$$c || exit 1; \
			helm lint -f $(CHARTS_DIR)/$$c/ci/test-values.yaml -f $(CHARTS_DIR)/$$c/ci/frankfurter-values.yaml $(CHARTS_DIR)/$$c || exit 1; \
			helm lint -f $(CHARTS_DIR)/$$c/ci/test-values.yaml -f $(CHARTS_DIR)/$$c/ci/bank-sync-values.yaml $(CHARTS_DIR)/$$c || exit 1; \
		elif [ -f $(CHARTS_DIR)/$$c/ci/test-values.yaml ]; then \
			helm lint -f $(CHARTS_DIR)/$$c/ci/test-values.yaml $(CHARTS_DIR)/$$c || exit 1; \
		else \
			helm lint $(CHARTS_DIR)/$$c || exit 1; \
		fi; \
	done

template: ## helm template every chart (same as CI's "Template Helm charts" step)
	@for c in $(CHARTS); do \
		echo "==> helm template $(CHARTS_DIR)/$$c"; \
		if [ "$$c" = "common" ]; then \
			helm template $(RELEASE) $(CHARTS_DIR)/$$c --values $(CHARTS_DIR)/$$c/values.yaml > /dev/null || exit 1; \
			helm template $(RELEASE) $(CHARTS_DIR)/$$c --values $(CHARTS_DIR)/$$c/values.yaml --values $(CHARTS_DIR)/$$c/ci/ingress-values.yaml > /dev/null || exit 1; \
		elif [ "$$c" = "firstdime-helm" ]; then \
			helm template $(RELEASE) $(CHARTS_DIR)/$$c --values $(CHARTS_DIR)/$$c/ci/test-values.yaml > /dev/null || exit 1; \
			helm template $(RELEASE) $(CHARTS_DIR)/$$c --values $(CHARTS_DIR)/$$c/ci/test-values.yaml --values $(CHARTS_DIR)/$$c/ci/frankfurter-values.yaml > /dev/null || exit 1; \
			helm template $(RELEASE) $(CHARTS_DIR)/$$c --values $(CHARTS_DIR)/$$c/ci/test-values.yaml --values $(CHARTS_DIR)/$$c/ci/bank-sync-values.yaml > /dev/null || exit 1; \
		elif [ -f $(CHARTS_DIR)/$$c/ci/test-values.yaml ]; then \
			helm template $(RELEASE) $(CHARTS_DIR)/$$c --values $(CHARTS_DIR)/$$c/ci/test-values.yaml > /dev/null || exit 1; \
		else \
			helm template $(RELEASE) $(CHARTS_DIR)/$$c --values $(CHARTS_DIR)/$$c/values.yaml > /dev/null || exit 1; \
		fi; \
	done

# The versioned directory makes a version bump re-download; .bin/kubeconform is
# a symlink to the current one so CI can put .bin/ on PATH.
$(KUBECONFORM):
	@echo "==> Installing kubeconform $(KUBECONFORM_VERSION) to $(KUBECONFORM_DIR) (checksum-verified)"
	@scripts/fetch-verified.sh $(KUBECONFORM_RELEASE)/CHECKSUMS $(KUBECONFORM_CHECKSUMS_SHA256) \
		$(KUBECONFORM_RELEASE)/kubeconform-$(OS)-$(ARCH).tar.gz $(KUBECONFORM_DIR)/kubeconform.tar.gz
	@tar xzf $(KUBECONFORM_DIR)/kubeconform.tar.gz -C $(KUBECONFORM_DIR) kubeconform
	@rm $(KUBECONFORM_DIR)/kubeconform.tar.gz
	@ln -sfn kubeconform-$(KUBECONFORM_VERSION)/kubeconform $(BIN_DIR)/kubeconform

kubeconform: $(KUBECONFORM) ## Install the pinned kubeconform into .bin/ (checksum-verified)

validate: $(KUBECONFORM) ## Validate rendered manifests against Kubernetes schemas via kubeconform (same as CI)
	@for c in $(CHARTS); do \
		echo "==> kubeconform $(CHARTS_DIR)/$$c"; \
		if [ "$$c" = "common" ]; then \
			helm template $(RELEASE) $(CHARTS_DIR)/$$c --values $(CHARTS_DIR)/$$c/values.yaml | $(KUBECONFORM) -summary || exit 1; \
			helm template $(RELEASE) $(CHARTS_DIR)/$$c --values $(CHARTS_DIR)/$$c/values.yaml --values $(CHARTS_DIR)/$$c/ci/ingress-values.yaml | $(KUBECONFORM) -summary || exit 1; \
		elif [ "$$c" = "firstdime-helm" ]; then \
			helm template $(RELEASE) $(CHARTS_DIR)/$$c --values $(CHARTS_DIR)/$$c/ci/test-values.yaml | $(KUBECONFORM) -summary || exit 1; \
			helm template $(RELEASE) $(CHARTS_DIR)/$$c --values $(CHARTS_DIR)/$$c/ci/test-values.yaml --values $(CHARTS_DIR)/$$c/ci/frankfurter-values.yaml | $(KUBECONFORM) -summary || exit 1; \
			helm template $(RELEASE) $(CHARTS_DIR)/$$c --values $(CHARTS_DIR)/$$c/ci/test-values.yaml --values $(CHARTS_DIR)/$$c/ci/bank-sync-values.yaml | $(KUBECONFORM) -summary || exit 1; \
		elif [ -f $(CHARTS_DIR)/$$c/ci/test-values.yaml ]; then \
			helm template $(RELEASE) $(CHARTS_DIR)/$$c --values $(CHARTS_DIR)/$$c/ci/test-values.yaml | $(KUBECONFORM) -summary || exit 1; \
		else \
			helm template $(RELEASE) $(CHARTS_DIR)/$$c --values $(CHARTS_DIR)/$$c/values.yaml | $(KUBECONFORM) -summary || exit 1; \
		fi; \
	done

# Unpacks the checksum-verified release tarball straight into Helm's plugin
# directory instead of `helm plugin install`: the git install runs a hook that
# downloads the binary itself, and the release ships no provenance for the
# per-platform tarball. Skips (with a note on a version mismatch) when a
# unittest plugin is already installed, since two would conflict.
helm-unittest-plugin: ## Install the pinned helm-unittest plugin (checksum-verified) if none is installed
	@installed=$$(helm plugin list 2>/dev/null | awk '$$1 == "unittest" { print $$2 }'); \
	if [ -n "$$installed" ]; then \
		[ "$$installed" = "$(HELM_UNITTEST_VERSION)" ] || \
			echo "note: helm-unittest $$installed is installed; CI uses $(HELM_UNITTEST_VERSION)"; \
	else \
		dir="$$(helm env HELM_PLUGINS)/helm-unittest"; \
		echo "==> Installing helm-unittest $(HELM_UNITTEST_VERSION) to $$dir (checksum-verified)"; \
		scripts/fetch-verified.sh $(HELM_UNITTEST_RELEASE)/helm-unittest-checksum.sha $(HELM_UNITTEST_CHECKSUMS_SHA256) \
			$(HELM_UNITTEST_RELEASE)/$(HELM_UNITTEST_ASSET) $(BIN_DIR)/$(HELM_UNITTEST_ASSET) && \
		mkdir -p "$$dir" && tar xzf $(BIN_DIR)/$(HELM_UNITTEST_ASSET) -C "$$dir" && \
		rm $(BIN_DIR)/$(HELM_UNITTEST_ASSET) && \
		helm plugin list | grep -q '^unittest' || exit 1; \
	fi

helm-unittest: helm-unittest-plugin ## Run helm-unittest for every chart, or one via HELM_CHART=<name> (same as CI)
	@for c in $(UNITTEST_CHARTS); do \
		echo "==> helm unittest $(CHARTS_DIR)/$$c"; \
		helm unittest $(CHARTS_DIR)/$$c --file '$(HELM_UNITTEST_FILE)' || exit 1; \
	done

test: lint template validate helm-unittest ## Run every check the lint-test CI workflow runs

check-version: ## Fail if a changed chart's version was not bumped (BASE=origin/main; CI runs it on PRs)
	@scripts/check-version-bump.sh $(BASE)

package: ## helm package every chart
	@for c in $(CHARTS); do \
		helm package $(CHARTS_DIR)/$$c; \
	done

clean: ## Remove downloaded tools and packaged charts
	rm -rf $(BIN_DIR)
	rm -f *.tgz
