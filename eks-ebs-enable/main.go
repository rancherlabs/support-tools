package main

import (
	"fmt"
	"log"
	"os"

	"github.com/rancherlabs/support-tools/eks-ebs-enable/internal/commands"
	"go.uber.org/zap"
	"go.uber.org/zap/zapcore"
)

func main() {
	if err := setupLogging(); err != nil {
		log.Fatalf("failed to configure logging %v", err)
	}

	zap.S().Info("EBS CSI Driver Enabler for EKS")
	zap.S().Warn("ONLY USE AS DIRECTED BY SUSE SUPPORT")

	rootCmd := commands.NewRootCmd()

	if err := rootCmd.Execute(); err != nil {
		zap.S().Fatalw("failed running command", "error", err)
	}
}

func setupLogging() error {
	debug := false
	for _, arg := range os.Args {
		if arg == "--debug" {
			debug = true
			break
		}
	}

	logConfig := zap.NewProductionConfig()
	logConfig.Encoding = "console"
	logConfig.EncoderConfig.EncodeLevel = zapcore.CapitalColorLevelEncoder
	logConfig.EncoderConfig.TimeKey = ""
	logConfig.EncoderConfig.CallerKey = ""
	logConfig.EncoderConfig.EncodeTime = zapcore.ISO8601TimeEncoder

	if debug {
		logConfig.Level.SetLevel(zap.DebugLevel)
	} else {
		logConfig.Level.SetLevel(zap.InfoLevel)
	}

	logger, err := logConfig.Build()
	if err != nil {
		return fmt.Errorf("building logger: %w", err)
	}
	zap.ReplaceGlobals(logger)

	log.SetOutput(os.Stdout)
	log.SetFlags(0)

	return nil
}
