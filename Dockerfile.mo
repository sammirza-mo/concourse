# syntax=docker/dockerfile:1

# Production image for MO's Concourse fork.
#
# This is the official concourse/concourse:${CONCOURSE_VERSION} image with *only* the
# `concourse` binary replaced by one built from this tree, which adds the
# `gcpsecretmanager` credential manager. Web assets, resource types, fly assets and the
# containerd `init` binary are inherited unchanged from the upstream release, so the
# result is "${CONCOURSE_VERSION} + GSM creds" and nothing else.
#
# Upstream's own Dockerfile is dev-only (it volume-mounts source); do not use it here.

ARG CONCOURSE_VERSION=8.3.0
ARG GO_VERSION=1.26

FROM --platform=$BUILDPLATFORM golang:${GO_VERSION} AS build

WORKDIR /src

# Modules first, so a source-only change does not re-download the module graph.
COPY go.mod go.sum ./
RUN go mod download

COPY . .

ARG CONCOURSE_VERSION
ARG TARGETOS
ARG TARGETARCH

# CGO is not required: ./cmd/concourse builds fully static.
#
# 2026-09-22: Version is injected via ldflags because versions.go defaults it to
# "0.0.0-dev". It is set to the plain upstream version (no fork suffix) so that semver
# parsing, fly's version check and the UI all behave exactly as on stock 8.3.0 -- fork
# provenance is carried by the image tag instead. WorkerVersion is a source constant and
# is deliberately NOT touched, which is what keeps the existing 8.3.0 workers compatible.
RUN CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} \
      go build -trimpath \
        -ldflags "-X github.com/concourse/concourse.Version=${CONCOURSE_VERSION}" \
        -o /out/concourse \
        ./cmd/concourse

FROM concourse/concourse:${CONCOURSE_VERSION}

COPY --from=build /out/concourse /usr/local/concourse/bin/concourse
