package main

import (
	"context"
	"fmt"
	"net"
	"os"
	"panagiotisptr/ping-pong/ping/proto"

	"go.uber.org/fx"
	"go.uber.org/fx/fxevent"
	"go.uber.org/zap"
	"google.golang.org/grpc"
	"google.golang.org/grpc/reflection"
)

type PingServer struct {
	logger     *zap.Logger
	pongClient proto.PongClient
	proto.UnimplementedPingServer
}

func (s *PingServer) Call(ctx context.Context, req *proto.CallRequest) (*proto.CallResponse, error) {
	s.logger.Sugar().Info("Called count")

	resp, err := s.pongClient.GetCount(ctx, &proto.GetCountRequest{})
	if err != nil {
		return nil, err
	}

	return &proto.CallResponse{
		Count: resp.GetCount(),
	}, nil
}

func ProvidePongClient(
	lc fx.Lifecycle,
) (proto.PongClient, error) {
	pongConn, err := grpc.Dial(
		os.Getenv("PONG_SERVICE_ADDRESS"),
		grpc.WithInsecure(),
	)
	if err != nil {
		return nil, err
	}

	lc.Append(fx.Hook{
		OnStop: func(ctx context.Context) error {
			return pongConn.Close()
		},
	})

	return proto.NewPongClient(pongConn), nil
}

func ProvidePingServer(
	logger *zap.Logger,
	pongClient proto.PongClient,
) *PingServer {
	return &PingServer{
		logger: logger.With(
			zap.String("service", "ping"),
		),
		pongClient: pongClient,
	}
}

// Provides the GRPC server instance
func ProvideGRPCServer(
	s *PingServer,
) (*grpc.Server, error) {
	gs := grpc.NewServer()
	proto.RegisterPingServer(gs, s)
	reflection.Register(gs)

	return gs, nil
}

// Provides the ZAP logger
func ProvideLogger() *zap.Logger {
	logger, _ := zap.NewProduction()

	return logger
}

func Bootstrap(
	lc fx.Lifecycle,
	gs *grpc.Server,
	logger *zap.Logger,
) {
	logger.Sugar().Info("Starting ping service")
	lc.Append(fx.Hook{
		OnStart: func(ctx context.Context) error {
			logger.Sugar().Info("Starting GRPC server.")

			addr := fmt.Sprintf(":%s", os.Getenv("SERVICE_PORT"))
			list, err := net.Listen("tcp", addr)
			if err != nil {
				return err
			} else {
				logger.Sugar().Info("Listening on " + addr)
			}

			go gs.Serve(list)

			return nil
		},
		OnStop: func(ctx context.Context) error {
			logger.Sugar().Info("Stopping GRPC server.")
			gs.Stop()

			return logger.Sync()
		},
	})
}

func main() {
	app := fx.New(
		fx.Provide(
			ProvideLogger,
			ProvidePongClient,
			ProvidePingServer,
			ProvideGRPCServer,
		),
		fx.Invoke(Bootstrap),
		fx.WithLogger(
			func(logger *zap.Logger) fxevent.Logger {
				return &fxevent.ZapLogger{Logger: logger}
			},
		),
	)

	app.Run()
}
