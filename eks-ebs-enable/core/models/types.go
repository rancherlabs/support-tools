package models

type EKSClusterDetails struct {
	ID                     string `json:"id"`
	Name                   string `json:"name"`
	AmazonCredentialSecret string `json:"amazonCredentialSecret"`
	Region                 string `json:"region"`
	KubernetesVersion      string `json:"kubernetesVersion"`
	KubeconfigURL          string `json:"kubeconfigURL"`
}
