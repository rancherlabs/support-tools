# rotate-tokens.sh

This script is used to rotate the main service account and token for a Rancher
downstream cluster. It may be used in the event of a known token exposure or as
a routine preemptive measure.

## Usage

Generate an API token in Rancher and use it to set the TOKEN environment
variable. Set KUBECONFIG to point to your Rancher local cluster. Set
RANCHER_SERVER to point to your Rancher service. The script can be run without
any arguments. Example:

```
export TOKEN=token-ccabc:xyz123
export KUBECONFIG=/path/to/kubeconfig
export RANCHER_SERVER=https://rancher.example.com
./rotate-tokens.sh
```

For extra debugging information, run with DEBUG=y:

```
DEBUG=y ./rotate-tokens.sh
```

The script iterates over each downstream cluster sequentially. If you have many
downstream clusters, this may take several minutes. Do not interrupt the script.

The script generates kubeconfigs for each downstream cluster and stores them in
`./kubeconfigs` in the current working directory. They can be removed with
`rm -r kubeconfigs`.
