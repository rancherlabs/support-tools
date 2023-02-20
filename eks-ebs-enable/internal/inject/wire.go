//go:build wireinject
// +build wireinject

package inject

import (
	"github.com/google/wire"
	"github.com/spf13/afero"

	"github.com/rancherlabs/support-tools/eks-ebs-enable/core/app"
	"github.com/rancherlabs/support-tools/eks-ebs-enable/core/ports"
	"github.com/rancherlabs/support-tools/eks-ebs-enable/infrastructure/aws"
	"github.com/rancherlabs/support-tools/eks-ebs-enable/infrastructure/rancher"
	"github.com/rancherlabs/support-tools/eks-ebs-enable/internal/config"
)

func CreateApp(cfg *config.Config) app.App {
	wire.Build(app.New,
		rancher.NewService,
		afero.NewOsFs,
		aws.NewService,
		rancherConfig,
		createPortsCollection)

	return nil
}

func createPortsCollection(rancherSvc ports.RancherService, fs afero.Fs, aws ports.AWSClientService) *ports.Collection {
	return &ports.Collection{
		Rancher:    rancherSvc,
		FileSystem: fs,
		AWS:        aws,
	}
}

func rancherConfig(cfg *config.Config) *config.RancherConfig {
	return &cfg.Rancher
}
