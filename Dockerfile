# Build the manager binary
FROM golang:1.17 as builder

WORKDIR /

COPY bin/manager /manager

ENTRYPOINT ["/manager"]
