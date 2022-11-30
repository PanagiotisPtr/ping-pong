FROM golang:1.19-alpine

RUN apk add --no-cache git
RUN apk add --no-cache protoc
RUN apk add --no-cache make
RUN go install google.golang.org/protobuf/cmd/protoc-gen-go@latest
RUN go install google.golang.org/grpc/cmd/protoc-gen-go-grpc@latest

WORKDIR $GOPATH/github.com/panagiotisptr/ping-pong/services/pong

COPY . .

RUN make protos

RUN go mod tidy

RUN go build -o pong cmd/pong/main.go

ENTRYPOINT [ "./pong" ]
