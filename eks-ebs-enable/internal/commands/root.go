package commands

import (
	"github.com/spf13/cobra"
)

func NewRootCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "eks-ebs-enable",
		Short: "A utility to enable the EBS CSI driver for EKS",
		PersistentPreRun: func(cmd *cobra.Command, args []string) {
			bindCommandToViper(cmd)
		},
		Run: func(cmd *cobra.Command, args []string) {
			cmd.Help()
		},
	}

	cmd.PersistentFlags().Bool("debug", false, "If true enables debug logging")
	cmd.AddCommand(NewEnableCmd())

	cobra.OnInitialize(initCobra)

	return cmd
}
