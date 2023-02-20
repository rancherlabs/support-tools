package commands

import (
	"fmt"

	"github.com/spf13/cobra"
	"github.com/spf13/pflag"
	"github.com/spf13/viper"
)

func initCobra() {
	viper.SetEnvPrefix("EKSEBSCSI")
	viper.AutomaticEnv()
}

func bindCommandToViper(cmd *cobra.Command) {
	bindFlagsToViper(cmd.PersistentFlags())
	bindFlagsToViper(cmd.Flags())
}

func bindFlagsToViper(fs *pflag.FlagSet) {
	fs.VisitAll(func(flag *pflag.Flag) {
		_ = viper.BindPFlag(flag.Name, flag)
		_ = viper.BindEnv(flag.Name)

		if !flag.Changed && viper.IsSet(flag.Name) {
			val := viper.Get(flag.Name)
			_ = fs.Set(flag.Name, fmt.Sprintf("%v", val))
		}
	})
}
