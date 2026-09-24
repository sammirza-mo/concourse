# syntax=docker/dockerfile:1

# Production image for MO's Concourse fork.
#
# The official concourse/concourse:${CONCOURSE_VERSION} image with the `concourse`
# binary replaced by one built from this tree, which adds the `gcpsecretmanager`
# credential manager. Resource types, fly assets and the containerd `init` binary are
# inherited unchanged from the upstream release.
#
# The web UI is NOT inherited: web/handler.go go:embeds web/public into the binary, so
# the official image's UI lives inside the official binary this image replaces. The
# compiled bundles (elm.min.js, main.css, bundle.js) are gitignored build output, so
# they must be built here before `go build` — without them web serves a blank page.
#
# Upstream's own Dockerfile is dev-only (it volume-mounts source); do not use it here.

ARG CONCOURSE_VERSION=8.3.0
ARG GO_VERSION=1.26
ARG NODE_VERSION=22

# 2026-09-24: amd64 regardless of the build host because the elm npm package ships no
# linux/arm64 compiler. The output is platform-independent JS/CSS, so this only costs
# emulation time on an arm64 build host.
FROM --platform=linux/amd64 node:${NODE_VERSION} AS web

WORKDIR /src
RUN corepack enable

COPY package.json yarn.lock .yarnrc.yml ./
RUN yarn install --immutable

COPY . .
RUN yarn build \
 && test -s web/public/elm.min.js \
 && test -s web/public/main.css \
 && test -s web/public/bundle.js

FROM --platform=$BUILDPLATFORM golang:${GO_VERSION} AS build

WORKDIR /src

# Modules first, so a source-only change does not re-download the module graph.
COPY go.mod go.sum ./
RUN go mod download

COPY . .
COPY --from=web /src/web/public/ ./web/public/

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
