
# Image URL to use all building/pushing image targets
IMG ?= controller:latest
# ENVTEST_K8S_VERSION refers to the version of kubebuilder assets to be downloaded by envtest binary.
ENVTEST_K8S_VERSION = 1.23

# Get the currently used golang install path (in GOPATH/bin, unless GOBIN is set)
ifeq (,$(shell go env GOBIN))
GOBIN=$(shell go env GOPATH)/bin
else
GOBIN=$(shell go env GOBIN)
endif

SAMPLES_DIR="${PWD}/config/samples"

# Setting SHELL to bash allows bash commands to be executed by recipes.
# This is a requirement for 'setup-envtest.sh' in the test target.
# Options are set to exit when a recipe line exits non-zero or a piped command fails.
SHELL = /usr/bin/env bash -o pipefail
.SHELLFLAGS = -ec

.PHONY: all
all: build

##@ General

# The help target prints out all targets with their descriptions organized
# beneath their categories. The categories are represented by '##@' and the
# target descriptions by '##'. The awk commands is responsible for reading the
# entire set of makefiles included in this invocation, looking for lines of the
# file as xyz: ## something, and then pretty-format the target and help. Then,
# if there's a line with ##@ something, that gets pretty-printed as a category.
# More info on the usage of ANSI control characters for terminal formatting:
# https://en.wikipedia.org/wiki/ANSI_escape_code#SGR_parameters
# More info on the awk command:
# http://linuxcommand.org/lc3_adv_awk.php

.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Development

.PHONY: manifests
manifests: controller-gen ## Generate WebhookConfiguration, ClusterRole and CustomResourceDefinition objects.
	$(CONTROLLER_GEN) rbac:roleName=manager-role crd webhook paths="./..." output:crd:artifacts:config=config/crd/bases

.PHONY: generate
generate: controller-gen ## Generate code containing DeepCopy, DeepCopyInto, and DeepCopyObject method implementations.
	$(CONTROLLER_GEN) object:headerFile="hack/boilerplate.go.txt" paths="./..."

.PHONY: fmt
fmt: ## Run go fmt against code.
	go fmt ./...

.PHONY: vet
vet: ## Run go vet against code.
	go vet ./...

.PHONY: test
test: manifests generate fmt vet envtest ## Run tests.
	KUBEBUILDER_ASSETS="$(shell $(ENVTEST) use $(ENVTEST_K8S_VERSION) -p path)" go test ./... -coverprofile cover.out

##@ Build

.PHONY: build
build: generate fmt vet ## Build manager binary.
	go build -o bin/manager main.go

.PHONY: run
run: manifests generate fmt vet ## Run a controller from your host.
	go run ./main.go

.PHONY: docker-build
docker-build: test ## Build docker image with the manager.
	docker build -t ${IMG} .

.PHONY: docker-push
docker-push: ## Push docker image with the manager.
	docker push ${IMG}

##@ Deployment

ifndef ignore-not-found
  ignore-not-found = false
endif

.PHONY: install
install: manifests kustomize ## Install CRDs into the K8s cluster specified in ~/.kube/config.
	$(KUSTOMIZE) build config/crd | kubectl apply -f -

.PHONY: uninstall
uninstall: manifests kustomize ## Uninstall CRDs from the K8s cluster specified in ~/.kube/config. Call with ignore-not-found=true to ignore resource not found errors during deletion.
	$(KUSTOMIZE) build config/crd | kubectl delete --ignore-not-found=$(ignore-not-found) -f -

.PHONY: deploy
deploy: manifests kustomize ## Deploy controller to the K8s cluster specified in ~/.kube/config.
	cd config/manager && $(KUSTOMIZE) edit set image controller=${IMG}
	$(KUSTOMIZE) build config/default | kubectl apply -f -

.PHONY: undeploy
undeploy: ## Undeploy controller from the K8s cluster specified in ~/.kube/config. Call with ignore-not-found=true to ignore resource not found errors during deletion.
	$(KUSTOMIZE) build config/default | kubectl delete --ignore-not-found=$(ignore-not-found) -f -

CONTROLLER_GEN = $(shell pwd)/bin/controller-gen
.PHONY: controller-gen
controller-gen: ## Download controller-gen locally if necessary.
	$(call go-get-tool,$(CONTROLLER_GEN),sigs.k8s.io/controller-tools/cmd/controller-gen@v0.8.0)

KUSTOMIZE = $(shell pwd)/bin/kustomize
.PHONY: kustomize
kustomize: ## Download kustomize locally if necessary.
	$(call go-get-tool,$(KUSTOMIZE),sigs.k8s.io/kustomize/kustomize/v3@v3.8.7)

ENVTEST = $(shell pwd)/bin/setup-envtest
.PHONY: envtest
envtest: ## Download envtest-setup locally if necessary.
	$(call go-get-tool,$(ENVTEST),sigs.k8s.io/controller-runtime/tools/setup-envtest@latest)

# go-get-tool will 'go get' any package $2 and install it to $1.
PROJECT_DIR := $(shell dirname $(abspath $(lastword $(MAKEFILE_LIST))))
define go-get-tool
@[ -f $(1) ] || { \
set -e ;\
TMP_DIR=$$(mktemp -d) ;\
cd $$TMP_DIR ;\
go mod init tmp ;\
echo "Downloading $(2)" ;\
GOBIN=$(PROJECT_DIR)/bin go get $(2) ;\
rm -rf $$TMP_DIR ;\
}
endef

.PHONY: install-helm-consul
install-helm-consul:
	helm install consul hashicorp/consul --values ${SAMPLES_DIR}/helm-consul-values.yml

.PHONY: uninstall-helm-consul
uninstall-helm-consul:
	helm uninstall consul

.PHONY: install-helm-vault
install-helm-vault:
	helm install vault hashicorp/vault --values ${SAMPLES_DIR}/helm-vault-values.yml

.PHONY: uninstall-helm-vault
uninstall-helm-vault:
	helm uninstall vault

.PHONY: port-forwarding
port-forwarding:
	kubectl port-forward vault-0 8200:8200

.PHONY: initialize-vault
initialize-vault:
	kubectl exec vault-0 -- vault operator init -key-shares=1 -key-threshold=1 -format=json > ${SAMPLES_DIR}/cluster-keys.json

.PHONY: unseal-vault
unseal-vault:
	export VAULT_UNSEAL_KEY=$$(cat ${SAMPLES_DIR}/cluster-keys.json | jq -r ".unseal_keys_b64[]") && \
	kubectl exec vault-0 -- vault operator unseal ${VAULT_UNSEAL_KEY}

.PHONY: apply-serviceaccount
apply-serviceaccount:
	kubectl apply -f ${SAMPLES_DIR}/serviceaccount.yaml

.PHONY: auth-to-vault
auth-to-vault:
	export VAULT_ADDR="https://0.0.0.0:8200/" && \
	export VAULT_TOKEN=$$(cat ${SAMPLES_DIR}/cluster-keys.json | jq ".root_token" -r) && \
	vault auth enable kubernetes && \
	VAULT_SECRET_NAME=$$(kubectl get serviceaccount vault-auth -o json | jq ".secrets[0].name" -r) && \
	export KUBE_HOST=$$(kubectl config view --raw --minify --flatten --output="jsonpath={.clusters[].cluster.server}") && \
	kubectl get secret ${VAULT_SECRET_NAME} -o json | jq '.data["ca.crt"]' -r | base64 -d > ca.crt && \
	vault write auth/kubernetes/config \
		token_reviewer_jwt="$(kubectl get secret ${VAULT_SECRET_NAME} -o json | jq .data.token -r | base64 -d)" \
		kubernetes_host=${KUBE_HOST} \
		kubernetes_ca_cert=@ca.crt


.PHONY: write-vault-policy
write-vault-policy:
	vault write sys/policy/mypolicy policy=@${SAMPLES_DIR}/policy.hcl
	vault write auth/kubernetes/role/vault-role \
	bound_service_account_names=vault-crd-serviceaccount \
	bound_service_account_namespaces=vault-crd \
	policies=mypolicy \
	ttl=1h

.PHONY: apply-vault-crd
apply-vault-crd:
	helm upgrade -i vault vault-crd-helm/vault-crd

.PHONY: apply-vault-secret
apply-vault-secret:
	kubectl apply -f ${SAMPLES_DIR}/vault-secret.yaml

