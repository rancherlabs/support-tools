package plan

import (
	"context"
	"errors"
	"fmt"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/awserr"
	"github.com/aws/aws-sdk-go/service/eks"
	"github.com/aws/aws-sdk-go/service/eks/eksiface"
	"github.com/rancherlabs/support-tools/eks-ebs-enable/planner"
)

func NewAWSEKSCreateEBSAddonStep(plan *enableEBSPlan) planner.Procedure {
	return &awsEKSCreateEBSAddonStep{
		plan: plan,
	}
}

type awsEKSCreateEBSAddonStep struct {
	plan *enableEBSPlan
}

func (s *awsEKSCreateEBSAddonStep) Name() string {
	return "aws_eks_create_ebs_addon"
}

func (s *awsEKSCreateEBSAddonStep) Do(ctx context.Context) ([]planner.Procedure, error) {
	if s.plan.AccessKey == "" || s.plan.SecretKey == "" {
		return nil, fmt.Errorf("expect aws access key and secret to be set")
	}
	if s.plan.DriverRoleARN == "" {
		return nil, fmt.Errorf("expected driver role arn")
	}
	if !s.plan.EBSPolicyAttachedToRole {
		return nil, errors.New("expected ebs policy to be attached to role")
	}
	ports := s.plan.Ports

	eksClient, err := ports.AWS.EKS(s.plan.AccessKey, s.plan.SecretKey, s.plan.EKSDetails.Region)
	if err != nil {
		return nil, fmt.Errorf("getting EKS client: %w", err)
	}

	installedARN, err := s.installedAddon(ctx, s.plan.ClusterName, eksClient)
	if err != nil {
		return nil, fmt.Errorf("checking if ebs addon is installed: %w", err)
	}

	if installedARN == "" {
		installedARN, err = s.installEBSAddon(ctx, s.plan.ClusterName, s.plan.EBSAddonVersion, eksClient)
		if err != nil {
			return nil, fmt.Errorf("installing ebs addon: %w", err)
		}
	}

	s.plan.EBSAddonARN = installedARN
	return nil, nil
}

func (s *awsEKSCreateEBSAddonStep) installedAddon(ctx context.Context, clusterName string, eksSvc eksiface.EKSAPI) (string, error) {
	output, err := eksSvc.DescribeAddonWithContext(ctx, &eks.DescribeAddonInput{
		AddonName:   aws.String(ebsAddonName),
		ClusterName: &clusterName,
	})
	if err != nil {
		if aerr, ok := err.(awserr.Error); ok {
			if aerr.Code() == eks.ErrCodeResourceNotFoundException {
				return "", nil
			}
		}
		return "", fmt.Errorf("getting ebs addon for cluster: %w", err)
	}

	if output.Addon == nil {
		return "", nil
	}

	return *output.Addon.AddonArn, nil
}

func (s *awsEKSCreateEBSAddonStep) installEBSAddon(ctx context.Context, clusterName, version string, eksSvc eksiface.EKSAPI) (string, error) {
	input := &eks.CreateAddonInput{
		AddonName:             aws.String(ebsAddonName),
		ClusterName:           &clusterName,
		ServiceAccountRoleArn: &s.plan.DriverRoleARN,
	}
	if version != "latest" {
		input.AddonVersion = aws.String(version)
	}

	output, err := eksSvc.CreateAddonWithContext(ctx, input)
	if err != nil {
		return "", fmt.Errorf("creating ebs addon: %w", err)
	}

	return *output.Addon.AddonArn, nil
}
