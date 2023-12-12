# Adjust downstream webhook
This script adjusts the version of the rancher-webhook release in downstream clusters.
It decides what to do with the webhook deployment in each downstream cluster based on Rancher server version.

## Background
The `rancher-webhook` chart is deployed in downstream clusters beginning with Rancher v2.7.2.
On a rollback from a version >=2.7.2 to a version <2.7.2, the webhook will stay in the downstream clusters. 
Since each version of the webhook is one-to-one compatible with a specific version of Rancher, this can result in unexpected behavior.

## Usage

```bash
## Create a token through the UI. The token should have no scope and be made for a user who is a global admin.
read -s RANCHER_TOKEN && export RANCHER_TOKEN
## The server URL for Rancher - you can get this value in the "server-url" setting. You can find it by going to Global Settings => Settings => server-url. The example format should be: https://rancher-test.home
read -s RANCHER_URL && export RANCHER_URL
bash adjust-downstream-webhook.sh
```
For Rancher setups using self-signed certificates, you can specify `--insecure-skip-tls-verify` to force the script to 
ignore TLS certificate verification. Note that this option is insecure, and should be avoided for production setups.

## Notes
This script should be run after rolling back Rancher to the desired version 
(for example, when going from v2.7.2 to v2.7.0, only run this script after v2.7.0 is running).
