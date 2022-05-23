MAJOR	 ?= 2
MINOR	 ?= 13
PATCH	 ?= 3
REVISION ?= 1

TAG	= ghcr.io/g0dscookie/icinga2
TAGLIST = -t ${TAG}:${MAJOR} -t ${TAG}:${MAJOR}.${MINOR} -t ${TAG}:${MAJOR}.${MINOR}.${PATCH}
BUILDARGS = --build-arg ICINGA2_VERSION=${MAJOR}.${MINOR}.${PATCH} --build-arg REVISION=${REVISION}

PLATFORM_FLAGS	= --platform linux/amd64 --platform linux/arm/v7
PUSH ?= --push

build:
	docker buildx build ${PUSH} ${PLATFORM_FLAGS} ${BUILDARGS} ${TAGLIST} .

latest: TAGLIST := -t ${TAG}:latest ${TAGLIST}
latest: build
.PHONY: build latest

amd64: PLATFORM_FLAGS := --platform linux/amd64
#amd64: BUILDARGS := --build-arg FLAVOR=debian ${BUILDARGS} --build-arg YQ_PLATFORM=amd64
amd64: build
amd64-latest: TAGLIST := -t ${TAG}:latest ${TAGLIST}
amd64-latest: amd64
.PHONY: amd64 amd64-latest

arm: PLATFORM_FLAGS := --platform linux/arm/v7
#arm: BUILDARGS := --build-arg FLAVOR=raspbian ${BUILDARGS} --build-arg YQ_PLATFORM=arm
arm: build
arm-latest: TAGLIST := -t ${TAG}:latest ${TAGLIST}
arm-latest: arm
.PHONY: arm arm-latest