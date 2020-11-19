#!/bin/bash
# Backup your data
# Use at your own risk
# Usage ./extended-cleanup-rancher2.sh
# Include clearing all iptables: ./extended-cleanup-rancher2.sh --flush-iptables --flush-images

flushiptables=0
flushimages=0
POSITIONAL=()
while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    -i|--flush-iptables)
    flushiptables=1
    shift # past argument
    shift # past value
    ;;
    -f|--flush-images)
    flushimages=1
    shift # past argument
    shift # past value
    ;;
    *)    # unknown option
    POSITIONAL+=("$1") # save it in an array for later
    shift # past argument
    ;;
esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters

echo "Removing containers..."
docker rm -f $(docker ps -qa)

if [ "$flushimages" = "1" ];
then
  echo "Removing images..."
  docker rmi -f $(docker images -q)
fi

echo "Removing volumes..."
docker volume rm $(docker volume ls -q)

echo "Removing directories..."
for mount in $(mount | grep tmpfs | grep '/var/lib/kubelet' | awk '{ print $3 }') /var/lib/kubelet /var/lib/rancher; do umount $mount; done
cleanupdirs="/etc/ceph /etc/cni /etc/kubernetes /opt/cni /opt/rke /run/secrets/kubernetes.io /run/calico /run/flannel /var/lib/calico /var/lib/weave /var/lib/etcd /var/lib/cni /var/lib/kubelet /var/lib/rancher/rke/log /var/log/containers /var/log/pods /var/run/calico"
for dir in $cleanupdirs; do
  echo "Removing $dir"
  rm -rf $dir
done

echo "Removing interfaces..."
cleanupinterfaces="flannel.1 cni0 tunl0"
for interface in $cleanupinterfaces; do
  echo "Deleting $interface"
  ip link delete $interface
done
if [ "$flushiptables" = "1" ];
then
  echo "Parameter flush found, flushing all iptables"
  iptables -F -t nat
  iptables -X -t nat
  iptables -F -t mangle
  iptables -X -t mangle
  iptables -F
  iptables -X
  /etc/init.d/docker restart
else
  echo "Parameter flush not found, iptables not cleaned"
fi
