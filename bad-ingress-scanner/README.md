[![Docker Pulls](https://img.shields.io/docker/pulls/cube8021/bad-ingress-scanner.svg)](https://hub.docker.com/r/cube8021/bad-ingress-scanner)

# Bad ingress scanner
This tools is designed to scan for misbehaving ingresses. An example being an ingress that was deployed refencing a non-extent SSL cert or an ingress an empty / missing backend service.

## Running report
```bash
kubectl -n ingress-nginx delete job ingress-scanner
kubectl apply -f deployment.yaml
kubectl -n ingress-nginx logs -l app=ingress-scanner
```

## Removing
```bash
kubectl delete -f deployment.yaml
```
