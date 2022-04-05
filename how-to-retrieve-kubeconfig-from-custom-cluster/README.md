## How to retrieve a kubeconfig from RKE v0.2.x+ or Rancher v2.2.x+

During a Rancher outage or other disaster event. You may lose access to a downstream cluster via Rancher and be unable to manage your applications. This process allows to bypass Rancher and connects directly to the downstream cluster.

## Pre-requisites

- Rancher v2.2.x or newer
- RKE v0.2.x or newer
- SSH access to one of the controlplane nodes

## Resolution

### SSH access

- You should SSH into one of the controlplane nodes in the cluster
- You'll need root/sudo or access to the docker cli

- Copy kubectl from the kubelet container
```bash
docker cp kubelet:/usr/local/bin/kubelet /usr/local/bin/
```

### Oneliner (RKE and Rancher custom cluster)

This option requires kubectl and jq to be installed on the server.

```
kubectl --kubeconfig $(docker inspect kubelet --format '{{ range .Mounts }}{{ if eq .Destination "/etc/kubernetes" }}{{ .Source }}{{ end }}{{ end }}')/ssl/kubecfg-kube-node.yaml get configmap -n kube-system full-cluster-state -o json | jq -r .data.\"full-cluster-state\" | jq -r .currentState.certificatesBundle.\"kube-admin\".config | sed -e "/^[[:space:]]*server:/ s_:.*_: \"https://127.0.0.1:6443\"_" > kubeconfig_admin.yaml
kubectl --kubeconfig kubeconfig_admin.yaml get nodes
```

### Docker run commands (Rancher custom cluster)

This option does not require kubectl or jq on the server because this uses the `rancher/rancher-agent` image to retrieve the kubeconfig.

- Get kubeconfig
```
docker run --rm --net=host -v $(docker inspect kubelet --format '{{ range .Mounts }}{{ if eq .Destination "/etc/kubernetes" }}{{ .Source }}{{ end }}{{ end }}')/ssl:/etc/kubernetes/ssl:ro --entrypoint bash $(docker inspect $(docker images -q --filter=label=org.label-schema.vcs-url=https://github.com/rancher/hyperkube.git) --format='{{index .RepoTags 0}}' | tail -1) -c 'kubectl --kubeconfig /etc/kubernetes/ssl/kubecfg-kube-node.yaml get configmap -n kube-system full-cluster-state -o json | jq -r .data.\"full-cluster-state\" | jq -r .currentState.certificatesBundle.\"kube-admin\".config | sed -e "/^[[:space:]]*server:/ s_:.*_: \"https://127.0.0.1:6443\"_"' > kubeconfig_admin.yaml
```

- Run `kubectl get nodes`
```
docker run --rm --net=host -v $PWD/kubeconfig_admin.yaml:/root/.kube/config:z --entrypoint bash $(docker inspect $(docker images -q --filter=label=org.label-schema.vcs-url=https://github.com/rancher/hyperkube.git) --format='{{index .RepoTags 0}}' | tail -1) -c 'kubectl get nodes'
```

### Script
Run `https://raw.githubusercontent.com/rancherlabs/support-tools/master/how-to-retrieve-kubeconfig-from-custom-cluster/rke-node-kubeconfig.sh` and follow the instructions given.
