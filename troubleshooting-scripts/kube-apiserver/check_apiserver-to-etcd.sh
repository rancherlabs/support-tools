#!/bin/bash

for i in $(docker inspect kube-apiserver | grep -m 1 "\--etcd-servers" | grep -Po '(?<=https://)[^:]*')
do
  echo -n "Checking $i "
  curl -k -X GET --cacert /etc/kubernetes/ssl/kube-ca.pem --cert /etc/kubernetes/ssl/kube-node.pem --key /etc/kubernetes/ssl/kube-node-key.pem https://"$i":2379/health
  echo ""
done
