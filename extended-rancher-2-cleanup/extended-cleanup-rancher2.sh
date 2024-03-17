#!/bin/bash

# Cleanup for nodes provisioned using the RKE1 distribution
# Note, for RKE2 and K3s use the uninstall script deployed on the node during install. 

# Directories to cleanup
CLEANUP_DIRS=(/etc/ceph /etc/cni /etc/kubernetes /opt/cni /run/secrets/kubernetes.io /run/calico /run/flannel /var/lib/calico /var/lib/weave /var/lib/etcd /var/lib/cni /var/lib/kubelet /var/lib/rancher/rke/log /var/log/containers /var/log/pods /var/run/calico)

# Interfaces to cleanup
CLEANUP_INTERFACES=(flannel.1 cni0 tunl0 weave datapath vxlan-6784)

run() {

  CONTAINERS=$(docker ps -qa)
  if [[ -n ${CONTAINERS} ]]
    then
      cleanup-containers
    else
      techo "No containers exist, skipping container cleanup..."
  fi
  cleanup-dirs
  cleanup-interfaces
  VOLUMES=$(docker volume ls -q)
  if [[ -n ${VOLUMES} ]]
    then
      cleanup-volumes
    else
      techo "No volumes exist, skipping container volume cleanup..."
  fi
  if [[ ${DELETE_IMAGES} -eq 1 ]]
    then
      IMAGES=$(docker images -q)
      if [[ -n ${IMAGES} ]]
        then
          cleanup-images
        else
          techo "No images exist, skipping container image cleanup..."
      fi
  fi
  if [[ -z ${SKIP_FLUSH_IPTABLES} ]]
    then
      flush-iptables
    else
      techo "Skipping flush of iptables rules..."
  fi
  techo "Done!"

}

cleanup-containers() {

  techo "Removing containers..."
  docker rm -f $(docker ps -qa)

}

cleanup-dirs() {

  techo "Unmounting filesystems..."
  for mount in $(mount | grep '/var/lib/kubelet' | awk '{ print $3 }')
    do
      umount -f $mount
  done

  if [ -n "${DELETE_SNAPSHOTS}" ]
    then
      techo "Removing etcd snapshots..."
      rm -rf /opt/rke
  fi

  techo "Removing directories..."
  for DIR in "${CLEANUP_DIRS[@]}"
    do
      techo "Removing $DIR"
      rm -rf $DIR
  done

}

cleanup-images() {

  techo "Removing images..."
  docker rmi -f $(docker images -q)

}

cleanup-interfaces() {

  techo "Removing interfaces..."
  for INTERFACE in "${CLEANUP_INTERFACES[@]}"
    do
      if $(ip link show ${INTERFACE} > /dev/null 2>&1)
        then
          techo "Removing $INTERFACE"
          ip link delete $INTERFACE
      fi
  done

}

cleanup-volumes() {

  techo "Removing volumes..."
  docker volume rm $(docker volume ls -q)

}

flush-iptables() {

  techo "Flushing iptables..."
  iptables -F -t nat
  iptables -X -t nat
  iptables -F -t mangle
  iptables -X -t mangle
  iptables -F
  iptables -X
  techo "Restarting Docker..."
  if systemctl list-units --full -all | grep -q docker.service
    then
      systemctl restart docker
    else
      /etc/init.d/docker restart
  fi

}

help() {

  echo "Rancher 2.x extended cleanup
  Usage: bash extended-cleanup-rancher2.sh [ -f -i -s ]

  All flags are optional

  -f | --skip-iptables      Skip flush of iptables rules
  -i | --delete-images      Cleanup all container images
  -s | --delete-snapshots   Cleanup all etcd snapshots
  -h                        This help menu

    !! Warning, this script flushes iptables rules, removes containers, and all data specific to Kubernetes and Rancher
    !! Docker will be restarted when flushing iptables rules
    !! Backup data as needed before running this script
    !! Use at your own risk"

}

timestamp() {

  date "+%Y-%m-%d %H:%M:%S"

}

techo() {

  echo "$(timestamp): $*"

}

# Check if we're running as root.
if [[ $EUID -ne 0 ]]
  then
    techo "This script must be run as root"
    exit 1
fi

while test $# -gt 0
  do
    case ${1} in
      -f|--skip-iptables)
        shift
        SKIP_FLUSH_IPTABLES=1
        ;;
      -i|--delete-images)
        shift
        DELETE_IMAGES=1
        ;;
      -s|--delete-snapshots)
        shift
        DELETE_SNAPSHOTS=1
        ;;
      h)
        help && exit 0
        ;;
      *)
        help && exit 0
    esac
done

# Run the cleanup
run