Note: The files in this folder are mirrored from another location, do not edit directly.

# Supportability Review

Ensure business continuity with ongoing reviews and advice. Get faster resolutions, prevent incidents, minimize drift whilst staying conformant with our validated configurations.

## Steps

1. Download the `collect.sh` script on a Linux node with "docker" installed.
    ```shell
    wget https://raw.githubusercontent.com/rancherlabs/support-tools/master/collection/rancher/v2.x/supportability-review/collect.sh
    chmod +x collect.sh
    ```

2. Set the required environment variables and run the collection script.
    ```shell
   export RANCHER_URL="https://rancher.example.com"
   export RANCHER_TOKEN="token-a1b2c:hp7nxfs25w5g7rlc6gkasddhzpphfjbgmcqg6g2kpv52gxg7tl2fgpq2q"
   ./collect.sh
   ```

3. Share the generated support bundle with SUSE Rancher Support Team.

### What's being collected?

Please review the below files for details:

- [cluster-collector.sh](./cluster-collector.sh)
- [nodes-collector.sh](./nodes-collector.sh)