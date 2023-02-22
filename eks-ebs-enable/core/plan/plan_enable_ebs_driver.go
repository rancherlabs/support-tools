package plan

import (
	"context"

	"go.uber.org/zap"

	"github.com/aws/aws-sdk-go/service/eks"
	"github.com/rancherlabs/support-tools/eks-ebs-enable/core/models"
	"github.com/rancherlabs/support-tools/eks-ebs-enable/core/ports"
	"github.com/rancherlabs/support-tools/eks-ebs-enable/planner"
)

type EnableEBSPlanInput struct {
	RancherKubeconfig  string
	ClusterName        string
	EBSAddonVersion    string
	AWSAccessKeyID     string
	AWSAccessKeySecret string

	Ports *ports.Collection
}

func NewEnableEBSPlan(input *EnableEBSPlanInput) planner.Plan {
	return &enableEBSPlan{
		Ports:             input.Ports,
		ClusterName:       input.ClusterName,
		RancherKubeconfig: input.RancherKubeconfig,
		EBSAddonVersion:   input.EBSAddonVersion,
		AccessKey:         input.AWSAccessKeyID,
		SecretKey:         input.AWSAccessKeySecret,
	}
}

type enableEBSPlan struct {
	RancherKubeconfig       string
	ClusterName             string
	EBSAddonVersion         string
	AccessKey               string
	SecretKey               string
	OIDCIssuerURL           string //TODO: can this be removed
	OIDCProviderARN         string
	DriverRoleARN           string
	EBSPolicyAttachedToRole bool
	EBSAddonARN             string
	EBSAddonActive          bool

	EKSDetails    *models.EKSClusterDetails
	AWSEKSDetails *eks.Cluster

	Ports *ports.Collection
}

func (p *enableEBSPlan) Name() string {
	return "enable_ebs_csi_driver"
}

func (p *enableEBSPlan) Create(ctx context.Context) ([]planner.Procedure, error) {
	logger := zap.S().With("plan_name", p.Name())
	logger.Info("creating plan")

	steps := []planner.Procedure{}
	if p.EKSDetails == nil {
		steps = append(steps, NewRancherEKSDetailsStep(p))
	}

	if p.AccessKey == "" || p.SecretKey == "" {
		steps = append(steps, NewRancherAWSCloudCredentialsStep(p))
	}

	if p.AWSEKSDetails == nil {
		steps = append(steps, NewAWSEKSDetailsStep(p))
	}

	if p.OIDCProviderARN == "" {
		steps = append(steps, NewAWSCreateOIDCProviderStep(p))
	}

	if p.DriverRoleARN == "" {
		steps = append(steps, NewAWSCreateEBSDriverRoleStep(p))
	}

	if !p.EBSPolicyAttachedToRole {
		steps = append(steps, NewAWSIAMAttachEBSPolicyStep(p))
	}

	if p.EBSAddonARN == "" {
		steps = append(steps, NewAWSEKSCreateEBSAddonStep(p))
	}

	if !p.EBSAddonActive {
		steps = append(steps, NewAWSEKSWaitAddonActiveStep(p))
	}

	return steps, nil
}
