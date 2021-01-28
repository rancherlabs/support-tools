# rancher-metadata-syncer
Rancher Metadata Syncer is a simple pod for publishing the Rancher metadata.json in an airgap setup to allow Rancher to get updated metadata files without granting Rancher internet access or upgrading Rancher.

## Installation

Note: The following tool should only be deployed on the Rancher Local cluster and not on a downstream cluster.

### Option A - Configmap
The configmap option is used when you would like to add the metadata files via a Configmap.
Note: The following steps should be run from a server/workstation with internet access.

- Download the metadata file(s)

```bash
wget --no-check-certificate -O v2-4.json https://releases.rancher.com/kontainer-driver-metadata/release-v2.4/data.json
wget --no-check-certificate -O v2-5.json https://releases.rancher.com/kontainer-driver-metadata/release-v2.5/data.json
```

- Create the Configmap with the metadata files.

```bash
kubectl -n cattle-system create configmap rancher-metadata --from-file=v2-4.json=./v2-4.json --from-file=v2-4.json=./v2-5.json
```

- Deploy the workload
```bash
kubectl apply -f deployment-configmap.yaml
```

- If you would update the metadata file, please do the following.
```bash
wget --no-check-certificate -O v2-4.json https://releases.rancher.com/kontainer-driver-metadata/release-v2.4/data.json
wget --no-check-certificate -O v2-5.json https://releases.rancher.com/kontainer-driver-metadata/release-v2.5/data.json
kubectl -n cattle-system delete configmap rancher-metadata
kubectl -n cattle-system create configmap rancher-metadata --from-file=v2-4.json=./v2-4.json --from-file=v2-4.json=./v2-5.json
kubectl -n cattle-system patch deployment rancher-metadata -p "{\"spec\":{\"template\":{\"metadata\":{\"labels\":{\"date\":\"$(date +%s)\"}}}}}"
```

### Option B - Proxy
The proxy option is used if you would like the deployment to automatedly download the metadata files every 6 hours without opening all of Rancher to the internet via the Proxy.

- Edit values HTTP_PROXY and HTTPS_PROXY in deployment-proxy.yaml match your environment requirements.
```bash
- name: HTTPS_PROXY
  value: "https://<user>:<password>@<ip_addr>:<port>/"
- name: HTTP_PROXY
  value: "http://<user>:<password>@<ip_addr>:<port>/"
```

- Deploy the workload
```bash
kubectl apply -f deployment-proxy.yaml
```

## Updating Rancher

- Browse to the Rancher UI -> Global -> Settings -> rke-metadata-config

- Update the value to the following for Rancher v2.4.x
```
{
  "refresh-interval-minutes": "60",
  "url": "http://rancher-metadata/v2-4.json"
}
```

- Update the value to the following for Rancher v2.5.x
```
{
  "refresh-interval-minutes": "60",
  "url": "http://rancher-metadata/v2-5.json"
}
```
