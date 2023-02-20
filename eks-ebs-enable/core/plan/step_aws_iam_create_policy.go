package plan

import (
	"bytes"
	"context"
	"fmt"
	"path"
	"text/template"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/arn"
	"github.com/aws/aws-sdk-go/aws/awserr"
	"github.com/aws/aws-sdk-go/service/iam"
	"github.com/aws/aws-sdk-go/service/iam/iamiface"

	"github.com/rancherlabs/support-tools/eks-ebs-enable/planner"
)

func NewAWSCreateEBSDriverRoleStep(plan *enableEBSPlan) planner.Procedure {
	return &awsIAMCreateEBSDriverRoleStep{
		plan: plan,
	}
}

type awsIAMCreateEBSDriverRoleStep struct {
	plan *enableEBSPlan
}

func (s *awsIAMCreateEBSDriverRoleStep) Name() string {
	return "aws_iam_create_ebs_role"
}

func (s *awsIAMCreateEBSDriverRoleStep) Do(ctx context.Context) ([]planner.Procedure, error) {
	if s.plan.AccessKey == "" || s.plan.SecretKey == "" {
		return nil, fmt.Errorf("expect aws access key and secret to be set")
	}
	if s.plan.OIDCProviderARN == "" {
		return nil, fmt.Errorf("expected oidc provider arn")
	}

	ports := s.plan.Ports
	roleName := fmt.Sprintf(driverRoleNameFormat, s.plan.ClusterName)

	iamService, err := ports.AWS.IAM(s.plan.AccessKey, s.plan.SecretKey, s.plan.EKSDetails.Region)
	if err != nil {
		return nil, fmt.Errorf("getting IAM client: %w", err)
	}

	roleArn, err := s.getDriverRole(ctx, roleName, iamService)
	if err != nil {
		return nil, fmt.Errorf("getting ebs driver role: %w", err)
	}
	if roleArn == "" {
		roleArn, err = s.createDriverRole(ctx, roleName, iamService)
		if err != nil {
			return nil, fmt.Errorf("creating ebs driver role: %w", err)
		}
	}

	s.plan.DriverRoleARN = roleArn

	return nil, nil
}

func (s *awsIAMCreateEBSDriverRoleStep) createDriverRole(ctx context.Context, roleName string, iamService iamiface.IAMAPI) (string, error) {
	providerID := path.Base(s.plan.OIDCProviderARN)
	parsedARN, err := arn.Parse(s.plan.OIDCProviderARN)
	if err != nil {
		return "", fmt.Errorf("parsing provider arn: %w", err)
	}

	templateData := struct {
		Region     string
		ProviderID string
		AccountID  string
	}{
		Region:     s.plan.EKSDetails.Region,
		ProviderID: providerID,
		AccountID:  parsedARN.AccountID,
	}
	tmpl, err := template.New("ebsrole").Parse(driverRoleTemplate)
	if err != nil {
		return "", fmt.Errorf("parsing ebs role template: %w", err)
	}
	buf := &bytes.Buffer{}
	if execErr := tmpl.Execute(buf, templateData); execErr != nil {
		return "", fmt.Errorf("executing ebs role template: %w", err)
	}

	output, err := iamService.CreateRoleWithContext(ctx, &iam.CreateRoleInput{
		RoleName:                 &roleName,
		AssumeRolePolicyDocument: aws.String(buf.String()),
	})
	if err != nil {
		return "", fmt.Errorf("creating role %s: %w", roleName, err)
	}

	return *output.Role.Arn, nil
}

func (s *awsIAMCreateEBSDriverRoleStep) getDriverRole(ctx context.Context, roleName string, iamService iamiface.IAMAPI) (string, error) {
	output, err := iamService.GetRoleWithContext(ctx, &iam.GetRoleInput{
		RoleName: &roleName,
	})
	if err != nil {
		if isNotFound(err) {
			return "", nil
		}

		return "", fmt.Errorf("getting roles %s: %w", roleName, err)
	}

	if output.Role == nil {
		return "", nil
	}

	return *output.Role.Arn, nil
}

func isNotFound(err error) bool {
	if aerr, ok := err.(awserr.Error); ok {
		switch aerr.Code() {
		case iam.ErrCodeNoSuchEntityException:
			return true
		default:
			return false
		}
	}

	return false
}
