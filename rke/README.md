Credit to [Superseb](https://github.com/superseb) for his [gist](https://gist.github.com/superseb/e9f2628d1033cb20e54f6ee268683a7a), where this was copied from.

# Recover cluster.rkestate file from controlplane node

## RKE

Run on `controlplane` node, uses any found `hyperkube` image

```sh
bash ./recover-rkestate.sh
```

## Rancher v2.2.x

Run on `controlplane` node, uses `rancher/rancher-agent` image

```sh
bash ./recover-rancher-rkestate.sh
```
