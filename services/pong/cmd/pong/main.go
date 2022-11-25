package main

import (
	"context"
	"fmt"
	"net"
	"os"
	"panagiotisptr/ping-pong/pong/proto"

	"go.uber.org/fx"
	"go.uber.org/fx/fxevent"
	"go.uber.org/zap"
	"google.golang.org/grpc"
	"google.golang.org/grpc/reflection"
)

type PongServer struct {
	logger *zap.Logger
	proto.UnimplementedPongServer
}

var count int64 = 0

func (s *PongServer) GetCount(context.Context, *proto.GetCountRequest) (*proto.GetCountResponse, error) {
	count += 1
	s.logger.Sugar().Info("Called count")

	return &proto.GetCountResponse{
		Count: count,
	}, nil
}

func ProvidePongServer(
	logger *zap.Logger,
) *PongServer {
	return &PongServer{
		logger: logger.With(
			zap.String("service", "pong"),
		),
	}
}

// Provides the GRPC server instance
func ProvideGRPCServer(
	s *PongServer,
) (*grpc.Server, error) {
	gs := grpc.NewServer()
	proto.RegisterPongServer(gs, s)
	reflection.Register(gs)

	return gs, nil
}

// Provides the ZAP logger
func ProvideLogger() *zap.Logger {
	logger, _ := zap.NewProduction()

	return logger
}

// Bootstraps the application
func Bootstrap(
	lc fx.Lifecycle,
	gs *grpc.Server,
	logger *zap.Logger,
) {
	logger.Sugar().Info("Starting pong service")
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
			ProvidePongServer,
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
