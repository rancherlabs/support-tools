package plan

import (
	"context"
	"errors"
	"fmt"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/service/eks"
	"github.com/rancherlabs/support-tools/eks-ebs-enable/planner"
)

func NewAWSEKSWaitAddonActiveStep(plan *enableEBSPlan) planner.Procedure {
	return &awsEKSWaitAddonActiveStep{
		plan: plan,
	}
}

type awsEKSWaitAddonActiveStep struct {
	plan *enableEBSPlan
}

func (s *awsEKSWaitAddonActiveStep) Name() string {
	return "aws_eks_wait_ebs_active"
}

func (s *awsEKSWaitAddonActiveStep) Do(ctx context.Context) ([]planner.Procedure, error) {
	if s.plan.AccessKey == "" || s.plan.SecretKey == "" {
		return nil, fmt.Errorf("expect aws access key and secret to be set")
	}
	if s.plan.EBSAddonARN == "" {
		return nil, errors.New("expected ebs addon arn")
	}
	ports := s.plan.Ports

	eksClient, err := ports.AWS.EKS(s.plan.AccessKey, s.plan.SecretKey, s.plan.EKSDetails.Region)
	if err != nil {
		return nil, fmt.Errorf("getting EKS client: %w", err)
	}

	if waitErr := eksClient.WaitUntilAddonActiveWithContext(ctx, &eks.DescribeAddonInput{
		AddonName:   aws.String(ebsAddonName),
		ClusterName: &s.plan.ClusterName,
	}); waitErr != nil {
		return nil, fmt.Errorf("waiting for ebs addon to be active: %w", err)
	}

	s.plan.EBSAddonActive = true

	return nil, nil
}
