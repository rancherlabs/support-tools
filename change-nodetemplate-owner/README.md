## Update
Note: As of Rancher v2.3.3 this should no longer be necessary.
https://github.com/rancher/rancher/issues/12186

## Change node template owner
This script will change your node template owner in Rancher 2.x.  You can run this script as a Docker image or directly as a bash script.  You'll need the cluster ID and the user ID you want to change the ownership to.
1. To obtain the cluster ID in the Rancher user interface, Navigate to Global> "Your Cluster Name"> then grab the cluster ID from your address bar.  I have listed an example of the URL and a cluster ID derrived from the URL below.
   * Example URL: `https://<RANCHER URL>/c/c-48x9z/monitoring`
   * Derrived cluster ID from above URL: **c-48x9z**
2. Now we need the user ID of the user to become the new node template owner, navigate to Global> Users> to find the ID.
3. To run the script using a docker image, make sure your $KUBECONFIG is set to the full path of your Rancher local cluster kube config then run the following command.

    ```bash
    docker run -ti -v $KUBECONFIG:/root/.kube/config patrick0057/change-nodetemplate-owner -c <cluster-id> -n <user-id>
    ```
4. To run the script directly, just download change-nodetemplate-owner.sh, make sure your $KUBECONFIG or ~/.kube/config is pointing to the correct Rancher local cluster then run the following command:

    ```bash
    curl -LO https://github.com/rancherlabs/support-tools/change-nodetemplate-owner/raw/master/change-nodetemplate-owner.sh
    ./change-nodetemplate-owner.sh -c <cluster-id> -n <user-id>
    ```
## Assign a node template to a cluster's node pool.
Assign a node template to a cluster's node pool.  This is useful for situations where the original owner of a cluster has been deleted which also deletes their node templates.  To use this task successfully it is recommended that you create a new node template in the UI before 
using it.  Make sure the node template matches the original ones as closely as possible.  You will be shown options to choose from and
prompted for confirmation.

Run script with docker image

  ```bash
  docker run -ti -v $KUBECONFIG:/root/.kube/config patrick0057/change-nodetemplate-owner -t changenodetemplate -c <cluster-id>
  ```
Run script from bash command line:

  ```bash
  curl -LO https://github.com/rancherlabs/support-tools/change-nodetemplate-owner/raw/master/change-nodetemplate-owner.sh
  ./change-nodetemplate-owner.sh -t changenodetemplate -c <cluster-id>
  ```
