.PHONY: protos

setup:
	mkdir -p proto

pong_proto: setup
	cp ../pong/pong.proto proto/pong.proto && \
	protoc --go_out=proto --go_opt=paths=source_relative \
	--go-grpc_out=proto --go-grpc_opt=paths=source_relative \
	proto/pong.proto -I proto

protos: pong_proto
	protoc --go_out=proto --go_opt=paths=source_relative \
	--go-grpc_out=proto --go-grpc_opt=paths=source_relative \
	ping.proto
