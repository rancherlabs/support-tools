# Fleet | GitRepo Secret Backup Restore Patch

This is a patching script to ensure all secrets used by Fleet `GitRepos` are backed up by the Racnher Backups tool.

The script is designed to fix existing clusters using Fleet and Rancher Backups. When run, it ensures that all secrets used by GitRepos are backed up. Although a bug fix is in progress, it will not be retroactive. Therefore, this script can resolve the current issue.

Additionally, the bug fix will only address `Secrets` created via the Fleet UI of Rancher. It does not cover secrets created outside of the Fleet UI, as those secrets cannot be guaranteed to be "fleet-owned."

By running this patching script on your Rancher cluster, it will identify all secrets used by GitRepos and label them as managed by Fleet. This labeling ensures they are backed up by Rancher Backups.

## Running the script
To run this script you simply need a valid KUBECONFIG to connect to your Racnher cluster. Then execute the shell script:
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