package plan

import (
	"context"
	"fmt"

	"github.com/rancherlabs/support-tools/eks-ebs-enable/planner"
)

func NewRancherEKSDetailsStep(plan *enableEBSPlan) planner.Procedure {
	return &rancherEKSDetails{
		plan: plan,
	}
}

type rancherEKSDetails struct {
	plan *enableEBSPlan
}

func (s *rancherEKSDetails) Name() string {
	return "rancher_eks_details"
}

func (s *rancherEKSDetails) Do(ctx context.Context) ([]planner.Procedure, error) {
	details, err := s.plan.Ports.Rancher.GetClusterDetails(ctx, s.plan.ClusterName)
	if err != nil {
		return nil, fmt.Errorf("listing clusters in rancher: %w", err)
	}

	s.plan.EKSDetails = details

	return nil, nil
}
