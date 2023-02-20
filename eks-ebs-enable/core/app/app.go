package app

import (
	"github.com/rancherlabs/support-tools/eks-ebs-enable/core/ports"
)

type App interface {
	ports.EBSCSIUseCases
}

func New(ports *ports.Collection) App {
	return &app{
		ports: ports,
	}
}

type app struct {
	ports *ports.Collection
}
