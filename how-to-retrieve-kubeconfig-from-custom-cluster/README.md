# How to retrieve a kubeconfig from an RKE1 cluster

During a Rancher outage or other disaster event you may lose access to a downstream cluster via Rancher and be unable to manage your applications. This process creates a kubeconfig to bypass Rancher, it connects directly to the local kube-apiserver on a control plane node.

**Note**: The [Authorised Cluster Endpoint (ACE)](https://ranchermanager.docs.rancher.com/how-to-guides/new-user-guides/manage-clusters/access-clusters/use-kubectl-and-kubeconfig#authenticating-directly-with-a-downstream-cluster) is a default option enabled on clusters provisioned by Rancher, this contains a second context which connects directly to the downstream kube-apiserver and also bypasses Rancher.

### Pre-requisites

- Rancher v2.2.x or newer
- RKE v0.2.x or newer
- SSH access to one of the controlplane nodes
- Access to the Docker CLI or root/sudo

## Retrieve a kubeconfig - using jq

This option requires `kubectl` and `jq` to be installed on the server.

**Note**: kubectl can be copied from the kubelet container

```bash
docker cp kubelet:/usr/local/bin/kubectl /usr/local/bin/
```

- Get kubeconfig

```bash
kubectl --kubeconfig $(docker inspect kubelet --format '{{ range .Mounts }}{{ if eq .Destination "/etc/kubernetes" }}{{ .Source }}{{ end }}{{ end }}')/ssl/kubecfg-kube-node.yaml get configmap -n kube-system full-cluster-state -o json | jq -r .data.\"full-cluster-state\" | jq -r .currentState.certificatesBundle.\"kube-admin\".config | sed -e "/^[[:space:]]*server:/ s_:.*_: \"https://127.0.0.1:6443\"_" > kubeconfig_admin.yaml
```

- Run `kubectl get nodes`
```bash
kubectl --kubeconfig kubeconfig_admin.yaml get nodes
```

## Retrieve a kubeconfig - without jq

This option does not require `kubectl` or `jq` on the server because this uses the `rancher/rancher-agent` image to retrieve the kubeconfig.

- Get kubeconfig
```bash
docker run --rm --net=host -v $(docker inspect kubelet --format '{{ range .Mounts }}{{ if eq .Destination "/etc/kubernetes" }}{{ .Source }}{{ end }}{{ end }}')/ssl:/etc/kubernetes/ssl:ro --entrypoint bash $(docker inspect $(docker images -q --filter=label=org.opencontainers.image.source=https://github.com/rancher/hyperkube.git) --format='{{index .RepoTags 0}}' | tail -1) -c 'kubectl --kubeconfig /etc/kubernetes/ssl/kubecfg-kube-node.yaml get configmap -n kube-system full-cluster-state -o json | jq -r .data.\"full-cluster-state\" | jq -r .currentState.certificatesBundle.\"kube-admin\".config | sed -e "/^[[:space:]]*server:/ s_:.*_: \"https://127.0.0.1:6443\"_"' > kubeconfig_admin.yaml
```

- Run `kubectl get nodes`
```bash
docker run --rm --net=host -v $PWD/kubeconfig_admin.yaml:/root/.kube/config:z --entrypoint bash $(docker inspect $(docker images -q --filter=label=org.opencontainers.image.source=https://github.com/rancher/hyperkube.git) --format='{{index .RepoTags 0}}' | tail -1) -c 'kubectl get nodes''
```

## Script
Run `https://raw.githubusercontent.com/rancherlabs/support-tools/master/how-to-retrieve-kubeconfig-from-custom-cluster/rke-node-kubeconfig.sh` and follow the instructions given.
