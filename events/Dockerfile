ARG BUILDPATH='/build'

# multi-stage build -> start w. golang:1.18-alpine for build
FROM golang:1.18-alpine as builder

ARG BUILDPATH

# build the sse listener into a binary -> ~300MB
COPY ./rclistener/ $BUILDPATH
RUN cd $BUILDPATH/cmd && go build -o rcl

# create final image - export go binary onto regular alpine -> ~18mb
FROM alpine:latest

ARG BUILDPATH
COPY --from=builder $BUILDPATH/cmd/rcl /bin/rcl