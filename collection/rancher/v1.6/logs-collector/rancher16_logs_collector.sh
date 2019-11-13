#!/bin/bash
#Check if we're running as root.
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root"
  exit 1
fi

# Create temp directory
TMPDIR=$(mktemp -d)

#Set TIMEOUT in seconds for select commands
TIMEOUT=60

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
mkdir -p $TMPDIR/systeminfo
hostname > $TMPDIR/systeminfo/hostname 2>&1
hostname -f > $TMPDIR/systeminfo/hostnamefqdn 2>&1
cat /etc/hosts > $TMPDIR/systeminfo/etchosts 2>&1
cat /etc/resolv.conf > $TMPDIR/systeminfo/etcresolvconf 2>&1
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
ps aux > $TMPDIR/systeminfo/psaux 2>&1

timeout_start_msg "lsof"
lsof -Pn >$TMPDIR/systeminfo/lsof 2>&1 & timeout_cmd
timeout_done_msg

if $(command -v sysctl >/dev/null 2>&1); then
  sysctl -a > $TMPDIR/systeminfo/sysctla 2>/dev/null
fi
# OS: Ubuntu
if $(command -v ufw >/dev/null 2>&1); then
  ufw status > $TMPDIR/systeminfo/ubuntu-ufw 2>&1
fi
if $(command -v apparmor_status >/dev/null 2>&1); then
  apparmor_status > $TMPDIR/systeminfo/ubuntu-apparmorstatus 2>&1
fi
# OS: RHEL
if [ -f /etc/redhat-release ]; then
  systemctl status NetworkManager > $TMPDIR/systeminfo/rhel-statusnetworkmanager 2>&1
  systemctl status firewalld > $TMPDIR/systeminfo/rhel-statusfirewalld 2>&1
  if $(command -v getenforce >/dev/null 2>&1); then
  getenforce > $TMPDIR/systeminfo/rhel-getenforce 2>&1
  fi
fi

# Docker
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

# Networking
mkdir -p $TMPDIR/networking
iptables-save > $TMPDIR/networking/iptablessave 2>&1
cat /proc/net/xfrm_stat > $TMPDIR/networking/procnetxfrmstat 2>&1
if $(command -v ip >/dev/null 2>&1); then
  ip addr show > $TMPDIR/networking/ipaddrshow 2>&1
  ip route > $TMPDIR/networking/iproute 2>&1
fi
if $(command -v ifconfig >/dev/null 2>&1); then
  ifconfig -a > $TMPDIR/networking/ifconfiga
fi

# System logging
mkdir -p $TMPDIR/systemlogs
cp /var/log/syslog* /var/log/messages* /var/log/kern* /var/log/docker* /var/log/system-docker* /var/log/audit/* $TMPDIR/systemlogs 2>/dev/null

# Rancher logging
# Discover any server or agent running
mkdir -p $TMPDIR/rancher/containerinspect
mkdir -p $TMPDIR/rancher/containerlogs
RANCHERSERVERS=$(docker ps -a | grep -E "rancher/server:|rancher/server |rancher/enterprise:|rancher/enterprise " | awk '{ print $1 }')
RANCHERAGENTS=$(docker ps -a | grep -E "rancher/agent:|rancher/agent " | awk '{ print $1 }')

for RANCHERSERVER in $RANCHERSERVERS; do
  docker inspect $RANCHERSERVER > $TMPDIR/rancher/containerinspect/server-$RANCHERSERVER 2>&1
  docker logs -t $RANCHERSERVER > $TMPDIR/rancher/containerlogs/server-$RANCHERSERVER 2>&1
  for LOGFILE in $(docker exec $RANCHERSERVER ls -1 /var/lib/cattle/logs 2>/dev/null); do
    mkdir -p $TMPDIR/rancher/cattlelogs/
    docker cp $RANCHERSERVER:/var/lib/cattle/logs/$LOGFILE $TMPDIR/rancher/cattlelogs/$LOGFILE-$RANCHERSERVER
  done
done

for RANCHERAGENT in $RANCHERAGENTS; do
  docker inspect $RANCHERAGENT > $TMPDIR/rancher/containerinspect/agent-$RANCHERAGENT 2>&1
  docker logs -t $RANCHERAGENT > $TMPDIR/rancher/containerlogs/agent-$RANCHERAGENT 2>&1
done

# Infastructure/System stack containers
for INFRACONTAINER in $(docker ps -a --filter label=io.rancher.container.system=true --format "{{.Names}}"); do
  mkdir -p $TMPDIR/infrastacks/containerlogs
  mkdir -p $TMPDIR/infrastacks/containerinspect
  docker inspect $INFRACONTAINER > $TMPDIR/infrastacks/containerinspect/$INFRACONTAINER 2>&1
  docker logs -t $INFRACONTAINER > $TMPDIR/infrastacks/containerlogs/$INFRACONTAINER 2>&1
done

# IPsec
IPSECROUTERS=$(docker ps --filter label=io.rancher.stack_service.name=ipsec/ipsec/router --format "{{.Names}}")
for IPSECROUTER in "${IPSECROUTERS[@]}"; do
  mkdir -p $TMPDIR/ipsec
  docker exec $IPSECROUTER bash -cx "swanctl --list-conns && swanctl --list-sas && ip -s xfrm state && ip -s xfrm policy && cat /proc/net/xfrm_stat && sysctl -a" > $TMPDIR/ipsec/ipsec.info.${IPSECROUTER}.log 2>&1
done

# Networkmanager
NETWORKMANAGERS=$(docker ps --filter label=io.rancher.stack_service.name=network-services/network-manager --format "{{.Names}}")
for NETWORKMANAGER in "${NETWORKMANAGERS[@]}"; do
  mkdir -p $TMPDIR/networkmanager
  docker exec $NETWORKMANAGER bash -cx "ip link && ip addr && ip neighbor && ip route && conntrack -L && iptables-save && sysctl -a && cat /etc/resolv.conf && uname -a" > $TMPDIR/networkmanager/nm.network.info.${NETWORKMANAGER}.log 2>&1
done

# System pods
SYSTEMNAMESPACES=(kube-system)
for SYSTEMNAMESPACE in "${SYSTEMNAMESPACES[@]}"; do
  CONTAINERS=$(docker ps -a --filter name=$SYSTEMNAMESPACE --format "{{.Names}}")
  for CONTAINER in $CONTAINERS; do
    mkdir -p $TMPDIR/k8s/podlogs
    mkdir -p $TMPDIR/k8s/podinspect
    docker inspect $CONTAINER > $TMPDIR/k8s/podinspect/$CONTAINER 2>&1
    docker logs -t $CONTAINER > $TMPDIR/k8s/podlogs/$CONTAINER 2>&1
  done
done

# etcd
ETCDCONTAINERS=$(docker ps --filter label=io.rancher.stack_service.name=kubernetes/etcd --format "{{.Names}}")
for ETCDCONTAINER in $ETCDCONTAINERS; do
  mkdir -p $TMPDIR/etcd
  docker exec $ETCDCONTAINER etcdctl cluster-health > $TMPDIR/etcd/cluster-health-${ETCDCONTAINER} 2>&1
  find $(docker inspect $ETCDCONTAINER --format '{{ range .Mounts }}{{ if eq .Destination "/pdata" }}{{ .Source }}{{ end }}{{ end }}') -type f -exec ls -la {} \; > $TMPDIR/etcd/findetcddata 2>&1
done

FILENAME="$(hostname)-$(date +'%Y-%m-%d_%H_%M_%S').tar"
tar cf /tmp/$FILENAME -C ${TMPDIR}/ .

if $(command -v gzip >/dev/null 2>&1); then
  gzip /tmp/${FILENAME}
  FILENAME="${FILENAME}.gz"
fi

echo "Created /tmp/${FILENAME}"
echo "You can now remove ${TMPDIR}"
