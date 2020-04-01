#!/bin/bash

# Check if we're running as root.
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root"
  exit 1
fi

MKTEMP_BASEDIR=""
DOCKER_LOGOPTS=""

while getopts ":d:s:" opt; do
  case $opt in
    d)
      MKTEMP_BASEDIR="-p ${OPTARG}"
      ;;
    s)
      DOCKER_LOGOPTS="--since ${OPTARG}"
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
    :)
      echo "Option -$OPTARG requires an argument." >&2
      exit 1
      ;;
  esac
done

# Create temp directory
TMPDIR=$(mktemp -d $MKTEMP_BASEDIR)

# Set TIMEOUT in seconds for select commands
TIMEOUT=60

# Detect RancherOS
if $(grep RancherOS /etc/os-release >/dev/null 2>&1); then
  RANCHEROS=true
fi

function timeout_start_msg() {
  TIMEOUT_CMD=$1
  TIMEOUT_EXCEEDED_MSG="$TIMEOUT_CMD command timed out, killing process to prevent hanging."
  echo "Executing $TIMEOUT_CMD with a timeout of $TIMEOUT seconds."
}
function timeout_done_msg() {
  echo "Execution of $TIMEOUT_CMD has finished."
  echo
}
function timeout_cmd() {
  WPID=$!; sleep $TIMEOUT && if kill -0 $WPID > /dev/null 2>&1; then echo $TIMEOUT_EXCEEDED_MSG; kill $WPID &> /dev/null; fi & KPID=$!; wait $WPID
}

# System info
echo "Collecting systeminfo"
mkdir -p $TMPDIR/systeminfo
hostname > $TMPDIR/systeminfo/hostname 2>&1
hostname -f > $TMPDIR/systeminfo/hostnamefqdn 2>&1
cp -p /etc/hosts $TMPDIR/systeminfo/etchosts 2>&1
cp -p /etc/resolv.conf $TMPDIR/systeminfo/etcresolvconf 2>&1
date > $TMPDIR/systeminfo/date 2>&1
free -m > $TMPDIR/systeminfo/freem 2>&1
uptime > $TMPDIR/systeminfo/uptime 2>&1
dmesg -T > $TMPDIR/systeminfo/dmesg 2>&1
df -h > $TMPDIR/systeminfo/dfh 2>&1
if df -i >/dev/null 2>&1; then
  df -i > $TMPDIR/systeminfo/dfi 2>&1
fi
lsmod > $TMPDIR/systeminfo/lsmod 2>&1
mount > $TMPDIR/systeminfo/mount 2>&1
ps auxfww > $TMPDIR/systeminfo/ps 2>&1
if [ "${RANCHEROS}" = true ]
  then
    top -bn 1 > $TMPDIR/systeminfo/top 2>&1
  else
    COLUMNS=512 top -cbn 1 > $TMPDIR/systeminfo/top 2>&1
fi
cat /proc/cpuinfo > $TMPDIR/systeminfo/cpuinfo 2>&1
uname -a > $TMPDIR/systeminfo/uname 2>&1
cat /etc/*release > $TMPDIR/systeminfo/osrelease 2>&1
if $(command -v lsblk >/dev/null 2>&1); then
  lsblk > $TMPDIR/systeminfo/lsblk 2>&1
fi

timeout_start_msg "lsof"
lsof -Pn > $TMPDIR/systeminfo/lsof 2>&1 & timeout_cmd
timeout_done_msg

if $(command -v sysctl >/dev/null 2>&1); then
  sysctl -a > $TMPDIR/systeminfo/sysctla 2>/dev/null
fi
if $(command -v systemctl >/dev/null 2>&1); then
  systemctl list-units > $TMPDIR/systeminfo/systemd-units 2>&1
fi
if $(command -v service >/dev/null 2>&1); then
  service --status-all > $TMPDIR/systeminfo/service-statusall 2>&1
fi

# OS: Ubuntu
if $(command -v ufw >/dev/null 2>&1); then
  ufw status > $TMPDIR/systeminfo/ubuntu-ufw 2>&1
fi
if $(command -v apparmor_status >/dev/null 2>&1); then
  apparmor_status > $TMPDIR/systeminfo/ubuntu-apparmorstatus 2>&1
fi
if $(command -v dpkg >/dev/null 2>&1); then
  dpkg -l > $TMPDIR/systeminfo/packages-dpkg 2>&1
fi

# OS: RHEL
if [ -f /etc/redhat-release ]; then
  systemctl status NetworkManager > $TMPDIR/systeminfo/rhel-statusnetworkmanager 2>&1
  systemctl status firewalld > $TMPDIR/systeminfo/rhel-statusfirewalld 2>&1
  if $(command -v getenforce >/dev/null 2>&1); then
  getenforce > $TMPDIR/systeminfo/rhel-getenforce 2>&1
  fi
fi
if $(command -v rpm >/dev/null 2>&1); then
  rpm -qa > $TMPDIR/systeminfo/packages-rpm 2>&1
fi

# Docker info and info gathered using `docker` command (Rancher 2 custom cluster/RKE)
if $(command -v docker >/dev/null 2>&1); then
  echo "Collecting Docker info"
  mkdir -p $TMPDIR/docker

  timeout_start_msg "docker info"
  docker info >$TMPDIR/docker/dockerinfo 2>&1 & timeout_cmd
  timeout_done_msg

  timeout_start_msg "docker ps -a"
  docker ps -a >$TMPDIR/docker/dockerpsa 2>&1
  timeout_done_msg

  timeout_start_msg "docker stats"
  docker stats -a --no-stream >$TMPDIR/docker/dockerstats 2>&1 & timeout_cmd
  timeout_done_msg

  if [ -f /etc/docker/daemon.json ]; then
    cat /etc/docker/daemon.json > $TMPDIR/docker/etcdockerdaemon.json
  fi

  # Rancher logging
  echo "Collecting Rancher logs"
  # Discover any server or agent running
  mkdir -p $TMPDIR/rancher/containerinspect
  mkdir -p $TMPDIR/rancher/containerlogs
  RANCHERSERVERS=$(docker ps -a | grep -E "rancher/rancher:|rancher/rancher " | awk '{ print $1 }')
  RANCHERAGENTS=$(docker ps -a | grep -E "rancher/rancher-agent:|rancher/rancher-agent " | awk '{ print $1 }')

  for RANCHERSERVER in $RANCHERSERVERS; do
    docker inspect $RANCHERSERVER > $TMPDIR/rancher/containerinspect/server-$RANCHERSERVER 2>&1
    docker logs $DOCKER_LOGOPTS -t $RANCHERSERVER > $TMPDIR/rancher/containerlogs/server-$RANCHERSERVER 2>&1
  done

  for RANCHERAGENT in $RANCHERAGENTS; do
    docker inspect $RANCHERAGENT > $TMPDIR/rancher/containerinspect/agent-$RANCHERAGENT 2>&1
    docker logs $DOCKER_LOGOPTS -t $RANCHERAGENT > $TMPDIR/rancher/containerlogs/agent-$RANCHERAGENT 2>&1
  done

  echo "Collecting k8s container logging"
  mkdir -p $TMPDIR/k8s/containerlogs
  mkdir -p $TMPDIR/k8s/containerinspect
  KUBECONTAINERS=(etcd etcd-rolling-snapshots kube-apiserver kube-controller-manager kubelet kube-scheduler kube-proxy nginx-proxy)
  for KUBECONTAINER in "${KUBECONTAINERS[@]}"; do
    if [ "$(docker ps -a -q -f name=$KUBECONTAINER)" ]; then
      docker inspect $KUBECONTAINER > $TMPDIR/k8s/containerinspect/$KUBECONTAINER 2>&1
      docker logs $DOCKER_LOGOPTS -t $KUBECONTAINER > $TMPDIR/k8s/containerlogs/$KUBECONTAINER 2>&1
    fi
  done

  echo "Collecting system pods logging"
  mkdir -p $TMPDIR/k8s/podlogs
  mkdir -p $TMPDIR/k8s/podinspect
  SYSTEMNAMESPACES=(kube-system kube-public cattle-system cattle-alerting cattle-logging cattle-pipeline ingress-nginx cattle-prometheus istio-system)
  for SYSTEMNAMESPACE in "${SYSTEMNAMESPACES[@]}"; do
    CONTAINERS=$(docker ps -a --filter name=$SYSTEMNAMESPACE --format "{{.Names}}")
    for CONTAINER in $CONTAINERS; do
      docker inspect $CONTAINER > $TMPDIR/k8s/podinspect/$CONTAINER 2>&1
      docker logs $DOCKER_LOGOPTS -t $CONTAINER > $TMPDIR/k8s/podlogs/$CONTAINER 2>&1
    done
  done

  # etcd
  if docker ps --format='{{.Names}}' | grep -q ^etcd$ >/dev/null 2>&1; then
    echo "Collecting etcdctl output"
    mkdir -p $TMPDIR/etcd
    PARAM=""
    # Check for older versions with incorrectly set ETCDCTL_ENDPOINT vs the correct ETCDCTL_ENDPOINTS
    # If ETCDCTL_ENDPOINTS is empty, its an older version
    if [ -z $(docker exec etcd printenv ETCDCTL_ENDPOINTS) ]; then
      ENDPOINT=$(docker exec etcd printenv ETCDCTL_ENDPOINT)
      if echo $ENDPOINT | grep -vq 0.0.0.0; then
        PARAM="--endpoints=$(docker exec etcd printenv ETCDCTL_ENDPOINT)"
      fi
    fi
    docker exec etcd sh -c "etcdctl $PARAM member list"  > $TMPDIR/etcd/memberlist 2>&1
    docker exec etcd etcdctl endpoint status --endpoints=$(docker exec etcd /bin/sh -c "etcdctl $PARAM member list | cut -d, -f5 | sed -e 's/ //g' | paste -sd ','") --write-out table > $TMPDIR/etcd/endpointstatus 2>&1
    docker exec etcd etcdctl endpoint health --endpoints=$(docker exec etcd /bin/sh -c "etcdctl $PARAM member list | cut -d, -f5 | sed -e 's/ //g' | paste -sd ','") > $TMPDIR/etcd/endpointhealth 2>&1
    docker exec etcd sh -c "etcdctl $PARAM alarm list" > $TMPDIR/etcd/alarmlist 2>&1
  fi

  # nginx-proxy
  echo "Collecting nginx-proxy info"
  if docker inspect nginx-proxy >/dev/null 2>&1; then
    mkdir -p $TMPDIR/k8s/nginx-proxy
    docker exec nginx-proxy cat /etc/nginx/nginx.conf > $TMPDIR/k8s/nginx-proxy/nginx.conf 2>&1
  fi
fi

# Networking
mkdir -p $TMPDIR/networking
iptables-save > $TMPDIR/networking/iptablessave 2>&1
iptables --wait 1 --numeric --verbose --list --table mangle > $TMPDIR/networking/iptablesmangle 2>&1
iptables --wait 1 --numeric --verbose --list --table nat > $TMPDIR/networking/iptablesnat 2>&1
iptables --wait 1 --numeric --verbose --list > $TMPDIR/networking/iptables 2>&1
if $(command -v netstat >/dev/null 2>&1); then
  if [ "${RANCHEROS}" = true ]
    then
      netstat -antu > $TMPDIR/networking/netstat 2>&1
    else
      netstat --programs --all --numeric --tcp --udp > $TMPDIR/networking/netstat 2>&1
      netstat --statistics > $TMPDIR/networking/netstatistics 2>&1
  fi
fi
cat /proc/net/xfrm_stat > $TMPDIR/networking/procnetxfrmstat 2>&1
if $(command -v ip >/dev/null 2>&1); then
  ip addr show > $TMPDIR/networking/ipaddrshow 2>&1
  ip route > $TMPDIR/networking/iproute 2>&1
fi
if $(command -v ifconfig >/dev/null 2>&1); then
  ifconfig -a > $TMPDIR/networking/ifconfiga
fi
if [ -d /etc/cni/net.d/ ]; then
  cat /etc/cni/net.d/*.conf* > $TMPDIR/networking/cni-config 2>&1
fi

# System logging
echo "Collecting systemlogs"
mkdir -p $TMPDIR/systemlogs
cp /var/log/syslog* /var/log/messages* /var/log/kern* /var/log/docker* /var/log/system-docker* /var/log/audit/* $TMPDIR/systemlogs 2>/dev/null

if $(grep "kubelet.service" $TMPDIR/systeminfo/systemd-units > /dev/null 2>&1); then
  journalctl --unit=kubelet > $TMPDIR/k8s/containerlogs/journalctl-kubelet
  journalctl --unit=kubeproxy > $TMPDIR/k8s/containerlogs/journalctl-kubeproxy
fi

# K8s directory/certificates
if [ -d /opt/rke/etc/kubernetes/ssl ]; then
  echo "Collecting k8s state"
  mkdir -p $TMPDIR/k8s/directories

  find /opt/rke/etc/kubernetes/ssl -type f -exec ls -la {} \; > $TMPDIR/k8s/directories/findoptrkeetckubernetesssl 2>&1

  mkdir -p $TMPDIR/k8s/certs
  CERTS=$(find /opt/rke/etc/kubernetes/ssl -type f -name *.pem | grep -v "\-key\.pem$")
  for CERT in $CERTS; do
    openssl x509 -in $CERT -text -noout > $TMPDIR/k8s/certs/$(basename $CERT) 2>&1
  done
  if [ -d /opt/rke/etc/kubernetes/.tmp ]; then
    mkdir -p $TMPDIR/k8s/tmpcerts
    TMPCERTS=$(find /opt/rke/etc/kubernetes/.tmp -type f -name *.pem | grep -v "\-key\.pem$")
    for TMPCERT in $TMPCERTS; do
      openssl x509 -in $TMPCERT -text -noout > $TMPDIR/k8s/tmpcerts/$(basename $TMPCERT) 2>&1
    done
  fi

elif [ -d /etc/kubernetes/ssl ]; then
  echo "Collecting k8s state"
  mkdir -p $TMPDIR/k8s/directories

  find /etc/kubernetes/ssl -type f -exec ls -la {} \; > $TMPDIR/k8s/directories/findetckubernetesssl 2>&1

  mkdir -p $TMPDIR/k8s/certs
  CERTS=$(find /etc/kubernetes/ssl -type f -name *.pem | grep -v "\-key\.pem$")
  for CERT in $CERTS; do
    openssl x509 -in $CERT -text -noout > $TMPDIR/k8s/certs/$(basename $CERT) 2>&1
  done
  if [ -d /etc/kubernetes/.tmp ]; then
    mkdir -p $TMPDIR/k8s/tmpcerts
    TMPCERTS=$(find /etc/kubernetes/.tmp -type f -name *.pem | grep -v "\-key\.pem$")
    for TMPCERT in $TMPCERTS; do
      openssl x509 -in $TMPCERT -text -noout > $TMPDIR/k8s/tmpcerts/$(basename $TMPCERT) 2>&1
    done
  fi
fi

# etcd
# /var/lib/etcd contents
if [ -d /var/lib/etcd ]; then
  echo "Collecting etcd info"
  mkdir -p $TMPDIR/etcd

  find /var/lib/etcd -type f -exec ls -la {} \; > $TMPDIR/etcd/findvarlibetcd 2>&1
elif [ -d /opt/rke/var/lib/etcd ]; then
  echo "Collecting etcd info"
  mkdir -p $TMPDIR/etcd

  find /opt/rke/var/lib/etcd -type f -exec ls -la {} \; > $TMPDIR/etcd/findoptrkevarlibetcd 2>&1
fi

# /opt/rke contents
if [ -d /opt/rke/etcd-snapshots ]; then
  mkdir -p $TMPDIR/etcd

  find /opt/rke/etcd-snapshots -type f -exec ls -la {} \; > $TMPDIR/etcd/findoptrkeetcdsnaphots 2>&1
fi

# k3s
if $(command -v k3s >/dev/null 2>&1); then
  echo "Collecting k3s info"
  mkdir -p $TMPDIR/k3s/crictl
  mkdir -p $TMPDIR/k3s/logs
  mkdir -p $TMPDIR/k3s/podlogs
  mkdir -p $TMPDIR/k3s/kubectl
  k3s check-config > $TMPDIR/k3s/check-config 2>&1
  k3s kubectl get nodes -o json > $TMPDIR/k3s/kubectl/nodes 2>&1
  k3s kubectl version > $TMPDIR/k3s/kubectl/version 2>&1
  k3s kubectl get pods --all-namespaces > $TMPDIR/k3s/kubectl/pods 2>&1
  if $(grep "k3s.service" $TMPDIR/systeminfo/systemd-units > /dev/null 2>&1); then
    journalctl --unit=k3s > $TMPDIR/k3s/logs/journalctl-k3s
  fi
  for SYSTEMNAMESPACE in "${SYSTEMNAMESPACES[@]}"; do
    for SYSTEMPOD in $(k3s kubectl -n $SYSTEMNAMESPACE get pods --no-headers -o custom-columns=NAME:.metadata.name); do
      k3s kubectl -n $SYSTEMNAMESPACE logs $SYSTEMPOD > $TMPDIR/k3s/podlogs/$SYSTEMNAMESPACE-$SYSTEMPOD 2>&1
    done
  done
  k3s crictl ps -a > $TMPDIR/k3s/crictl/psa 2>&1
  k3s crictl pods > $TMPDIR/k3s/crictl/pods 2>&1
  k3s crictl info > $TMPDIR/k3s/crictl/info 2>&1
  k3s crictl stats -a > $TMPDIR/k3s/crictl/statsa 2>&1
  k3s crictl version > $TMPDIR/k3s/crictl/version 2>&1
  k3s crictl images > $TMPDIR/k3s/crictl/images 2>&1
  k3s crictl imagefsinfo > $TMPDIR/k3s/crictl/imagefsinfo 2>&1
fi

FILEDIR=$(dirname $TMPDIR)
FILENAME="$(hostname)-$(date +'%Y-%m-%d_%H_%M_%S').tar"
tar cf $FILEDIR/$FILENAME -C ${TMPDIR}/ .

if $(command -v gzip >/dev/null 2>&1); then
  echo "Compressing archive to ${FILEDIR}/${FILENAME}.gz"
  gzip ${FILEDIR}/${FILENAME}
  FILENAME="${FILENAME}.gz"
fi

echo "Created ${FILEDIR}/${FILENAME}"
echo "You can now remove ${TMPDIR}"
