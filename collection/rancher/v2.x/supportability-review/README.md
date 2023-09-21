Note: The files in this folder are mirrored from another location, do not edit directly.

# Supportability Review

Ensure business continuity with ongoing reviews and advice. Get faster resolutions, prevent incidents, minimize drift whilst staying conformant with our validated configurations.

## Notes
This script is intended to collect info from Rancher upstream cluster and RKE1 managed downstream clusters [CF Additional use]

### What's being collected?

Please review the below files for details:

- [cluster-collector.sh](./cluster-collector.sh)
- [nodes-collector.sh](./nodes-collector.sh) ## Runs on every node of the cluster.

## Prerequisites


- [ ] **Node requirements**
  - Connectivity:
      - Access to Rancher URL

      - Access to https://raw.githubusercontent.com/ to download the collect.sh script

      - Access to ghcr.io/rancherlabs repository to download the docker image used in the collect.sh script.

  - Packages:
      - Docker installed

      - wget or curl tool

- [ ] **Permissions**
      - ⚠️ 🥦 💥 Generate Rancher Bearer Token.  [How to generate a token](https://ranchermanager.docs.rancher.com/reference-guides/user-settings/api-keys#docusaurus_skipToContent_fallback).

     :no_mouth: A truism is that the user that generates the token will collect only clusters allowed to. The user has to be owner, as a member it will fail.

## How to use

**1. Download the `collect.sh` script on a Linux node and make it executable**

   - **Using wget**

       ```shell
       wget https://raw.githubusercontent.com/rancherlabs/support-tools/master/collection/rancher/v2.x/supportability-review/collect.sh
       chmod +x collect.sh
       ```

   - **Using curl**

     ```shell
     curl -OLs https://raw.githubusercontent.com/rancherlabs/support-tools/master/collection/rancher/v2.x/supportability-review/collect.sh
     chmod +x collect.sh
     ```

**2. Set the required environment variables**

  ```shell
  export RANCHER_URL="https://rancher.example.com"
  export RANCHER_TOKEN="token-a1b2c:hp7nxfs25w5g7rlc6gkasddhzpphfjbgmcqg6g2kpv52gxg7tl2fgpq2q"
  ```


**3. Run the collection script**

The script needs to be run on the node, using the root user or a user in the `docker` group.

  ```shell
  ./collect.sh
  ```

**Note:** Ensure the docker daemon is running.

  #### For Airgap setup

  To be able to run this tool in an airgap environment, two images need to be mirrored in the private registry.

  - Supportability Review Image (SR Image): `ghcr.io/rancherlabs/supportability-review:latest`
  - Sonobuoy Image: `rancher/mirrored-sonobuoy-sonobuoy:v0.56.7`

  ```
  export SRC_SR_IMAGE="ghcr.io/rancherlabs/supportability-review:latest"
  export DST_SR_IMAGE="registry.example.com/supportability-review:latest"
  docker tag $SRC_SR_IMAGE $DST_SR_IMAGE
  docker push $DST_SR_IMAGE

  export SRC_SONOBUOY_IMAGE="rancher/mirrored-sonobuoy-sonobuoy:v0.56.7"
  export DST_SONOBUOY_IMAGE="registry.example.com/sonobuoy:v0.56.7"
  docker tag $SRC_SONOBUOY_IMAGE $DST_SONOBUOY_IMAGE
  docker push $DST_SONOBUOY_IMAGE
  ```

  ```
  export SR_IMAGE=$DST_SR_IMAGE
  ./collect.sh \
    --sr-image=$DST_SR_IMAGE \
    --sonobuoy-image=$DST_SONOBUOY_IMAGE
  ```

 #### If using nerdctl and containerd instead of docker
 
 To run with nerdctl, please set the CONTAINERD_ADDRESS variable

 ```shell
 export CONTAINERD_ADDRESS=<your containerd socket used by nerdctl>
 ```

**4. Share the generated support bundle with SUSE Rancher Support Team.**

Output will be written as a tar.gz archive in the same path where the script is run.

## Flags
```shell
Rancher Supportability Review
Usage: collect.sh [ --cluster  <cluster-name> --cluster <cluster-id>]

All flags are optional.
```
## FAQ
1) Rancher downstrean clusters are X but the scan does not detect all
```
INFO     | sscan |__main__:collect_info_from_clusters_using_rancher_api:288 - No of clusters detected: 2
```
The user (Bearer Token) does not have access to that cluster.

2) Access forbidden
```
ERRO[0000] Preflight checks failed
ERRO[0000] could not retrieve list of pods: pods is forbidden: User "u-mrhdf" cannot list resource "pods" in API group "" in the namespace "kube-system"
```
The user (Bearer Token) has access but not full permission. ## Cluster member vs Owner

## Additional use
The script could be run in RKE1 or K3S clusters not managed by Rancher
### Note

1. **Download the `collect.sh` script on a Linux node and make it executable**
2. **Set the required environment variables**
    ```shell
   export KUBECONFIG="/pathto/kubeconfig.yaml"
   ```
3. **Run the collection script**

 The script needs to be run directly on the node, using the root user or a user in the ```docker group```. Ensure the docker daemon is running.
```
 ./collect.sh
```
