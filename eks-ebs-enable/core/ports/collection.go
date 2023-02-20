package ports

import "github.com/spf13/afero"

type Collection struct {
	Rancher    RancherService
	AWS        AWSClientService
	FileSystem afero.Fs
}
