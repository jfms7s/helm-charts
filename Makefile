SHELL := /bin/bash

CHARTS_DIR := charts
CHARTS     := $(notdir $(wildcard $(CHARTS_DIR)/*))
RELEASE    := test-release

BIN_DIR       := .bin
KUBECONFORM   := $(BIN_DIR)/kubeconform
KUBECONFORM_URL := https://github.com/yannh/kubeconform/releases/latest/download/kubeconform-linux-amd64.tar.gz

HELM_UNITTEST_VERSION := 1.1.2
HELM_CHART            ?=
HELM_UNITTEST_FILE    ?= tests/**/*.yaml

ifeq ($(strip $(HELM_CHART)),)
UNITTEST_CHARTS := $(CHARTS)
else
UNITTEST_CHARTS := $(HELM_CHART)
endif

.PHONY: help lint template validate helm-unittest-plugin helm-unittest test package clean $(CHARTS)

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

lint: ## helm lint every chart (same as CI's "Lint Helm charts" step)
	@for c in $(CHARTS); do \
		echo "==> helm lint $(CHARTS_DIR)/$$c"; \
		helm lint $(CHARTS_DIR)/$$c || exit 1; \
	done

template: ## helm template every chart (same as CI's "Template Helm charts" step)
	@for c in $(CHARTS); do \
		echo "==> helm template $(CHARTS_DIR)/$$c"; \
		helm template $(RELEASE) $(CHARTS_DIR)/$$c --values $(CHARTS_DIR)/$$c/values.yaml > /dev/null || exit 1; \
	done

$(KUBECONFORM):
	@mkdir -p $(BIN_DIR)
	@echo "==> Installing kubeconform to $(KUBECONFORM)"
	@curl -sSL $(KUBECONFORM_URL) | tar xz -C $(BIN_DIR) kubeconform

validate: $(KUBECONFORM) ## Validate rendered manifests against Kubernetes schemas via kubeconform (same as CI)
	@for c in $(CHARTS); do \
		echo "==> kubeconform $(CHARTS_DIR)/$$c"; \
		helm template $(RELEASE) $(CHARTS_DIR)/$$c --values $(CHARTS_DIR)/$$c/values.yaml | $(KUBECONFORM) -summary || exit 1; \
	done

helm-unittest-plugin: ## Install the helm-unittest plugin (pinned version below) if not already present
	@helm plugin list 2>/dev/null | grep -q '^unittest' || \
		helm plugin install https://github.com/helm-unittest/helm-unittest.git --version $(HELM_UNITTEST_VERSION) --verify=false

helm-unittest: helm-unittest-plugin ## Run helm-unittest for every chart, or one via HELM_CHART=<name> (same as CI)
	@for c in $(UNITTEST_CHARTS); do \
		echo "==> helm unittest $(CHARTS_DIR)/$$c"; \
		helm unittest $(CHARTS_DIR)/$$c --file '$(HELM_UNITTEST_FILE)' || exit 1; \
	done

test: lint template validate helm-unittest ## Run every check the lint-test CI workflow runs

package: ## helm package every chart
	@for c in $(CHARTS); do \
		helm package $(CHARTS_DIR)/$$c; \
	done

clean: ## Remove downloaded tools and packaged charts
	rm -rf $(BIN_DIR)
	rm -f *.tgz
