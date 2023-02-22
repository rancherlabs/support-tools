package app

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path"

	"go.uber.org/zap"

	"github.com/rancherlabs/support-tools/eks-ebs-enable/core/plan"
	"github.com/rancherlabs/support-tools/eks-ebs-enable/core/ports"
	"github.com/rancherlabs/support-tools/eks-ebs-enable/planner"
)

func (a *app) Enable(ctx context.Context, input *ports.EnableInput) (*ports.EnableOutput, error) {
	logger := zap.S().With("cluster", input.ClusterName)
	logger.Info("enabling EBS CSI driver for EKS cluster")

	if input.RancherKubeconfig == "" {
		homeDir, err := os.UserHomeDir()
		if err != nil {
			return nil, fmt.Errorf("getting home directory: %w", err)
		}

		input.RancherKubeconfig = path.Join(homeDir, ".kube", "config")
		logger.Debugw("no rancher kubeconfig supplied, defaulting", "path", input.RancherKubeconfig)
	}

	if input.ExplicitCreds {
		if input.AWSAccessKeyID == "" {
			return nil, errors.New("aws access key id is required when using explicit creds")
		}
		if input.AWSAccessKeySecret == "" {
			return nil, errors.New("aws access key secret is required when using explicit creds")
		}
	}

	plan := plan.NewEnableEBSPlan(&plan.EnableEBSPlanInput{
		Ports:              a.ports,
		ClusterName:        input.ClusterName,
		RancherKubeconfig:  input.RancherKubeconfig,
		EBSAddonVersion:    input.EBSAddonVersion,
		AWSAccessKeyID:     input.AWSAccessKeyID,
		AWSAccessKeySecret: input.AWSAccessKeySecret,
	})

	manager := planner.NewManager(logger)
	numExecuted, err := manager.Execute(ctx, plan)
	if err != nil {
		return nil, fmt.Errorf("executing plan %s: %w", plan.Name(), err)
	}
	logger.Debugw("finished executing plan", "num_steps", numExecuted)

	logger.Info("finished enabling EBS CSI driver")

	return nil, nil
}
