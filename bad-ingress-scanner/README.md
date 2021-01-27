[![Docker Pulls](https://img.shields.io/docker/pulls/cube8021/bad-ingress-scanner.svg)](https://hub.docker.com/r/cube8021/bad-ingress-scanner)

# Bad ingress scanner
This tool is designed to scan for misbehaving ingresses. An example being an ingress that was deployed referencing a non-extent SSL cert or an ingress with an empty/missing backend service.

## Running report
```bash
kubectl -n ingress-nginx delete job ingress-scanner
kubectl apply -f deployment.yaml
kubectl -n ingress-nginx logs -l app=ingress-scanner
```

## Example output
```
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
