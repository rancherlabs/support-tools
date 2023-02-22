package config

type Config struct {
	Rancher         RancherConfig
	Cluster         ClusterConfig
	EBSAddonVersion string
	ExplicitCreds   bool
	AWSCredentials  AWSCredentials
}

type RancherConfig struct {
	Endpoint    string
	BearerToken string
	Kubeconfig  string
}

type ClusterConfig struct {
	Name string
}

type AWSCredentials struct {
	AccessKeyID     string
	AccessKeySecret string
}
