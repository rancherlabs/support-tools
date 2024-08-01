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

**1. Download the `collect.sh` script on a Linux environment and make it executable**

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

  #### Additional tolerations

  Some Kubernetes nodes could have it's own taints. If you want to run collector on the nodes, please prepare `yaml` file contains `tolerations` like trailing. To ignore all the taints, just use `operator: Exists`.

  ```yaml
  tolerations:
  - operator: Exists
  - effect: NoSchedule
    operator: Exists
  - key: "key1"
    operator: "Equal"
    value: "value1"
    effect: "NoSchedule"
  - key: "key1"
    operator: "Exists"
    effect: "NoSchedule"
  ```

  And specifiy its absolute path with `SONOBUOY_TOLARATION_FILE` environment variable.
  ```shell
  export SONOBUOY_TOLARATION_FILE=<absolute path to the file>
  ```

**3. Run the collection script**

The script needs to be run on a linux machine running docker with access to your Rancher instance, using the root user or a user in the `docker` group. 

  ```shell
  ./collect.sh
  ```

**Note:** Ensure the docker daemon is running or `nerdctl` is installed or `podman` is installed.

  #### For Airgap setup

  To be able to run this tool in an airgap environment, two images need to be mirrored in the private registry.

  - Supportability Review Image (SR Image): `ghcr.io/rancher/supportability-review:latest`
  - Sonobuoy Image: `rancher/mirrored-sonobuoy-sonobuoy:v0.57.1-rancher2`

  ```
  export SRC_SR_IMAGE="ghcr.io/rancher/supportability-review:latest"
  export DST_SR_IMAGE="registry.example.com/supportability-review:latest"
  docker tag $SRC_SR_IMAGE $DST_SR_IMAGE
  docker push $DST_SR_IMAGE

  export SRC_SONOBUOY_IMAGE="rancher/mirrored-sonobuoy-sonobuoy:v0.57.1-rancher2"
  export DST_SONOBUOY_IMAGE="registry.example.com/sonobuoy:v0.57.1-rancher2"
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

## Config ENV variables

```shell
# To enable collection of cluster-info dump
export SR_COLLECT_CLUSTER_INFO_DUMP=1
```

## Security Policies
If you are using Security Policies, they may prevent collect.sh from working. This section provides solutions for each Security Policy Tool.

### Kyverno
You can use the `exclude` field to bypass Security Policy errors.

For example, suppose you were using the [Disallow Privilege Escalation Policy](https://kyverno.io/policies/pod-security/restricted/disallow-privilege-escalation/disallow-privilege-escalation/) with the following YAML file.
```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: disallow-privilege-escalation
spec:
  validationFailureAction: Enforce
  background: true
  rules:
    - name: privilege-escalation
      match:
        any:
        - resources:
            kinds:
              - Pod
      validate:
        message: >-
          Privilege escalation is disallowed. The fields
          spec.containers[*].securityContext.allowPrivilegeEscalation,
          spec.initContainers[*].securityContext.allowPrivilegeEscalation,
          and spec.ephemeralContainers[*].securityContext.allowPrivilegeEscalation
          must be set to `false`.
        pattern:
          spec:
            =(ephemeralContainers):
            - securityContext:
                allowPrivilegeEscalation: "false"
            =(initContainers):
            - securityContext:
                allowPrivilegeEscalation: "false"
            containers:
            - securityContext:
                allowPrivilegeEscalation: "false"
```

In this case, `collect.sh` outputs the following error and exits abnormally.

```
ERRO[0000] error attempting to run sonobuoy: failed to create object: failed to create API resource sonobuoy: admission webhook "validate.kyverno.svc-fail" denied the request:

resource Pod/sonobuoy/sonobuoy was blocked due to the following policies

disallow-privilege-escalation:
  privilege-escalation: 'validation error: Privilege escalation is disallowed. The
    fields spec.containers[*].securityContext.allowPrivilegeEscalation, spec.initContainers[*].securityContext.allowPrivilegeEscalation,
    and spec.ephemeralContainers[*].securityContext.allowPrivilegeEscalation must
    be set to `false`. rule privilege-escalation failed at path /spec/containers/0/securityContext/'
Traceback (most recent call last):
  File "/etc/rancher/supportability-review/data_collection/collect_info_from_rancher_setup.py", line 689, in <module>
    collect_info_using_kubeconfig(
  File "/etc/rancher/supportability-review/data_collection/collect_info_from_rancher_setup.py", line 373, in collect_info_using_kubeconfig
    myc.run()
  File "/etc/rancher/supportability-review/data_collection/collect_info_from_rancher_setup.py", line 218, in run
    self.collect()
  File "/etc/rancher/supportability-review/data_collection/collect_info_from_rancher_setup.py", line 252, in collect
    subprocess.run(sonobuoy_run_cmd, check=True)
  File "/usr/lib64/python3.10/subprocess.py", line 526, in run
    raise CalledProcessError(retcode, process.args,
subprocess.CalledProcessError: Command '['sonobuoy', 'run', '--config', '/etc/sonobuoy/sonobuoy-config.json', '--kubeconfig', '/tmp/kubeconfig.yml', '--sonobuoy-image', 'rancher/mirrored-sonobuoy-sonobuoy:v0.57.0', '--namespace-psa-enforce-level', 'privileged', '--aggregator-node-selector', 'kubernetes.io/os:linux', '--wait', '--plugin', '/etc/rancher/supportability-review/data_collection/tmp/output/edc77d17-7bb1-4d39-be56-66ecc9b5e554/cluster-collector.yaml', '--plugin', '/etc/rancher/supportability-review/data_collection/tmp/output/edc77d17-7bb1-4d39-be56-66ecc9b5e554/nodes-collector.yaml']' returned non-zero exit status 1.
```
To work around this, add an `exclude` field to the YAML file that allows `sonobuoy` namespaces. If you are using another namespace, specify it.
```
--- disallow-privilege-escalation.yaml	2024-01-24 13:26:16.047008000 +0900
+++ disallow-privilege-escalation-sonobuoy.yaml	2024-01-24 13:32:59.532158949 +0900
@@ -12,6 +12,11 @@
         - resources:
             kinds:
               - Pod
+      exclude:
+        any:
+        - resources:
+            namespaces:
+            - sonobuoy
       validate:
         message: >-
           Privilege escalation is disallowed. The fields
```

## FAQ
1) Rancher downstream clusters are X but the scan does not detect all
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
The script could be run in RKE1/RKE2/K3S clusters not managed by Rancher
### Note

1. **Download the `collect.sh` script on a Linux node and make it executable**
2. **Set the required environment variables**
    ```shell
   export KUBECONFIG="/pathto/kubeconfig.yaml"
   ```
3. **Run the collection script**
 The script needs to be run on a linux machine running docker with access to your Kubernetes instance, using the root user or a user in the `docker` group.
```
 ./collect.sh
```
