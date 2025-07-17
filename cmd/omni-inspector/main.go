// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

// Package main implements a simple HTTP server.
package main

import (
	"context"
	"crypto/tls"
	"flag"
	"fmt"
	"log"
	"net"
	"net/http"
	"net/url"
	"os/signal"
	"slices"
	"syscall"
	"time"

	"github.com/cosi-project/runtime/pkg/safe"
	"github.com/cosi-project/runtime/pkg/state"
	gateway "github.com/grpc-ecosystem/grpc-gateway/v2/runtime"
	"github.com/siderolabs/go-api-signature/pkg/pgp"
	"github.com/siderolabs/go-api-signature/pkg/serviceaccount"
	"github.com/siderolabs/omni/client/api/omni/resources"
	"github.com/siderolabs/omni/client/pkg/access"
	"github.com/siderolabs/omni/client/pkg/client"
	"github.com/siderolabs/omni/client/pkg/client/omni"
	"github.com/siderolabs/omni/client/pkg/constants"
	"github.com/siderolabs/omni/client/pkg/omni/resources/auth"
	"go.uber.org/zap"
	"golang.org/x/sync/errgroup"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/grpc/encoding/gzip"
	"google.golang.org/protobuf/encoding/protojson"

	"github.com/siderolabs/omni-inspector/internal/frontend"
	"github.com/siderolabs/omni-inspector/internal/pkg/clientconfig"
	"github.com/siderolabs/omni-inspector/internal/pkg/logging"
)

func main() {
	if err := run(); err != nil {
		log.Fatalf("server run failed %s", err)
	}

	log.Printf("the server was stopped gracefully")
}

func run() error {
	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer cancel()

	marshaller := &gateway.JSONPb{
		MarshalOptions: protojson.MarshalOptions{
			UseProtoNames:  true,
			UseEnumNumbers: true,
		},
	}

	runtimeMux := gateway.NewServeMux(
		gateway.WithMarshalerOption(gateway.MIMEWildcard, marshaller),
	)

	mux := http.NewServeMux()

	staticMux := frontend.NewStaticHandler(7200)

	mux.Handle("/api/", http.StripPrefix("/api", runtimeMux))
	mux.Handle("/", staticMux)

	var (
		serviceAccount string
		opts           []client.Option
	)

	envKey, valueBase64 := serviceaccount.GetFromEnv()
	if envKey != "" {
		sa, saErr := serviceaccount.Decode(valueBase64)
		if saErr != nil {
			return saErr
		}

		serviceAccount = sa.Name

		opts = append(opts, client.WithServiceAccount(valueBase64))
	}

	loggerCfg := zap.NewDevelopmentConfig()
	loggerCfg.Development = false

	logger, err := loggerCfg.Build()
	if err != nil {
		return err
	}

	if serviceAccount == "" {
		serviceAccount, err = createServiceAccount(ctx, logger)
		if err != nil {
			return err
		}

		opts = append(opts, client.WithServiceAccount(serviceAccount))
	}

	opts = append(opts, client.WithOmniClientOptions(omni.WithRetryLogger(logger)))

	conn, err := initConnection(omniEndpoint,
		opts...,
	)
	if err != nil {
		return err
	}

	if err := resources.RegisterResourceServiceHandler(ctx, runtimeMux, conn); err != nil {
		return err
	}

	eg, ctx := errgroup.WithContext(ctx)

	gatewayServer := &http.Server{
		Addr:    "localhost:12000",
		Handler: logging.NewHandler(mux),
	}

	eg.Go(func() error {
		return gatewayServer.ListenAndServe()
	})

	log.Printf("the API server is running on the address 0.0.0.0:12000")

	<-ctx.Done()

	if err := gatewayServer.Shutdown(ctx); err != nil {
		return fmt.Errorf("HTTP server shutdown failed %w", err)
	}

	return nil
}

func initConnection(endpoint string, opts ...client.Option) (*grpc.ClientConn, error) {
	u, err := url.Parse(endpoint)
	if err != nil {
		return nil, err
	}

	if u.Port() == "" && u.Scheme == "https" {
		u.Host = net.JoinHostPort(u.Host, "443")
	}

	if u.Scheme == "http" {
		u.Scheme = "grpc"
	}

	if u.Port() == "" && u.Scheme == "grpc" {
		u.Host = net.JoinHostPort(u.Host, "80")
	}

	var (
		options         client.Options
		grpcDialOptions []grpc.DialOption
	)

	for _, opt := range opts {
		opt(&options)
	}

	if options.AuthInterceptor != nil {
		grpcDialOptions = append(grpcDialOptions,
			grpc.WithUnaryInterceptor(options.AuthInterceptor.Unary()),
			grpc.WithStreamInterceptor(options.AuthInterceptor.Stream()))
	}

	grpcDialOptions = slices.Concat(grpcDialOptions, options.AdditionalGRPCDialOptions)

	switch u.Scheme {
	case "https":
		grpcDialOptions = append(grpcDialOptions, grpc.WithTransportCredentials(credentials.NewTLS(&tls.Config{
			InsecureSkipVerify: options.InsecureSkipTLSVerify,
		})))
	default:
		grpcDialOptions = append(grpcDialOptions, grpc.WithTransportCredentials(insecure.NewCredentials()))
	}

	grpcDialOptions = append(grpcDialOptions,
		grpc.WithDefaultCallOptions(
			grpc.MaxCallRecvMsgSize(constants.GRPCMaxMessageSize),
			grpc.UseCompressor(gzip.Name),
		),
		grpc.WithSharedWriteBuffer(true),
	)

	return grpc.NewClient(u.Host, grpcDialOptions...)
}

var omniEndpoint string

func init() {
	flag.StringVar(&omniEndpoint, "endpoint", "https://localhost:8099", "Omni endpoint")
}

func createServiceAccount(ctx context.Context, logger *zap.Logger) (serviceAccountKey string, err error) {
	config := clientconfig.New(omniEndpoint)

	rootClient, err := config.GetClient()
	if err != nil {
		return "", err
	}

	defer rootClient.Close() //nolint:errcheck

	name := "omni-inspector"

	sa := access.ParseServiceAccountFromName(name)

	key, err := pgp.GenerateKey(sa.BaseName, "", sa.FullID(), 365*24*time.Hour)
	if err != nil {
		return "", err
	}

	armoredPublicKey, err := key.ArmorPublic()
	if err != nil {
		return "", err
	}

	serviceAccountKey, err = serviceaccount.Encode(name, key)
	if err != nil {
		return "", err
	}

	identity, err := safe.ReaderGetByID[*auth.Identity](ctx, rootClient.Omni().State(), sa.FullID())
	if err != nil && !state.IsNotFoundError(err) {
		return "", err
	}

	if identity != nil {
		logger.Info("delete service account")

		err = rootClient.Management().DestroyServiceAccount(ctx, name)
		if err != nil {
			return "", err
		}
	}

	// create service account with the generated key
	_, err = rootClient.Management().CreateServiceAccount(ctx, name, armoredPublicKey, "Admin", false)

	return serviceAccountKey, err
}
