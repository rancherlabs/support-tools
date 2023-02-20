package config

type Config struct {
	Rancher         RancherConfig
	Cluster         ClusterConfig
	EBSAddonVersion string
}

type RancherConfig struct {
	Endpoint    string
	BearerToken string
	Kubeconfig  string
}

type ClusterConfig struct {
	Name string
}
