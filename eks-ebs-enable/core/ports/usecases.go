package ports

import (
	"context"
)

type EBSCSIUseCases interface {
	Enable(ctx context.Context, input *EnableInput) (*EnableOutput, error)
}

type EnableInput struct {
	ClusterName       string
	RancherKubeconfig string
	EBSAddonVersion   string
}

type EnableOutput struct {
}
