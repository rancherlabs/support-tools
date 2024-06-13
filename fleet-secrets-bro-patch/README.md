# Fleet | GitRepo Secret Backup Restore Patch

This is a patching script to ensure all secrets used by Fleet `GitRepos` are backed up by the Rancher Backups tool.

From Rancher v2.8.?? (TBD) and v2.9.0 all `Secrets` created via the Fleet UI in Rancher will be included in Rancher Backups.

Any GitRepo `Secrets` created before this, or outside of the Fleet UI in Rancher, will not be included in Rancher Backups.

By running this patching script on your Rancher cluster, it will identify all secrets used by GitRepos and label them as managed by Fleet. This labeling ensures they are backed up by Rancher Backups.

## Running the script
To run this script you simply need a valid KUBECONFIG to connect to your Rancher cluster. Then execute the shell script:
> ./patch_gitrepo_secrets.sh

When run you should see output similar to:

```bash
./patch_gitrepo_secrets.sh
Patching unique secret combinations:
Patching secret: fleet-default:auth-helm-creds
secret/auth-helm-creds patched
Patching secret: fleet-local:auth-gitlab-creds
secret/auth-gitlab-creds patched (no change)
```

Note: If the secret already has the necessary label it will look like the `secret/auth-gitlab-creds` line above.