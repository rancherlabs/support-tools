# NGINX-to-pods-check
This script is designed to walk through all the ingresses in a cluster and test that it can curl the backend pods from the NGINX pods. This is mainly done to verify the overlay network is working along with checking the overall configurtion.

## Run script
```
curl https://raw.githubusercontent.com/rancherlabs/support-tools/master/NGINX-to-pods-check/check.sh | bash
```

## Example output

### Broken pod

```
bash ./check.sh -F Table
####################################################
Pod: webserver-bad-85cf9ccdf8-8v4mh
PodIP: 10.42.0.252
Port: 80
Endpoint: ingress-1d8af467b8b7c9682fda18c8d5053db7
Ingress: test-bad
Ingress Pod: nginx-ingress-controller-b2s2d
Node: a1ubphylbp01
Status: Fail!
####################################################
```

```
bash ./check.sh -F Inline
Checking Pod webserver-bad-8v4mh PodIP 10.42.0.252 on Port 80 in endpoint ingress-bad for ingress test-bad from nginx-ingress-controller-b2s2d on node a1ubphylbp01 NOK
```

### Working pod

```
bash ./check.sh -F Table
####################################################
Pod: webserver-bad-85cf9ccdf8-8v4mh
PodIP: 10.42.0.252
Port: 80
Endpoint: ingress-1d8af467b8b7c9682fda18c8d5053db7
Ingress: test-bad
Ingress Pod: nginx-ingress-controller-b2s2d
Node: a1ubphylbp01
Status: Pass!
####################################################
```

```
bash ./check.sh -F Inline
Checking Pod webserver-good-65644cffd4-gbpkj PodIP 10.42.0.251 on Port 80 in endpoint ingress-good for ingress test-good from nginx-ingress-controller-b2s2d on node a1ubphylbp01 OK
```

## Testing

The following commands will deploy two workloads and ingresses. One that is working with a webserver that is responding on port 80. And the other will have the webserver disabled so it will fail to connect.

```
kubectl apply -f https://raw.githubusercontent.com/rancherlabs/support-tools/master/NGINX-to-pods-check/example-deployment.yml
```
