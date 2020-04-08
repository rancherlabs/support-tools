## Deploy new cluster and node agents on Rancher 2.x

If you've recently made changes to your Rancher installation like updating the server URL or changing the Rancher installation SSL, then you will likely need to redeploy your cluster and node agent YAML files from the Rancher server.

1. Create a local admin user for use with this tutorial or generate an API Bearer Token.  Without this, the script cannot login to get the new deployment file.  You cannot use user accounts that are tied to third party authentication such as LDAP, Active Directory or GitHub to name a few.
2. Login to a single controlplane node of the cluster you need to redeploy your agent YAML to.
3. Download the script:
   ```
   curl -LO https://github.com/rancherlabs/support-tools/raw/master/cluster-agent-tool/cluster-agent-tool.sh
   wget https://github.com/rancherlabs/support-tools/raw/master/cluster-agent-tool/cluster-agent-tool.sh
   ```

4. Choose method a or b, which ever is more convenient for you on step 4.

4a. Run the script with the following options to redeploy your cluster and node agents.
```
bash cluster-agent-tool.sh -fy -a'save' -t'API Bearer Token here'
```

4b. Run the script with the following options to redeploy your cluster YAML.  -p is optional, if you don't include it, then the script will prompt you for the password so it doesn't have to be saved in your bash history.
```
bash cluster-agent-tool.sh -fy -a'save' -u'localadmin' -p'yourpassword'
```


   
5. If your script has made changes to multiple deployments and shows an output like the following, then you are good to repeat these steps for your next cluster.
```
namespace/cattle-system unchanged
serviceaccount/cattle unchanged
clusterrolebinding.rbac.authorization.k8s.io/cattle-admin-binding unchanged
secret/cattle-credentials-bd8604b unchanged
clusterrole.rbac.authorization.k8s.io/cattle-admin unchanged
deployment.extensions/cattle-cluster-agent unchanged
daemonset.extensions/cattle-node-agent unchanged

Script has finished without error.
```
