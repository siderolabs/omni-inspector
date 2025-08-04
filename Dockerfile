# syntax = docker/dockerfile-upstream:1.17.1-labs

# THIS FILE WAS AUTOMATICALLY GENERATED, PLEASE DO NOT EDIT.
#
# Generated on 2025-08-04T15:09:58Z by kres 5fb5b90.

ARG JS_TOOLCHAIN
ARG TOOLCHAIN

# cleaned up specs and compiled versions
FROM scratch AS generate

FROM ghcr.io/siderolabs/ca-certificates:v1.10.0 AS image-ca-certificates

FROM ghcr.io/siderolabs/fhs:v1.10.0 AS image-fhs

# base toolchain image
FROM --platform=${BUILDPLATFORM} ${JS_TOOLCHAIN} AS js-toolchain
RUN apk --update --no-cache add bash curl protoc protobuf-dev go
COPY ./go.mod .
COPY ./go.sum .
ENV GOPATH=/go
ENV PATH=${PATH}:/usr/local/go/bin

# runs markdownlint
FROM docker.io/oven/bun:1.2.18-alpine AS lint-markdown
WORKDIR /src
RUN bun i markdownlint-cli@0.45.0 sentences-per-line@0.3.0
COPY .markdownlint.json .
COPY ./README.md ./README.md
RUN bunx markdownlint --ignore "CHANGELOG.md" --ignore "**/node_modules/**" --ignore '**/hack/chglog/**' --rules sentences-per-line .

# collects proto specs
FROM scratch AS proto-specs-frontend
ADD https://raw.githubusercontent.com/googleapis/googleapis/master/google/rpc/status.proto /frontend/src/api/google/rpc/
ADD https://raw.githubusercontent.com/cosi-project/specification/5c734257bfa6a3acb01417809797dbfbe0e73c71/proto/v1alpha1/resource.proto /frontend/src/api/v1alpha1/
ADD https://raw.githubusercontent.com/siderolabs/omni/b0f76343100033927a40ea0e604d5be8a84b3592/client/api/common/omni.proto /frontend/src/api/common/
ADD https://raw.githubusercontent.com/siderolabs/omni/b0f76343100033927a40ea0e604d5be8a84b3592/client/api/omni/resources/resources.proto /frontend/src/api/resources/

# base toolchain image
FROM --platform=${BUILDPLATFORM} ${TOOLCHAIN} AS toolchain
RUN apk --update --no-cache add bash curl build-base protoc protobuf-dev

# tools and sources
FROM --platform=${BUILDPLATFORM} js-toolchain AS js
WORKDIR /src
ARG PROTOBUF_GRPC_GATEWAY_TS_VERSION
RUN --mount=type=cache,target=/root/.cache/go-build,id=omni-inspector/root/.cache/go-build --mount=type=cache,target=/go/pkg,id=omni-inspector/go/pkg go install github.com/siderolabs/protoc-gen-grpc-gateway-ts@v${PROTOBUF_GRPC_GATEWAY_TS_VERSION}
RUN mv /go/bin/protoc-gen-grpc-gateway-ts /bin
COPY frontend/package.json ./
RUN --mount=type=cache,target=/src/node_modules,id=omni-inspector/src/node_modules,sharing=locked bun install
COPY frontend/tsconfig*.json ./
COPY frontend/bunfig.toml ./
COPY frontend/*.html ./
COPY frontend/*.ts ./
COPY frontend/*.js ./
COPY frontend/*.ico ./
COPY frontend/public ./
COPY ./frontend/src ./src
COPY ./frontend/test ./test
COPY ./frontend/eslint.config.js ./eslint.config.js
COPY ./frontend/postcss.config.js ./postcss.config.js
COPY ./frontend/vite.config.js ./vite.config.js

# build tools
FROM --platform=${BUILDPLATFORM} toolchain AS tools
ENV GO111MODULE=on
ARG CGO_ENABLED
ENV CGO_ENABLED=${CGO_ENABLED}
ARG GOTOOLCHAIN
ENV GOTOOLCHAIN=${GOTOOLCHAIN}
ARG GOEXPERIMENT
ENV GOEXPERIMENT=${GOEXPERIMENT}
ENV GOPATH=/go
ARG DEEPCOPY_VERSION
RUN --mount=type=cache,target=/root/.cache/go-build,id=omni-inspector/root/.cache/go-build --mount=type=cache,target=/go/pkg,id=omni-inspector/go/pkg go install github.com/siderolabs/deep-copy@${DEEPCOPY_VERSION} \
	&& mv /go/bin/deep-copy /bin/deep-copy
ARG GOLANGCILINT_VERSION
RUN --mount=type=cache,target=/root/.cache/go-build,id=omni-inspector/root/.cache/go-build --mount=type=cache,target=/go/pkg,id=omni-inspector/go/pkg go install github.com/golangci/golangci-lint/v2/cmd/golangci-lint@${GOLANGCILINT_VERSION} \
	&& mv /go/bin/golangci-lint /bin/golangci-lint
RUN --mount=type=cache,target=/root/.cache/go-build,id=omni-inspector/root/.cache/go-build --mount=type=cache,target=/go/pkg,id=omni-inspector/go/pkg go install golang.org/x/vuln/cmd/govulncheck@latest \
	&& mv /go/bin/govulncheck /bin/govulncheck
ARG GOFUMPT_VERSION
RUN go install mvdan.cc/gofumpt@${GOFUMPT_VERSION} \
	&& mv /go/bin/gofumpt /bin/gofumpt

# builds frontend
FROM --platform=${BUILDPLATFORM} js AS frontend
ARG JS_BUILD_ARGS
RUN --mount=type=cache,target=/src/node_modules,id=omni-inspector/src/node_modules bun run build ${JS_BUILD_ARGS}
RUN mkdir -p /internal/frontend/dist
RUN cp -rf ./dist/* /internal/frontend/dist

# runs eslint
FROM js AS lint-eslint
RUN --mount=type=cache,target=/src/node_modules,id=omni-inspector/src/node_modules bun run lint

# runs protobuf compiler
FROM js AS proto-compile-frontend
COPY --from=proto-specs-frontend / /
RUN protoc -I/frontend/src/api --grpc-gateway-ts_out=source_relative:/frontend/src/api --grpc-gateway-ts_opt=use_proto_names=true /frontend/src/api/google/rpc/status.proto
RUN protoc -I/frontend/src/api --grpc-gateway-ts_out=source_relative:/frontend/src/api --grpc-gateway-ts_opt=use_proto_names=true /frontend/src/api/v1alpha1/resource.proto
RUN protoc -I/frontend/src/api --grpc-gateway-ts_out=source_relative:/frontend/src/api --grpc-gateway-ts_opt=use_proto_names=true /frontend/src/api/common/omni.proto
RUN protoc -I/frontend/src/api --grpc-gateway-ts_out=source_relative:/frontend/src/api --grpc-gateway-ts_opt=use_proto_names=true /frontend/src/api/resources/resources.proto

# runs js unit-tests
FROM js AS unit-tests-frontend
RUN --mount=type=cache,target=/src/node_modules,id=omni-inspector/src/node_modules,sharing=locked bun add -d @happy-dom/global-registrator
RUN --mount=type=cache,target=/src/node_modules,id=omni-inspector/src/node_modules CI=true bun run test

# tools and sources
FROM tools AS base
WORKDIR /src
COPY go.mod go.mod
COPY go.sum go.sum
RUN cd .
RUN --mount=type=cache,target=/go/pkg,id=omni-inspector/go/pkg go mod download
RUN --mount=type=cache,target=/go/pkg,id=omni-inspector/go/pkg go mod verify
COPY ./api ./api
COPY ./cmd ./cmd
COPY ./internal ./internal
COPY --from=frontend /internal/frontend/dist ./internal/frontend/dist
RUN --mount=type=cache,target=/go/pkg,id=omni-inspector/go/pkg go list -mod=readonly all >/dev/null

# cleaned up specs and compiled versions
FROM scratch AS generate-frontend
COPY --from=proto-compile-frontend frontend/ frontend/

# runs gofumpt
FROM base AS lint-gofumpt
RUN FILES="$(gofumpt -l .)" && test -z "${FILES}" || (echo -e "Source code is not formatted with 'gofumpt -w .':\n${FILES}"; exit 1)

# runs golangci-lint
FROM base AS lint-golangci-lint
WORKDIR /src
COPY .golangci.yml .
ENV GOGC=50
RUN --mount=type=cache,target=/root/.cache/go-build,id=omni-inspector/root/.cache/go-build --mount=type=cache,target=/root/.cache/golangci-lint,id=omni-inspector/root/.cache/golangci-lint,sharing=locked --mount=type=cache,target=/go/pkg,id=omni-inspector/go/pkg golangci-lint run --config .golangci.yml

# runs govulncheck
FROM base AS lint-govulncheck
WORKDIR /src
RUN --mount=type=cache,target=/root/.cache/go-build,id=omni-inspector/root/.cache/go-build --mount=type=cache,target=/go/pkg,id=omni-inspector/go/pkg govulncheck ./...

# builds omni-inspector-linux-amd64
FROM base AS omni-inspector-linux-amd64-build
COPY --from=generate / /
WORKDIR /src/cmd/omni-inspector
ARG GO_BUILDFLAGS
ARG GO_LDFLAGS
RUN --mount=type=cache,target=/root/.cache/go-build,id=omni-inspector/root/.cache/go-build --mount=type=cache,target=/go/pkg,id=omni-inspector/go/pkg GOARCH=amd64 GOOS=linux go build ${GO_BUILDFLAGS} -ldflags "${GO_LDFLAGS}" -o /omni-inspector-linux-amd64

# builds omni-inspector-linux-arm64
FROM base AS omni-inspector-linux-arm64-build
COPY --from=generate / /
WORKDIR /src/cmd/omni-inspector
ARG GO_BUILDFLAGS
ARG GO_LDFLAGS
RUN --mount=type=cache,target=/root/.cache/go-build,id=omni-inspector/root/.cache/go-build --mount=type=cache,target=/go/pkg,id=omni-inspector/go/pkg GOARCH=arm64 GOOS=linux go build ${GO_BUILDFLAGS} -ldflags "${GO_LDFLAGS}" -o /omni-inspector-linux-arm64

# runs unit-tests with race detector
FROM base AS unit-tests-race
WORKDIR /src
ARG TESTPKGS
RUN --mount=type=cache,target=/root/.cache/go-build,id=omni-inspector/root/.cache/go-build --mount=type=cache,target=/go/pkg,id=omni-inspector/go/pkg --mount=type=cache,target=/tmp,id=omni-inspector/tmp CGO_ENABLED=1 go test -race ${TESTPKGS}

# runs unit-tests
FROM base AS unit-tests-run
WORKDIR /src
ARG TESTPKGS
RUN --mount=type=cache,target=/root/.cache/go-build,id=omni-inspector/root/.cache/go-build --mount=type=cache,target=/go/pkg,id=omni-inspector/go/pkg --mount=type=cache,target=/tmp,id=omni-inspector/tmp go test -covermode=atomic -coverprofile=coverage.txt -coverpkg=${TESTPKGS} ${TESTPKGS}

FROM scratch AS omni-inspector-linux-amd64
COPY --from=omni-inspector-linux-amd64-build /omni-inspector-linux-amd64 /omni-inspector-linux-amd64

FROM scratch AS omni-inspector-linux-arm64
COPY --from=omni-inspector-linux-arm64-build /omni-inspector-linux-arm64 /omni-inspector-linux-arm64

FROM scratch AS unit-tests
COPY --from=unit-tests-run /src/coverage.txt /coverage-unit-tests.txt

FROM omni-inspector-linux-${TARGETARCH} AS omni-inspector

FROM scratch AS omni-inspector-all
COPY --from=omni-inspector-linux-amd64 / /
COPY --from=omni-inspector-linux-arm64 / /

FROM scratch AS image-omni-inspector
ARG TARGETARCH
COPY --from=omni-inspector omni-inspector-linux-${TARGETARCH} /omni-inspector
COPY --from=image-fhs / /
COPY --from=image-ca-certificates / /
LABEL org.opencontainers.image.source=https://github.com/siderolabs/omni-inspector
ENTRYPOINT ["/omni-inspector"]

