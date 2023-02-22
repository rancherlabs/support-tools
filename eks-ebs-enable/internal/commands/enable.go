package commands

import (
	"github.com/rancherlabs/support-tools/eks-ebs-enable/core/ports"
	"github.com/rancherlabs/support-tools/eks-ebs-enable/internal/config"
	"github.com/rancherlabs/support-tools/eks-ebs-enable/internal/inject"
	"github.com/spf13/cobra"
	"go.uber.org/zap"
)

func NewEnableCmd() *cobra.Command {
	cfg := &config.Config{}

	cmd := &cobra.Command{
		Use:   "enable",
		Short: "Enable the EBS CSI driver for EKS",
		PreRun: func(cmd *cobra.Command, args []string) {
			bindCommandToViper(cmd)
		},
		RunE: func(cmd *cobra.Command, args []string) error {
			app := inject.CreateApp(cfg)

			output, err := app.Enable(cmd.Context(), &ports.EnableInput{
				ClusterName:        cfg.Cluster.Name,
				RancherKubeconfig:  cfg.Rancher.Kubeconfig,
				EBSAddonVersion:    cfg.EBSAddonVersion,
				ExplicitCreds:      cfg.ExplicitCreds,
				AWSAccessKeyID:     cfg.AWSCredentials.AccessKeyID,
				AWSAccessKeySecret: cfg.AWSCredentials.AccessKeySecret,
			})
			if err != nil {
				return err
			}

			//TODO: do stuff with the output
			zap.S().Info(output)

			return nil
		},
	}

	cmd.Flags().StringVarP(&cfg.Cluster.Name, "cluster", "c", "", "The name of the Rancher cluster to upgrade")
	cmd.Flags().StringVarP(&cfg.Rancher.Endpoint, "endpoint", "e", "", "The Rancher API Endpoint (ends with /v3)")
	cmd.Flags().StringVarP(&cfg.Rancher.BearerToken, "bearer-token", "b", "", "The Rancher API Bearer Token")
	cmd.Flags().StringVarP(&cfg.Rancher.Kubeconfig, "kubeconfig", "k", "", "The path to the Rancher Kubeconfig. (default \"$HOME/.kube/config\")")
	cmd.Flags().StringVarP(&cfg.EBSAddonVersion, "version", "v", "latest", "The version of the EBS addon to install if its not installed already")
	cmd.Flags().BoolVar(&cfg.ExplicitCreds, "explicit-creds", false, "If true the AWS credentials supplied via the flags will be used")
	cmd.Flags().StringVar(&cfg.AWSCredentials.AccessKeyID, "access-key-id", "", "The AWS access key id to use")
	cmd.Flags().StringVar(&cfg.AWSCredentials.AccessKeySecret, "access-key-secret", "", "The AWS access key secret to use")

	cmd.MarkFlagRequired("cluster")
	cmd.MarkFlagRequired("endpoint")
	cmd.MarkFlagRequired("bearer-token")

	return cmd
}
