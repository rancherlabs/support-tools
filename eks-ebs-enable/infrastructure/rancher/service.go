package rancher

import (
	"context"
	"fmt"

	"github.com/carlmjohnson/requests"

	"github.com/rancherlabs/support-tools/eks-ebs-enable/core/models"
	"github.com/rancherlabs/support-tools/eks-ebs-enable/core/ports"
	"github.com/rancherlabs/support-tools/eks-ebs-enable/internal/config"
)

func NewService(cfg *config.RancherConfig) ports.RancherService {
	s := &serviceImpl{
		endpoint:    cfg.Endpoint,
		bearerToken: cfg.BearerToken,
	}
	return s
}

type serviceImpl struct {
	endpoint    string
	bearerToken string
}

func (s *serviceImpl) GetClusterDetails(ctx context.Context, clusterName string) (*models.EKSClusterDetails, error) {
	url := fmt.Sprintf("%s/clusters", s.endpoint)
	list := &ClusterListAPIService{}

	err := requests.
		URL(url).
		Accept(ContentTypeJSON).
		Param("name", clusterName).
		Bearer(s.bearerToken).
		ToJSON(list).
		Fetch(ctx)
	if err != nil {
		return nil, fmt.Errorf("getting cluster details from Rancher: %w", err)
	}

	if len(list.Data) == 0 {
		return nil, fmt.Errorf("cluster %s not found", clusterName)
	}

	details := &models.EKSClusterDetails{
		ID:                     list.Data[0].ID,
		Name:                   clusterName,
		AmazonCredentialSecret: list.Data[0].EKSConfig.AmazonCredentialSecret,
		KubernetesVersion:      *list.Data[0].EKSConfig.KubernetesVersion,
		Region:                 list.Data[0].EKSConfig.Region,
	}
	kubeUrl, ok := list.Data[0].Actions["generateKubeconfig"]
	if !ok {
		return nil, fmt.Errorf("no kubeconfig action found for cluster %s", clusterName)
	}
	details.KubeconfigURL = kubeUrl

	return details, nil
}
