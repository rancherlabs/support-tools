package rancher

type ClusterListAPIService struct {
	Collection
	Data []ClusterDetailsAPIService `json:"data,omitempty"`
}

type ClusterDetailsAPIService struct {
	ClusterSpec
	APIService
}

// NOTE: these types have been copied from Rancher so that we don't
// require a import of Rancher.

type ClusterSpecBase struct {
	DesiredAgentImage  string `json:"desiredAgentImage"`
	DesiredAuthImage   string `json:"desiredAuthImage"`
	AgentImageOverride string `json:"agentImageOverride"`
	//AgentEnvVars                                         []v1.EnvVar                             `json:"agentEnvVars,omitempty"`
	//RancherKubernetesEngineConfig                        *rketypes.RancherKubernetesEngineConfig `json:"rancherKubernetesEngineConfig,omitempty"`
	DefaultPodSecurityAdmissionConfigurationTemplateName string `json:"defaultPodSecurityAdmissionConfigurationTemplateName,omitempty"`
	DefaultPodSecurityPolicyTemplateName                 string `json:"defaultPodSecurityPolicyTemplateName,omitempty"`
	DefaultClusterRoleForProjectMembers                  string `json:"defaultClusterRoleForProjectMembers,omitempty"`
	DockerRootDir                                        string `json:"dockerRootDir,omitempty"`
	EnableNetworkPolicy                                  *bool  `json:"enableNetworkPolicy"`
	EnableClusterAlerting                                bool   `json:"enableClusterAlerting"`
	EnableClusterMonitoring                              bool   `json:"enableClusterMonitoring"`
	WindowsPreferedCluster                               bool   `json:"windowsPreferedCluster"`
	//LocalClusterAuthEndpoint                             LocalClusterAuthEndpoint                `json:"localClusterAuthEndpoint,omitempty"`
	//ClusterSecrets                                       ClusterSecrets                          `json:"clusterSecrets" norman:"nocreate,noupdate"`
}

type EKSClusterConfigSpec struct {
	AmazonCredentialSecret string            `json:"amazonCredentialSecret"`
	DisplayName            string            `json:"displayName"`
	Region                 string            `json:"region"`
	Imported               bool              `json:"imported"`
	KubernetesVersion      *string           `json:"kubernetesVersion"`
	Tags                   map[string]string `json:"tags"`
	SecretsEncryption      *bool             `json:"secretsEncryption"`
	KmsKey                 *string           `json:"kmsKey"`
	PublicAccess           *bool             `json:"publicAccess"`
	PrivateAccess          *bool             `json:"privateAccess"`
	PublicAccessSources    []string          `json:"publicAccessSources"`
	LoggingTypes           []string          `json:"loggingTypes"`
	Subnets                []string          `json:"subnets"`
	SecurityGroups         []string          `json:"securityGroups"`
	ServiceRole            *string           `json:"serviceRole"`
	NodeGroups             []NodeGroup       `json:"nodeGroups"`
}

type NodeGroup struct {
	Gpu                  *bool              `json:"gpu"`
	ImageID              *string            `json:"imageId"`
	NodegroupName        *string            `json:"nodegroupName"`
	DiskSize             *int64             `json:"diskSize"`
	InstanceType         *string            `json:"instanceType"`
	Labels               map[string]*string `json:"labels"`
	Ec2SshKey            *string            `json:"ec2SshKey"`
	DesiredSize          *int64             `json:"desiredSize"`
	MaxSize              *int64             `json:"maxSize"`
	MinSize              *int64             `json:"minSize"`
	Subnets              []string           `json:"subnets"`
	Tags                 map[string]*string `json:"tags"`
	ResourceTags         map[string]*string `json:"resourceTags"`
	UserData             *string            `json:"userData"`
	Version              *string            `json:"version"`
	LaunchTemplate       *LaunchTemplate    `json:"launchTemplate"`
	RequestSpotInstances *bool              `json:"requestSpotInstances"`
	SpotInstanceTypes    []*string          `json:"spotInstanceTypes"`
	NodeRole             *string            `json:"nodeRole"`
}

type LaunchTemplate struct {
	ID      *string `json:"id"`
	Name    *string `json:"name"`
	Version *int64  `json:"version"`
}

type ClusterSpec struct {
	ClusterSpecBase
	DisplayName string `json:"displayName"`
	Description string `json:"description"`
	Internal    bool   `json:"internal"`
	//K3sConfig                           *K3sConfig                  `json:"k3sConfig,omitempty"`
	//Rke2Config                          *Rke2Config                 `json:"rke2Config,omitempty"`
	//ImportedConfig                      *ImportedConfig             `json:"importedConfig,omitempty" norman:"nocreate,noupdate"`
	//GoogleKubernetesEngineConfig        *MapStringInterface         `json:"googleKubernetesEngineConfig,omitempty"`
	//AzureKubernetesServiceConfig        *MapStringInterface         `json:"azureKubernetesServiceConfig,omitempty"`
	//AmazonElasticContainerServiceConfig *MapStringInterface         `json:"amazonElasticContainerServiceConfig,omitempty"`
	//GenericEngineConfig                 *MapStringInterface         `json:"genericEngineConfig,omitempty"`
	//AKSConfig                           *aksv1.AKSClusterConfigSpec `json:"aksConfig,omitempty"`
	EKSConfig *EKSClusterConfigSpec `json:"eksConfig,omitempty"`
	//GKEConfig                           *gkev1.GKEClusterConfigSpec `json:"gkeConfig,omitempty"`
	ClusterTemplateName         string `json:"clusterTemplateName,omitempty"`
	ClusterTemplateRevisionName string `json:"clusterTemplateRevisionName,omitempty"`
	//ClusterTemplateAnswers              Answer                      `json:"answers,omitempty"`
	//ClusterTemplateQuestions            []Question                  `json:"questions,omitempty" norman:"nocreate,noupdate"`
	FleetWorkspaceName string `json:"fleetWorkspaceName,omitempty"`
}

type APIService struct {
	Resource
	Annotations map[string]string `json:"annotations,omitempty" yaml:"annotations,omitempty"`
	CABundle    string            `json:"caBundle,omitempty" yaml:"caBundle,omitempty"`
	//Conditions            []APIServiceCondition `json:"conditions,omitempty" yaml:"conditions,omitempty"`
	Created               string            `json:"created,omitempty" yaml:"created,omitempty"`
	CreatorID             string            `json:"creatorId,omitempty" yaml:"creatorId,omitempty"`
	Group                 string            `json:"group,omitempty" yaml:"group,omitempty"`
	GroupPriorityMinimum  int64             `json:"groupPriorityMinimum,omitempty" yaml:"groupPriorityMinimum,omitempty"`
	InsecureSkipTLSVerify bool              `json:"insecureSkipTLSVerify,omitempty" yaml:"insecureSkipTLSVerify,omitempty"`
	Labels                map[string]string `json:"labels,omitempty" yaml:"labels,omitempty"`
	Name                  string            `json:"name,omitempty" yaml:"name,omitempty"`
	//OwnerReferences       []OwnerReference      `json:"ownerReferences,omitempty" yaml:"ownerReferences,omitempty"`
	Removed string `json:"removed,omitempty" yaml:"removed,omitempty"`
	//Service               *ServiceReference     `json:"service,omitempty" yaml:"service,omitempty"`
	State                string `json:"state,omitempty" yaml:"state,omitempty"`
	Transitioning        string `json:"transitioning,omitempty" yaml:"transitioning,omitempty"`
	TransitioningMessage string `json:"transitioningMessage,omitempty" yaml:"transitioningMessage,omitempty"`
	UUID                 string `json:"uuid,omitempty" yaml:"uuid,omitempty"`
	//Version              string `json:"version,omitempty" yaml:"version,omitempty"`
	//VersionPriority      int64  `json:"versionPriority,omitempty" yaml:"versionPriority,omitempty"`
}

type Resource struct {
	ID      string            `json:"id,omitempty"`
	Type    string            `json:"type,omitempty"`
	Links   map[string]string `json:"links"`
	Actions map[string]string `json:"actions"`
}

type Collection struct {
	Type         string                 `json:"type,omitempty"`
	Links        map[string]string      `json:"links"`
	CreateTypes  map[string]string      `json:"createTypes,omitempty"`
	Actions      map[string]string      `json:"actions"`
	Pagination   *Pagination            `json:"pagination,omitempty"`
	Sort         *Sort                  `json:"sort,omitempty"`
	Filters      map[string][]Condition `json:"filters,omitempty"`
	ResourceType string                 `json:"resourceType"`
}

type SortOrder string

type Sort struct {
	Name    string            `json:"name,omitempty"`
	Order   SortOrder         `json:"order,omitempty"`
	Reverse string            `json:"reverse,omitempty"`
	Links   map[string]string `json:"links,omitempty"`
}

var (
	ModifierEQ      ModifierType = "eq"
	ModifierNE      ModifierType = "ne"
	ModifierNull    ModifierType = "null"
	ModifierNotNull ModifierType = "notnull"
	ModifierIn      ModifierType = "in"
	ModifierNotIn   ModifierType = "notin"
)

type ModifierType string

type Condition struct {
	Modifier ModifierType `json:"modifier,omitempty"`
	Value    interface{}  `json:"value,omitempty"`
}

type Pagination struct {
	Marker   string `json:"marker,omitempty"`
	First    string `json:"first,omitempty"`
	Previous string `json:"previous,omitempty"`
	Next     string `json:"next,omitempty"`
	Last     string `json:"last,omitempty"`
	Limit    *int64 `json:"limit,omitempty"`
	Total    *int64 `json:"total,omitempty"`
	Partial  bool   `json:"partial,omitempty"`
}
