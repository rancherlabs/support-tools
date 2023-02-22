package ports

import (
	"context"
)

type EBSCSIUseCases interface {
	Enable(ctx context.Context, input *EnableInput) (*EnableOutput, error)
}

type EnableInput struct {
	ClusterName        string
	RancherKubeconfig  string
	EBSAddonVersion    string
	ExplicitCreds      bool
	AWSAccessKeyID     string
	AWSAccessKeySecret string
}

type EnableOutput struct {
}
