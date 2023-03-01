package plan

import (
	"context"
	"errors"
	"fmt"
	"strings"

	"github.com/spf13/afero"
	v1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/tools/clientcmd"

	"github.com/rancherlabs/support-tools/eks-ebs-enable/planner"
)

func NewRancherAWSCloudCredentialsStep(plan *enableEBSPlan) planner.Procedure {
	return &rancherAWSCloudCredentialStep{
		plan: plan,
	}
}

type rancherAWSCloudCredentialStep struct {
	plan *enableEBSPlan
}

func (s *rancherAWSCloudCredentialStep) Name() string {
	return "rancher_aws_cloud_credential"
}

func (s *rancherAWSCloudCredentialStep) Do(ctx context.Context) ([]planner.Procedure, error) {
	parts := strings.Split(s.plan.EKSDetails.AmazonCredentialSecret, ":")
	if len(parts) != 2 {
		return nil, fmt.Errorf("unexpected number of parts for aws creds name, got %d but expected 2", len(parts))
	}

	data, err := afero.ReadFile(s.plan.Ports.FileSystem, s.plan.RancherKubeconfig)
	if err != nil {
		return nil, fmt.Errorf("reading file %s: %w", s.plan.RancherKubeconfig, err)
	}

	config, err := clientcmd.RESTConfigFromKubeConfig(data)
	if err != nil {
		return nil, fmt.Errorf("building rest kubeconfig: %w", err)
	}

	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		return nil, fmt.Errorf("getting k8s clientset: %w", err)
	}

	secret, err := clientset.CoreV1().Secrets(parts[0]).Get(ctx, parts[1], v1.GetOptions{})
	if err != nil {
		return nil, fmt.Errorf("getting secret %s/%s: %w", parts[0], parts[1], err)
	}

	data, ok := secret.Data["amazonec2credentialConfig-accessKey"]
	if !ok {
		return nil, errors.New("could find accessKey in secret")
	}
	s.plan.AccessKey = string(data)

	data, ok = secret.Data["amazonec2credentialConfig-secretKey"]
	if !ok {
		return nil, errors.New("could find secretKey in secret")
	}
	s.plan.SecretKey = string(data)

	return nil, nil
}
