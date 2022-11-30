FROM golang:1.19-alpine

RUN apk add --no-cache git
RUN apk add --no-cache protoc
RUN apk add --no-cache make
RUN go install google.golang.org/protobuf/cmd/protoc-gen-go@latest
RUN go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest

# copy proto files needed by this service
WORKDIR $GOPATH/github.com/panagiotisptr/ping-pong/services/pong
ADD https://raw.githubusercontent.com/PanagiotisPtr/ping-pong/main/services/pong/pong.proto .

WORKDIR $GOPATH/github.com/panagiotisptr/ping-pong/services/ping

COPY . .

RUN make protos

RUN go mod tidy

RUN go build -o ping cmd/ping/main.go

ENTRYPOINT [ "./ping" ]
