package plan

import (
	"context"
	"fmt"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/service/iam"
	"github.com/aws/aws-sdk-go/service/iam/iamiface"

	"github.com/rancherlabs/support-tools/eks-ebs-enable/planner"
)

func NewAWSIAMAttachEBSPolicyStep(plan *enableEBSPlan) planner.Procedure {
	return &awsIAMAttachEBSPolicyStep{
		plan: plan,
	}
}

type awsIAMAttachEBSPolicyStep struct {
	plan *enableEBSPlan
}

func (s *awsIAMAttachEBSPolicyStep) Name() string {
	return "aws_iam_attach_ebs_policy"
}

func (s *awsIAMAttachEBSPolicyStep) Do(ctx context.Context) ([]planner.Procedure, error) {
	if s.plan.AccessKey == "" || s.plan.SecretKey == "" {
		return nil, fmt.Errorf("expect aws access key and secret to be set")
	}
	if s.plan.DriverRoleARN == "" {
		return nil, fmt.Errorf("expected driver role arn")
	}

	ports := s.plan.Ports
	roleName := fmt.Sprintf(driverRoleNameFormat, s.plan.ClusterName)

	iamService, err := ports.AWS.IAM(s.plan.AccessKey, s.plan.SecretKey, s.plan.EKSDetails.Region)
	if err != nil {
		return nil, fmt.Errorf("getting IAM client: %w", err)
	}

	policyAttached, err := s.isPolicyAttached(ctx, roleName, iamService)
	if err != nil {
		return nil, fmt.Errorf("checking if EBS policy is attached to role: %w", err)
	}
	if policyAttached {
		s.plan.EBSPolicyAttachedToRole = true
		return nil, nil
	}

	if attachErr := s.attachEBSPolicy(ctx, roleName, iamService); attachErr != nil {
		return nil, fmt.Errorf("attaching ebs policy to role: %w", err)
	}

	s.plan.EBSPolicyAttachedToRole = true

	return nil, nil
}

func (s *awsIAMAttachEBSPolicyStep) isPolicyAttached(ctx context.Context, roleName string, iamService iamiface.IAMAPI) (bool, error) {
	output, err := iamService.ListAttachedRolePoliciesWithContext(ctx, &iam.ListAttachedRolePoliciesInput{
		RoleName: &roleName,
	})
	if err != nil {
		return false, fmt.Errorf("getting role %s: %w", roleName, err)
	}

	for _, policy := range output.AttachedPolicies {
		if *policy.PolicyArn == ebsPolicyARN {
			return true, nil
		}
	}

	return false, nil
}

func (s *awsIAMAttachEBSPolicyStep) attachEBSPolicy(ctx context.Context, roleName string, iamService iamiface.IAMAPI) error {
	_, err := iamService.AttachRolePolicyWithContext(ctx, &iam.AttachRolePolicyInput{
		RoleName:  &roleName,
		PolicyArn: aws.String(ebsPolicyARN),
	})
	if err != nil {
		return fmt.Errorf("attaching policy %s to role %s: %w", ebsPolicyARN, roleName, err)
	}

	return nil
}
