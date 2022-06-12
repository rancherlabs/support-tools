# Swiss-Army-Knife
Rancher Support uses the image of a standard tool called `swiss-army-knife` to help you manage your Rancher/Kubernetes environment. You can learn more about this image by visiting its official repo at [rancherlabs/swiss-army-knife](https://github.com/rancherlabs/swiss-army-knife/)

TLDR; This image has a lot of useful tools that can be used for scripting and troubleshooting.
- [`kubectl`](https://kubernetes.io/docs/reference/kubectl/overview/)
- [`helm`](https://helm.sh/docs/intro/)
- [`curl`](https://curl.haxx.se/docs/manpage.html)
- [`jq`](https://stedolan.github.io/jq/)
- [`traceroute`](https://www.traceroute.org/about.html)
- [`dig`](https://www.dig.com/products/dns/dig/)
- [`nslookup`](https://www.google.com/search?q=nslookup)
- [`ping`](https://www.google.com/search?q=ping)
- [`netstat`](https://www.google.com/search?q=netstat)
- And many more!

## Example deployments

### Overlay Test
As part of Rancher's overlay test, which can be found [here](https://rancher.com/docs/rancher/v2.6/en/troubleshooting/networking/). You can be deployed to the Rancher environment by running the following command:
```
kubectl apply -f https://raw.githubusercontent.com/rancherlabs/support-tools/master/swiss-army-knife/deploy/overlaytest.yaml
```

This will deploy a deamonset that will run on all nodes in the cluster. These pods will be running `tail -f /dev/null,` which will do nothing but keep the pod running.

You can run the overlay test script by running the following command:
```
curl -sfL https://raw.githubusercontent.com/rancherlabs/support-tools/master/swiss-army-knife/overlaytest.sh | bash
```

### Admin Tools
This deployment will deploy `swiss-army-knife` to all nodes in the cluster but with additional permissions and privileges. This is useful for troubleshooting and managing your Rancher environment. The pod will be running `tail -f /dev/null,` which will do nothing but keep the pod running.

Inside the pod, you will be able to un `kubectl` commands with cluster-admin privileges. Along with this pod being able to gain full access to the node, including the ability to gain a root shell on the node. By running the following commands:
- `kubectl -n kube-system get pods -l app=swiss-army-knife -o wide`
- This will show you all pods running `swiss-army-knife` in the `kube-system` namespace.
- Find the pod on the node you want to interact with.
- `kubectl -n kube-system exec -it <pod-name> -- bash`
- `chroot /rootfs`

You are now running a root shell on the node with full privileges.

**Important:** This deployment is designed for troubleshooting and management purposes and should not be left running on a cluster.