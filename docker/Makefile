KUBE_OPENMPI_VERSION ?= 0.7.0
REPOSITORY ?= kikkomep/kube-openmpi

OPENMPI_VERSION ?= 1.10.7

# Args for SSH Uer embedded in container images
SSH_USER ?= openmpi
SSH_UID ?= 1000
SSH_GID ?= 1000

# Args for CentOS Base Image
CENTOS_REPOSITORY ?= centos
CENTOS_TAG ?= centos7
CENTOS_BASED_BASE_IMAGE ?= $(CENTOS_REPOSITORY):$(CENTOS_TAG)
CENTOS_IMAGE ?= $(REPOSITORY):$(OPENMPI_VERSION)-$(CENTOS_TAG)-$(KUBE_OPENMPI_VERSION)
CENTOS_ALIAS ?= $(REPOSITORY):$(KUBE_OPENMPI_VERSION)

# Args for CentOS WRF Image
WRF_VERSION ?= 4.0.3
CMODE ?= 35
NEST ?= 1
CENTOS_WRF_IMAGE ?= $(REPOSITORY):wrf_$(WRF_VERSION)-$(OPENMPI_VERSION)-$(CENTOS_TAG)-$(KUBE_OPENMPI_VERSION)
CENTOS_WRF_ALIAS ?= $(REPOSITORY):wrf_$(WRF_VERSION)

.PHONY: build
build: centos_image centos_wrf_image

centos_image:
	docker build \
		--build-arg CENTOS_BASED_BASE_IMAGE=$(CENTOS_BASED_BASE_IMAGE) \
		--build-arg OPENMPI_VERSION=$(OPENMPI_VERSION) \
		--build-arg SSH_USER=$(SSH_USER) \
		--build-arg SSH_UID=$(SSH_UID) \
		--build-arg SSH_GID=$(SSH_GID) \
		-t $(CENTOS_IMAGE) \
		-f Dockerfile.kube-openmpi \
		. && \
		docker tag $(CENTOS_IMAGE) $(CENTOS_ALIAS)

centos_wrf_image:
	docker build \
		--build-arg CENTOS_OPENMPI_BASE_IMAGE=$(CENTOS_IMAGE) \
		--build-arg WRF_VERSION=$(WRF_VERSION) \
		--build-arg CMODE=$(CMODE) \
		--build-arg NEST=$(NEST) \
		-t $(CENTOS_WRF_IMAGE) \
		-f Dockerfile.kube-openmpi-wrf \
		. && \
		docker tag $(CENTOS_WRF_IMAGE) $(CENTOS_WRF_ALIAS)


publish:
	docker push $(CENTOS_IMAGE) && docker push $(CENTOS_ALIAS)
	docker push $(CENTOS_WRF_IMAGE) && docker push $(CENTOS_WRF_ALIAS)
