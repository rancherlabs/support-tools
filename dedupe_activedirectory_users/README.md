# SURE-6644 Support Script

## Purpose

These scripts are designed to be used to remove duplicate users that were created due to a bug in Rancher 2.7.5.

It is recommended to take a snapshot of Rancher before performing this in the event that a restore is required.

If the duplicate Rancher users all have been migrated (i.e.:  They all have a principalId of activedirectory_user://<hex guid string>), then you should run dedupe_by_principal.sh.
If the duplicate Rancher users have not been migrated (i.e.: They have a DN-based activedirectory_user:// principalId), then you should run dedupe_by_displayname.sh

## Requirements

This script requires the following:

- jq
- kubectl

## Usage

1. Open a terminal
2. Export environment variables for the path to the kubeconfig for your Rancher cluster

```bash
export RANCHER_URL="<URL To Rancher including https://>"
export RANCHER_TOKEN="<Token for Rancher Admin>"
```

3. Do a dry run first.  This will display a list of the users that will be deleted on the actual run. If you need to, you can also add --insecure-skip-tls-verify.

```bash
./dedupe_by_principal.sh
```
OR
```bash
./dedupe_by_displayname.sh
```

4. Perform the actual delete operation.  If you need to, you can also add --insecure-skip-tls-verify.

```bash
./dedupe_by_principal.sh -w
```
OR
```bash
./dedupe_by_displayname.sh -w
```
