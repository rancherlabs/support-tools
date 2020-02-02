# etcd-tools
This is a collection of etcd tools to do long and tedious tasks.  Currently there is a restore tool for restoring a snapshot to a single node and a join tool for rejoining other members after the restore has been completed on the single node.  This has been tested on RKE deployed clusters, Rancher deployed clusters (tested on aws) and Rancher custom clusters.  These tools assume you have not changed node IP's or removed the cluster from the Rancher interface.  If either of these things have been done, your cluster will not be in a healthy state after restore.

1. Take an etcd snapshot before starting, using one of the following commands (only one will work):
```bash
docker exec etcd etcdctl snapshot save /tmp/snapshot.db && docker cp etcd:/tmp/snapshot.db .
```
```bash
docker exec etcd sh -c "etcdctl snapshot --endpoints=\$ETCDCTL_ENDPOINT save /tmp/snapshot.db" && docker cp etcd:/tmp/snapshot.db .
```

2. Stop etcd on all nodes except for the one you are restoring:
```bash
docker update --restart=no etcd && docker stop etcd
```

3. Run the restore:
```bash
curl -LO https://github.com/patrick0057/etcd-tools/raw/master/restore-etcd-single.sh
bash ./restore-etcd-single.sh </path/to/snapshot>
```

You can also restore lost quorum with the following command instead:
```bash
bash ./restore-etcd-single.sh FORCE_NEW_CLUSTER
```

4. Rejoin etcd nodes by running the following commands.  SSH key is optional if you have a default one already set on your ssh account.

Automatic mode:
```bash
curl -LO https://github.com/patrick0057/etcd-tools/raw/master/etcd-join.sh
bash ./etcd-join.sh <ssh user> <remote etcd IP> [path to ssh key for remote box]
```

Manual mode (good for scenarios where you can't setup ssh keys between etcd nodes):
```bash
curl -LO https://github.com/patrick0057/etcd-tools/raw/master/etcd-join.sh
bash ./etcd-join.sh MANUAL_MODE
```

NOTE: If you are using etcd-join.sh to rejoin a node to a cluster that wasn't recently restored with restore-etcd-single.sh, then you will want to make sure the etcd node is not a member of the etcd cluster before running the script.  If it is a member then it will fail to rejoin.  Examples below for clusters that require --endpoints and clusters that don't.
```bash
docker exec etcd sh -c "etcdctl --endpoints=\$ETCDCTL_ENDPOINT member list"
docker exec etcd sh -c "etcdctl --endpoints=\$ETCDCTL_ENDPOINT member remove <id>"
```

```bash
docker exec etcd sh -c "etcdctl member list"
docker exec etcd sh -c "etcdctl member remove <id>"
```

5. Restart kubelet and kube-apiserver on all servers where it has not been restarted for you by the script already.
```bash
docker restart kubelet kube-apiserver
```

## Quickly generate and copy SSH keys

Generate and copy.  This method is quickest if you have a password login you can use on the remote end.
```
ssh-keygen -t rsa -b 4096 -f ~/.ssh/etcd -N "" <<< y >/dev/null
ssh-copy-id -i ~/.ssh/etcd user@host
```

Generate and manual copy.  This method is quickest if you have ssh sessions open already and no other way to login directly without a key.
```
ssh-keygen -t rsa -b 4096 -f ~/.ssh/etcd -N "" <<< y >/dev/null
cat ~/.ssh/etcd.pub
```
Copy output and on the other host paste it in like so
```
cat >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
```
