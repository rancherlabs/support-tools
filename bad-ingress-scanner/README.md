[![Docker Pulls](https://img.shields.io/docker/pulls/cube8021/bad-ingress-scanner.svg)](https://hub.docker.com/r/cube8021/bad-ingress-scanner)

# Bad ingress scanner
This tool is designed to scan for misbehaving ingresses. An example being an ingress that was deployed referencing a non-existent SSL cert or an ingress with an empty/missing backend service.

## Running report - remotely
```bash
wget -o ingress-scanner.sh https://raw.githubusercontent.com/rancherlabs/support-tools/master/bad-ingress-scanner/run.sh
chmod +x ./ingress-scanner.sh
./ingress-scanner.sh
```

## Running report - in-cluster
```bash
kubectl -n ingress-nginx delete job ingress-scanner
kubectl apply -f deployment.yaml
kubectl -n ingress-nginx logs -l app=ingress-scanner
```

## Example output
```bash
Pod: nginx-ingress-controller-r8kkz
####################################################################
Found bad endpoints.
default/ingress-75f627ce3d0ccd29dd268e0ab2b37008
default/test-01-example-com
default/test-02-example-com
####################################################################
Found bad certs.
default/test-01-example-com
default/test-02-example-com
```

## Removing
```bash
kubectl delete -f deployment.yaml
```

## Deploying test ingress rules
Note: These rules are designed to be broken/invalid and are deployed to the default namespace.
```bash
kubectl apply -f bad-ingress.yaml
```

## Removing test ingress rules
```bash
kubectl delete -f bad-ingress.yaml
```
