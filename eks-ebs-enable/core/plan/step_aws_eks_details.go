package plan

import (
	"context"
	"errors"
	"fmt"

	"github.com/aws/aws-sdk-go/service/eks"
	"github.com/rancherlabs/support-tools/eks-ebs-enable/planner"
)

func NewAWSEKSDetailsStep(plan *enableEBSPlan) planner.Procedure {
	return &awsEKSDetailsStep{
		plan: plan,
	}
}

type awsEKSDetailsStep struct {
	plan *enableEBSPlan
}

func (s *awsEKSDetailsStep) Name() string {
	return "aws_eks_details"
}

func (s *awsEKSDetailsStep) Do(ctx context.Context) ([]planner.Procedure, error) {
	if s.plan.AccessKey == "" || s.plan.SecretKey == "" {
		return nil, fmt.Errorf("expect aws access key and secret to be set")
	}

	ports := s.plan.Ports

	eksClient, err := ports.AWS.EKS(s.plan.AccessKey, s.plan.SecretKey, s.plan.EKSDetails.Region)
	if err != nil {
		return nil, fmt.Errorf("getting EKS client: %w", err)
	}

	output, err := eksClient.DescribeClusterWithContext(ctx, &eks.DescribeClusterInput{
		Name: &s.plan.ClusterName,
	})
	if err != nil {
		return nil, fmt.Errorf("getting eks details from aws: %w", err)
	}

	if output.Cluster == nil {
		return nil, errors.New("EKS cluster not found")
	}

	s.plan.AWSEKSDetails = output.Cluster

	return nil, nil
}
