# Set repository on Docker Registry (or DockerHub)
REPOSITORY ?= kikkomep/kube-openmpi

# Set CentOS Base Image
CENTOS_REPOSITORY ?= centos
CENTOS_TAG ?= centos7
CENTOS_BASED_BASE_IMAGE ?= $(CENTOS_REPOSITORY):$(CENTOS_TAG)

# Set OpenMPI version
OPENMPI_VERSION ?= 1.10.7
KUBE_OPENMPI_VERSION ?= 0.7.0

# Args for SSH Uer embedded in container images
SSH_USER ?= openmpi
SSH_UID ?= 1000
SSH_GID ?= 1000

# Args for WRF Base Image
WRF_BASE_IMAGE ?= $(REPOSITORY):wrf_base

# Args for WRF Initializer Image
WRF_INITIALIZER_IMAGE ?= $(REPOSITORY):wrf_initializer

# Args for WRF Kube OpenMPI Image
WRF_VERSION ?= 4.0.3
CMODE ?= 35
NEST ?= 1
WRF_KUBE_OPENMPI_IMAGE ?= $(REPOSITORY):wrf_$(WRF_VERSION)-$(OPENMPI_VERSION)-$(CENTOS_TAG)-$(KUBE_OPENMPI_VERSION)
WRF_KUBE_OPENMPI_IMAGE_ALIAS_1 ?= $(REPOSITORY):wrf_$(WRF_VERSION)


# Args for WRF Writer Image
HADOOP_CLIENT_VERSION ?= 3.2.0-ubuntu
WRF_WRITER_BASE_IMAGE ?= crs4/hadoopclient:$(HADOOP_CLIENT_VERSION)
TILEDB_VERSION ?= 1.6.0
TILEDB_PY_VERSION ?= 0.4.3
WRF_WRITER_IMAGE ?= $(REPOSITORY):wrf_writer_$(HADOOP_CLIENT_VERSION)-$(TILEDB_VERSION)-$(TILEDB_PY_VERSION)


.PHONY: build
build: wrf_base_image wrf_initializer_image wrf_kube_openmpi_image wrf_writer_image


wrf_base_image:
	docker build \
	  --build-arg CENTOS_BASED_BASE_IMAGE=$(CENTOS_BASED_BASE_IMAGE) \
	  --build-arg WRF_VERSION=$(WRF_VERSION) \
		-t $(WRF_BASE_IMAGE) \
		-f wrf-base.Dockerfile \
		.

wrf_initializer_image: wrf_base_image
	docker build \
	  --build-arg WRF_BASE_IMAGE=$(WRF_BASE_IMAGE) \
		-t $(WRF_INITIALIZER_IMAGE) \
		-f wrf-initializer.Dockerfile \
		.

wrf_kube_openmpi_image:
	docker build \
		--build-arg WRF_BASE_IMAGE=$(WRF_BASE_IMAGE) \
		--build-arg OPENMPI_VERSION=$(OPENMPI_VERSION) \
		--build-arg CMODE=$(CMODE) \
		--build-arg NEST=$(NEST) \
		--build-arg SSH_USER=$(SSH_USER) \
		--build-arg SSH_UID=$(SSH_UID) \
		--build-arg SSH_GID=$(SSH_GID) \
		-t $(WRF_KUBE_OPENMPI_IMAGE) \
		-f wrf-kube-openmpi.Dockerfile \
		. && \
		docker tag $(WRF_KUBE_OPENMPI_IMAGE) $(WRF_KUBE_OPENMPI_IMAGE_ALIAS_1)


wrf_writer_image:
	cd writer && \
	docker build \
		--build-arg WRF_WRITER_BASE_IMAGE=$(WRF_WRITER_BASE_IMAGE) \
		--build-arg WRF_WRITER_BASE_IMAGE=$(WRF_WRITER_BASE_IMAGE) \
		--build-arg TILEDB_VERSION=$(TILEDB_VERSION) \
		--build-arg TILEDB_PY_VERSION=$(TILEDB_PY_VERSION) \
		-t $(WRF_WRITER_IMAGE) \
		-f Dockerfile \
		.


publish:
	docker push $(WRF_BASE_IMAGE)	
	docker push $(WRF_INITIALIZER_IMAGE)
	docker push $(WRF_KUBE_OPENMPI_IMAGE) && docker push $(WRF_KUBE_OPENMPI_IMAGE_ALIAS_1)
	docker push $(WRF_WRITER_IMAGE)
