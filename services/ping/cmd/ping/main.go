package main

import (
	"context"
	"fmt"
	"net"
	"net/http"
	"os"
	"panagiotisptr/ping-pong/ping/proto"

	"go.elastic.co/ecszap"
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
	serviceAddress := os.Getenv("PONG_SERVICE_ADDRESS")
	if serviceAddress == "" {
		serviceAddress = "pong:80"
	}

	pongConn, err := grpc.Dial(
		serviceAddress,
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

func ProvideHTTPServer(
	s *PingServer,
) *http.ServeMux {
	mux := http.NewServeMux()

	mux.HandleFunc("/call", func(w http.ResponseWriter, r *http.Request) {
		res, err := s.Call(context.Background(), &proto.CallRequest{})
		if err != nil {
			w.Write([]byte(fmt.Sprintf("error: %v", err)))
		} else {
			w.Write([]byte(fmt.Sprintf("%d", res.GetCount())))
		}
	})

	return mux
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
	encoderConfig := ecszap.NewDefaultEncoderConfig()
	core := ecszap.NewCore(encoderConfig, os.Stdout, zap.DebugLevel)
	logger := zap.New(core, zap.AddCaller())

	return logger
}

func Bootstrap(
	lc fx.Lifecycle,
	gs *grpc.Server,
	mux *http.ServeMux,
	logger *zap.Logger,
) {
	logger.Sugar().Info("Starting ping service")
	lc.Append(fx.Hook{
		OnStart: func(ctx context.Context) error {
			logger.Sugar().Info("Starting GRPC server.")

			grpcPort := os.Getenv("SERVICE_GRPC_PORT")
			if grpcPort == "" {
				grpcPort = "80"
			}

			httpPort := os.Getenv("SERVICE_HTTP_PORT")
			if httpPort == "" {
				httpPort = "8888"
			}

			grpcAddr := fmt.Sprintf(":%s", grpcPort)
			list, err := net.Listen("tcp", grpcAddr)
			if err != nil {
				return err
			} else {
				logger.Sugar().Info("Listening on " + grpcAddr)
			}

			httpAddr := fmt.Sprintf(":%s", httpPort)
			go http.ListenAndServe(httpAddr, mux)

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
			ProvideHTTPServer,
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
