# Workaround script for patching Rancher agents when clusters disconnect

## Installation

```
kubectl -n cattle-system apply -f deploy.yaml
```

## Example messages
```
Starting checks...
Checking cluster c-m-27h8qs5z
Cluster c-m-27h8qs5z is connected
Checking cluster c-m-7z88l7ss
Cluster c-m-7z88l7ss is connected
Checking cluster c-m-b8mhz2vk
Cluster c-m-b8mhz2vk is connected
Checking cluster c-m-cj8jqkcb
Cluster c-m-cj8jqkcb is not connected
cluster.management.cattle.io/c-m-cj8jqkcb patched
Checking cluster c-m-d5ks8lsw
Cluster c-m-d5ks8lsw is connected
Checking cluster c-m-f59vrbtj
Cluster c-m-f59vrbtj is connected
Checking cluster c-m-z88fl5tl
Cluster c-m-z88fl5tl is connected
Sleeping...
```
