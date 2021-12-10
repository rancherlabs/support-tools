#!/bin/bash
# Rancher 2.x logs collector for supported Linux distributions
# https://rancher.com/support-maintenance-terms#rancher-support-matrix

# Included namespaces
SYSTEM_NAMESPACES=(kube-system kube-public cattle-system cattle-alerting cattle-logging cattle-pipeline ingress-nginx cattle-prometheus istio-system longhorn-system cattle-global-data fleet-system fleet-default rancher-operator-system cattle-monitoring-system cattle-logging-system cattle-fleet-system cattle-fleet-local-system)

# Included container logs
KUBE_CONTAINERS=(etcd etcd-rolling-snapshots kube-apiserver kube-controller-manager kubelet kube-scheduler kube-proxy nginx-proxy)

# Included journald logs
JOURNALD_LOGS=(docker k3s rke2-agent rke2-server containerd cloud-init systemd-network kubelet kubeproxy)

# Minimum space needed to run the script (MB)
SPACE=1536

# Set TIMEOUT in seconds for select commands
TIMEOUT=60

# Default nice and ionice priorities
PRIORITY_NICE=19 # lowest
PRIORITY_IONICE="idle" # lowest

setup() {

  TMPDIR=$(mktemp -d $MKTEMP_BASEDIR) || { techo 'Creating temporary directory failed, please check options'; exit 1; }
  techo "Created ${TMPDIR}"

}

disk-space() {

  AVAILABLE=$(df -m ${TMPDIR} | tail -n 1 | awk '{ print $4 }')
  if [ "${AVAILABLE}" -lt "${SPACE}" ]
    then
      techo "${AVAILABLE} MB space free, minimum needed is ${SPACE} MB."
      DISK_FULL=1
  fi

}

sherlock() {

  if [ -z ${PRIORITY_DEFAULT} ]
    then
      echo -n "$(timestamp): Detecting available commands... "
      if $(command -v renice >/dev/null 2>&1); then
        renice -n ${PRIORITY_NICE} "$$" >/dev/null 2>&1
        echo -n "renice "
      fi
      if $(command -v ionice >/dev/null 2>&1); then
        ionice -c ${PRIORITY_IONICE} -p "$$" >/dev/null 2>&1
        echo "ionoice"
      fi
  fi

  echo -n "$(timestamp): Detecting OS... "
  if [ -f /etc/os-release ]
    then
      OSRELEASE=$(grep -w ^ID /etc/os-release | cut -d= -f2 | sed 's/"//g')
      OSVERSION=$(grep -w ^VERSION_ID /etc/os-release | cut -d= -f2 | sed 's/"//g')
      echo "${OSRELEASE} ${OSVERSION}"
    else
      echo -e "\n$(timestamp): couldn't detect OS"
  fi
  if [ -n "${DISTRO_FLAG}" ]
    then
      techo "Setting k8s distro as ${DISTRO_FLAG}"
      DISTRO="${DISTRO_FLAG}"
    else
      echo -n "$(timestamp): Detecting k8s distribution... "
      if $(command -v docker >/dev/null 2>&1)
        then
          if $(docker ps >/dev/null 2>&1)
            then
              DISTRO=rke
              echo "rke"
            else
              FOUND="rke "
          fi
      fi
      if $(command -v k3s >/dev/null 2>&1)
        then
          if $(k3s crictl ps >/dev/null 2>&1)
            then
              DISTRO=k3s
              echo "k3s"
            else
              FOUND+="k3s"
          fi
      fi
      if $(command -v rke2 >/dev/null 2>&1)
        then
          RKE2_BIN=$(dirname $(which rke2))
          if [ -f /etc/rancher/rke2/config.yaml ]
            then
              CUSTOM_DIR=$(awk '$1 ~ /data-dir:/ {print $2}' /etc/rancher/rke2/config.yaml)
          fi
          if [[ -z "${CUSTOM_DIR}" && -z "${DATA_DIR}" ]]
            then
              RKE2_DIR="/var/lib/rancher/rke2"
            else
              if [ -n "${DATA_DIR}" ]
                then
                  RKE2_DIR="${DATA_DIR}"
                else
                  RKE2_DIR="${CUSTOM_DIR}"
              fi
          fi
          export CRI_CONFIG_FILE="${RKE2_DIR}/agent/etc/crictl.yaml"
          if $(${RKE2_DIR}/bin/crictl ps >/dev/null 2>&1)
            then
              DISTRO=rke2
              echo "rke2"
            else
              FOUND+="rke2"
          fi
          techo "Detecting data-dir... ${RKE2_DIR}"
      fi
      if [ -z $DISTRO ]
        then
          echo -e "\n$(timestamp): couldn't detect k8s distro"
          if [ -n "${FOUND}" ]
            then
              techo "Found ${FOUND} but could not execute commands successfully"
          fi
      fi
  fi

  echo -n "$(timestamp): Detecting init type... "
  if $(command -v systemctl >/dev/null 2>&1)
    then
      INIT="systemd"
      echo "systemd"
    else
      INIT="other"
      echo "other"
  fi

}

system-all() {

  techo "Collecting system info"
  mkdir -p $TMPDIR/systeminfo
  hostname > $TMPDIR/systeminfo/hostname 2>&1
  hostname -f > $TMPDIR/systeminfo/hostnamefqdn 2>&1
  cp -p /etc/hosts $TMPDIR/systeminfo/etchosts 2>&1
  cp -p /etc/resolv.conf $TMPDIR/systeminfo/etcresolvconf 2>&1
  cp -p /run/systemd/resolve/resolv.conf $TMPDIR/systeminfo/systemd-resolved 2>&1
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
  vmstat --wide --timestamp 1 5 > $TMPDIR/systeminfo/vmstat 2>&1
  if [ "${OSRELEASE}" = "rancheros" ]
    then
      top -bn 1 > $TMPDIR/systeminfo/top 2>&1
    else
      COLUMNS=512 top -cbn 1 > $TMPDIR/systeminfo/top 2>&1
  fi
  cat /proc/cpuinfo > $TMPDIR/systeminfo/cpuinfo 2>&1
  cat /proc/sys/fs/file-nr > $TMPDIR/systeminfo/file-nr 2>&1
  cat /proc/sys/fs/file-max > $TMPDIR/systeminfo/file-max 2>&1
  ulimit -aH > $TMPDIR/systeminfo/ulimit-hard 2>&1
  uname -a > $TMPDIR/systeminfo/uname 2>&1
  cat /etc/*release > $TMPDIR/systeminfo/osrelease 2>&1
  if $(command -v lsblk >/dev/null 2>&1); then
    lsblk > $TMPDIR/systeminfo/lsblk 2>&1
  fi
  if $(command -v iostat >/dev/null 2>&1); then
    iostat -h -x 2 5 > $TMPDIR/systeminfo/iostathx 2>&1
  fi  
  if $(command -v pidstat >/dev/null 2>&1); then
    pidstat -drshut -p ALL 2 5 > $TMPDIR/systeminfo/pidstatx 2>&1
  fi
  lsof -Pn > $TMPDIR/systeminfo/lsof 2>&1 & timeout_cmd
  if $(command -v sysctl >/dev/null 2>&1); then
    sysctl -a > $TMPDIR/systeminfo/sysctla 2>/dev/null
  fi
  if $(command -v systemctl >/dev/null 2>&1); then
    systemctl list-units > $TMPDIR/systeminfo/systemd-units 2>&1
  fi
  if $(command -v systemctl >/dev/null 2>&1); then
    systemctl list-unit-files > $TMPDIR/systeminfo/systemd-unit-files 2>&1
  fi
  if $(command -v service >/dev/null 2>&1); then
    service --status-all > $TMPDIR/systeminfo/service-statusall 2>&1
  fi

}

system-ubuntu() {

  if $(command -v ufw >/dev/null 2>&1); then
    ufw status > $TMPDIR/systeminfo/ubuntu-ufw 2>&1
  fi
  if $(command -v apparmor_status >/dev/null 2>&1); then
    apparmor_status > $TMPDIR/systeminfo/ubuntu-apparmorstatus 2>&1
  fi
  if $(command -v dpkg >/dev/null 2>&1); then
    dpkg -l > $TMPDIR/systeminfo/packages-dpkg 2>&1
  fi

}

system-rhel() {

  systemctl status NetworkManager > $TMPDIR/systeminfo/rhel-statusnetworkmanager 2>&1
  systemctl status firewalld > $TMPDIR/systeminfo/rhel-statusfirewalld 2>&1
  if $(command -v getenforce >/dev/null 2>&1); then
    getenforce > $TMPDIR/systeminfo/rhel-getenforce 2>&1
  fi
  if $(command -v rpm >/dev/null 2>&1); then
    rpm -qa > $TMPDIR/systeminfo/packages-rpm 2>&1
  fi

}

networking() {

  techo "Collecting network info"
  mkdir -p $TMPDIR/networking
  iptables-save > $TMPDIR/networking/iptablessave 2>&1
  ip6tables-save > $TMPDIR/networking/ip6tablessave 2>&1
  if [ ! "${OSRELEASE}" = "sles" ]
    then
      IPTABLES_FLAGS="--wait 1"
  fi
  iptables $IPTABLES_FLAGS --numeric --verbose --list --table mangle > $TMPDIR/networking/iptablesmangle 2>&1
  iptables $IPTABLES_FLAGS --numeric --verbose --list --table nat > $TMPDIR/networking/iptablesnat 2>&1
  iptables $IPTABLES_FLAGS --numeric --verbose --list > $TMPDIR/networking/iptables 2>&1
  ip6tables $IPTABLES_FLAGS --numeric --verbose --list --table mangle > $TMPDIR/networking/ip6tablesmangle 2>&1
  ip6tables $IPTABLES_FLAGS --numeric --verbose --list --table nat > $TMPDIR/networking/ip6tablesnat 2>&1
  ip6tables $IPTABLES_FLAGS --numeric --verbose --list > $TMPDIR/networking/ip6tables 2>&1
  if $(command -v netstat >/dev/null 2>&1); then
    if [ "${OSRELEASE}" = "rancheros" ]
      then
        netstat -antu > $TMPDIR/networking/netstat 2>&1
      else
        netstat --programs --all --numeric --tcp --udp > $TMPDIR/networking/netstat 2>&1
        netstat --statistics > $TMPDIR/networking/netstatistics 2>&1
    fi
  fi
  if $(command -v ipvsadm >/dev/null 2>&1); then
    ipvsadm -ln > $TMPDIR/networking/ipvsadm 2>&1
  fi
  if [ -f /proc/net/xfrm_stat ]
    then
      cat /proc/net/xfrm_stat > $TMPDIR/networking/procnetxfrmstat 2>&1
  fi
  if $(command -v ip >/dev/null 2>&1); then
    ip addr show > $TMPDIR/networking/ipaddrshow 2>&1
    ip route show table all > $TMPDIR/networking/iproute 2>&1
    ip rule show > $TMPDIR/networking/iprule 2>&1
    ip -s link show > $TMPDIR/networking/iplinkshow 2>&1
  fi
  if $(command -v ifconfig >/dev/null 2>&1); then
    ifconfig -a > $TMPDIR/networking/ifconfiga
  fi
  if $(command -v ss >/dev/null 2>&1); then
    ss -anp > $TMPDIR/networking/ssanp 2>&1
    ss -itan > $TMPDIR/networking/ssitan 2>&1
    ss -uapn > $TMPDIR/networking/ssuapn 2>&1
    ss -wapn > $TMPDIR/networking/sswapn 2>&1
    ss -xapn > $TMPDIR/networking/ssxapn 2>&1
    ss -4apn > $TMPDIR/networking/ss4apn 2>&1
    ss -6apn > $TMPDIR/networking/ss6apn 2>&1
    ss -tunlp6 > $TMPDIR/networking/sstunlp6 2>&1
    ss -tunlp4 > $TMPDIR/networking/sstunlp4 2>&1
  fi
  if [ -d /etc/cni/net.d/ ]; then
    mkdir -p $TMPDIR/networking/cni
    cp -r -p /etc/cni/net.d/* $TMPDIR/networking/cni 2>&1
  fi

}

rke-logs() {

  techo "Collecting docker info"
  mkdir -p $TMPDIR/docker

  docker info > $TMPDIR/docker/dockerinfo 2>&1 & timeout_cmd
  docker ps -a > $TMPDIR/docker/dockerpsa 2>&1
  docker stats -a --no-stream > $TMPDIR/docker/dockerstats 2>&1 & timeout_cmd
  docker images > $TMPDIR/docker/dockerimages 2>&1 & timeout_cmd

  if [ -f /etc/docker/daemon.json ]; then
    cp -p /etc/docker/daemon.json $TMPDIR/docker/etcdockerdaemon.json
  fi

}

k3s-logs() {

  techo "Collecting k3s info"
  mkdir -p $TMPDIR/k3s/crictl
  k3s check-config > $TMPDIR/k3s/check-config 2>&1
  k3s crictl ps -a > $TMPDIR/k3s/crictl/psa 2>&1
  k3s crictl pods > $TMPDIR/k3s/crictl/pods 2>&1
  k3s crictl info > $TMPDIR/k3s/crictl/info 2>&1
  k3s crictl stats -a > $TMPDIR/k3s/crictl/statsa 2>&1
  k3s crictl version > $TMPDIR/k3s/crictl/version 2>&1
  k3s crictl images > $TMPDIR/k3s/crictl/images 2>&1
  k3s crictl imagefsinfo > $TMPDIR/k3s/crictl/imagefsinfo 2>&1
  k3s crictl stats -a > $TMPDIR/k3s/crictl/statsa 2>&1
  if [ -f /etc/systemd/system/k3s.service ]
    then
      cp -p /etc/systemd/system/k3s.service $TMPDIR/k3s/k3s.service
  fi

}

rke2-logs() {

  techo "Collecting rke2 info"
  mkdir -p $TMPDIR/rke2/crictl
  ${RKE2_BIN}/rke2 --version > $TMPDIR/rke2/version 2>&1
  ${RKE2_DIR}/bin/crictl --version > $TMPDIR/rke2/crictl/crictl-version 2>&1
  ${RKE2_DIR}/bin/containerd --version > $TMPDIR/rke2/crictl/containerd-version 2>&1
  ${RKE2_DIR}/bin/runc --version > $TMPDIR/rke2/crictl/runc-version 2>&1
  ${RKE2_DIR}/bin/crictl ps -a > $TMPDIR/rke2/crictl/psa 2>&1
  ${RKE2_DIR}/bin/crictl pods > $TMPDIR/rke2/crictl/pods 2>&1
  ${RKE2_DIR}/bin/crictl info > $TMPDIR/rke2/crictl/info 2>&1
  ${RKE2_DIR}/bin/crictl stats -a > $TMPDIR/rke2/crictl/statsa 2>&1
  ${RKE2_DIR}/bin/crictl version > $TMPDIR/rke2/crictl/version 2>&1
  ${RKE2_DIR}/bin/crictl images > $TMPDIR/rke2/crictl/images 2>&1
  ${RKE2_DIR}/bin/crictl imagefsinfo > $TMPDIR/rke2/crictl/imagefsinfo 2>&1
  ${RKE2_DIR}/bin/crictl stats -a > $TMPDIR/rke2/crictl/statsa 2>&1
  if [ -f /usr/local/lib/systemd/system/rke2-agent.service ]
    then
      cp -p /usr/local/lib/systemd/system/rke2*.service $TMPDIR/rke2/
  fi

}

rke-k8s() {

  techo "Collecting rancher logs"
  # Discover any server or agent running
  mkdir -p $TMPDIR/rancher/{containerlogs,containerinspect}
  RANCHERSERVERS=$(docker ps -a | grep -E "k8s_rancher_rancher|rancher/rancher:|rancher/rancher " | awk '{ print $1 }')
  RANCHERAGENTS=$(docker ps -a | grep -E "k8s_agent_cattle|rancher/rancher-agent:|rancher/rancher-agent " | awk '{ print $1 }')

  for RANCHERSERVER in $RANCHERSERVERS; do
    docker inspect $RANCHERSERVER > $TMPDIR/rancher/containerinspect/server-$RANCHERSERVER 2>&1
    docker logs $SINCE_FLAG -t $RANCHERSERVER > $TMPDIR/rancher/containerlogs/server-$RANCHERSERVER 2>&1
  done

  for RANCHERAGENT in $RANCHERAGENTS; do
    docker inspect $RANCHERAGENT > $TMPDIR/rancher/containerinspect/agent-$RANCHERAGENT 2>&1
    docker logs $SINCE_FLAG -t $RANCHERAGENT 2>&1 | sed 's/with token.*/with token REDACTED/g' > $TMPDIR/rancher/containerlogs/agent-$RANCHERAGENT 2>&1
  done

  # K8s Docker container logging
  techo "Collecting k8s component logs"
  mkdir -p $TMPDIR/k8s/{containerlogs,containerinspect}
  for KUBE_CONTAINER in "${KUBE_CONTAINERS[@]}"; do
    if [ "$(docker ps -a -q -f name=$KUBE_CONTAINER)" ]; then
      docker inspect $KUBE_CONTAINER > $TMPDIR/k8s/containerinspect/$KUBE_CONTAINER 2>&1
      docker logs $SINCE_FLAG -t $KUBE_CONTAINER > $TMPDIR/k8s/containerlogs/$KUBE_CONTAINER 2>&1
    fi
  done

  # System pods
  techo "Collecting system pod logs"
  mkdir -p $TMPDIR/k8s/{podlogs,podinspect}
  for SYSTEM_NAMESPACE in "${SYSTEM_NAMESPACES[@]}"; do
    CONTAINERS=$(docker ps -a --filter name=$SYSTEM_NAMESPACE --format "{{.Names}}")
    for CONTAINER in $CONTAINERS; do
      docker inspect $CONTAINER > $TMPDIR/k8s/podinspect/$CONTAINER 2>&1
      docker logs $SINCE_FLAG -t $CONTAINER > $TMPDIR/k8s/podlogs/$CONTAINER 2>&1
    done
  done

  # Node and pod overview
  mkdir -p $TMPDIR/k8s/kubectl
  KUBECONFIG=/etc/kubernetes/ssl/kubecfg-kube-node.yaml
  docker exec kubelet kubectl get nodes -o wide --kubeconfig=$KUBECONFIG > $TMPDIR/k8s/kubectl/nodes 2>&1
  docker exec kubelet kubectl describe nodes --kubeconfig=$KUBECONFIG > $TMPDIR/k8s/kubectl/nodesdescribe 2>&1
  docker exec kubelet kubectl get pods -o wide --all-namespaces --kubeconfig=$KUBECONFIG > $TMPDIR/k8s/kubectl/pods 2>&1
  docker exec kubelet kubectl get svc -o wide --all-namespaces --kubeconfig=$KUBECONFIG > $TMPDIR/k8s/kubectl/services 2>&1
  docker exec kubelet kubectl get endpoints -o wide --all-namespaces --kubeconfig=$KUBECONFIG > $TMPDIR/k8s/kubectl/endpoints 2>&1
  docker exec kubelet kubectl get configmaps --all-namespaces --kubeconfig=$KUBECONFIG > $TMPDIR/k8s/kubectl/configmaps 2>&1
  docker exec kubelet kubectl get namespaces --kubeconfig=$KUBECONFIG > $TMPDIR/k8s/kubectl/namespaces 2>&1

  techo "Collecting nginx-proxy info"
  if docker inspect nginx-proxy >/dev/null 2>&1; then
    mkdir -p $TMPDIR/k8s/nginx-proxy
    docker exec nginx-proxy cat /etc/nginx/nginx.conf > $TMPDIR/k8s/nginx-proxy/nginx.conf 2>&1
  fi

}

k3s-k8s() {

  techo "Collecting k3s cluster logs"
  if [ -d /var/lib/rancher/k3s/agent ]; then
    mkdir -p $TMPDIR/k3s/kubectl
    KUBECONFIG=/var/lib/rancher/k3s/agent/kubelet.kubeconfig
    k3s kubectl --kubeconfig=$KUBECONFIG get nodes -o wide > $TMPDIR/k3s/kubectl/nodes 2>&1
    k3s kubectl --kubeconfig=$KUBECONFIG describe nodes > $TMPDIR/k3s/kubectl/nodesdescribe 2>&1
    k3s kubectl --kubeconfig=$KUBECONFIG version > $TMPDIR/k3s/kubectl/version 2>&1
    k3s kubectl --kubeconfig=$KUBECONFIG get pods -o wide --all-namespaces > $TMPDIR/k3s/kubectl/pods 2>&1
    k3s kubectl --kubeconfig=$KUBECONFIG get svc -o wide --all-namespaces > $TMPDIR/k3s/kubectl/services 2>&1
  fi

  if [ -d /var/lib/rancher/k3s/server ]; then
    unset KUBECONFIG
    kubectl api-resources > $TMPDIR/k3s/kubectl/api-resources 2>&1
    K3S_OBJECTS=(clusterroles clusterrolebindings crds mutatingwebhookconfigurations namespaces nodes pv validatingwebhookconfigurations)
    K3S_OBJECTS_NAMESPACED=(apiservices configmaps cronjobs deployments daemonsets endpoints events helmcharts hpa ingress jobs leases pods pvc replicasets roles rolebindings statefulsets)
    for OBJECT in "${K3S_OBJECTS[@]}"; do
      k3s kubectl get ${OBJECT} -o wide > $TMPDIR/k3s/kubectl/${OBJECT} 2>&1
    done
    for OBJECT in "${K3S_OBJECTS_NAMESPACED[@]}"; do
      k3s kubectl get ${OBJECT} --all-namespaces -o wide > $TMPDIR/k3s/kubectl/${OBJECT} 2>&1
    done
  fi

  mkdir -p $TMPDIR/k3s/podlogs
  techo "Collecting system pod logs"
  if [ -d /var/lib/rancher/k3s/server ]; then
    for SYSTEM_NAMESPACE in "${SYSTEM_NAMESPACES[@]}"; do
      for SYSTEM_POD in $(k3s kubectl -n $SYSTEM_NAMESPACE get pods --no-headers -o custom-columns=NAME:.metadata.name); do
        k3s kubectl -n $SYSTEM_NAMESPACE logs --all-containers $SYSTEM_POD > $TMPDIR/k3s/podlogs/$SYSTEM_NAMESPACE-$SYSTEM_POD 2>&1
        k3s kubectl -n $SYSTEM_NAMESPACE logs -p --all-containers $SYSTEM_POD > $TMPDIR/k3s/podlogs/$SYSTEM_NAMESPACE-$SYSTEM_POD-previous 2>&1
      done
    done
  elif [ -d /var/lib/rancher/k3s/agent ]; then
    for SYSTEM_NAMESPACE in "${SYSTEM_NAMESPACES[@]}"; do
      if ls -d /var/log/pods/$SYSTEM_NAMESPACE* > /dev/null 2>&1; then
        cp -r -p /var/log/pods/$SYSTEM_NAMESPACE* $TMPDIR/k3s/podlogs/
      fi
    done
  fi

}

rke2-k8s() {

  techo "Collecting rke2 cluster logs"
  if [ -f ${RKE2_DIR}/agent/kubelet.kubeconfig ]; then
    mkdir -p $TMPDIR/rke2/kubectl
    KUBECONFIG=${RKE2_DIR}/agent/kubelet.kubeconfig
    ${RKE2_DIR}/bin/kubectl --kubeconfig=$KUBECONFIG get nodes -o wide > $TMPDIR/rke2/kubectl/nodes 2>&1
    ${RKE2_DIR}/bin/kubectl --kubeconfig=$KUBECONFIG describe nodes > $TMPDIR/rke2/kubectl/nodesdescribe 2>&1
    ${RKE2_DIR}/bin/kubectl --kubeconfig=$KUBECONFIG version > $TMPDIR/rke2/kubectl/version 2>&1
    ${RKE2_DIR}/bin/kubectl --kubeconfig=$KUBECONFIG get pods -o wide --all-namespaces > $TMPDIR/rke2/kubectl/pods 2>&1
    ${RKE2_DIR}/bin/kubectl --kubeconfig=$KUBECONFIG get svc -o wide --all-namespaces > $TMPDIR/rke2/kubectl/services 2>&1
  fi

  if [ -f /etc/rancher/rke2/rke2.yaml ]; then
    KUBECONFIG=/etc/rancher/rke2/rke2.yaml
    ${RKE2_DIR}/bin/kubectl --kubeconfig=$KUBECONFIG api-resources > $TMPDIR/rke2/kubectl/api-resources 2>&1
    RKE2_OBJECTS=(clusterroles clusterrolebindings crds mutatingwebhookconfigurations namespaces nodes pv validatingwebhookconfigurations)
    RKE2_OBJECTS_NAMESPACED=(apiservices configmaps cronjobs deployments daemonsets endpoints events helmcharts hpa ingress jobs leases pods pvc replicasets roles rolebindings statefulsets)
    for OBJECT in "${RKE2_OBJECTS[@]}"; do
      ${RKE2_DIR}/bin/kubectl --kubeconfig=$KUBECONFIG get ${OBJECT} -o wide > $TMPDIR/rke2/kubectl/${OBJECT} 2>&1
    done
    for OBJECT in "${RKE2_OBJECTS_NAMESPACED[@]}"; do
      ${RKE2_DIR}/bin/kubectl --kubeconfig=$KUBECONFIG get ${OBJECT} --all-namespaces -o wide > $TMPDIR/rke2/kubectl/${OBJECT} 2>&1
    done
  fi

  mkdir -p $TMPDIR/rke2/podlogs
  techo "Collecting rke2 system pod logs"
  if [ -f /etc/rancher/rke2/rke2.yaml ]; then
    KUBECONFIG=/etc/rancher/rke2/rke2.yaml
    for SYSTEM_NAMESPACE in "${SYSTEM_NAMESPACES[@]}"; do
      for SYSTEM_POD in $(${RKE2_DIR}/bin/kubectl --kubeconfig=$KUBECONFIG -n $SYSTEM_NAMESPACE get pods --no-headers -o custom-columns=NAME:.metadata.name); do
        ${RKE2_DIR}/bin/kubectl --kubeconfig=$KUBECONFIG -n $SYSTEM_NAMESPACE logs --all-containers $SYSTEM_POD > $TMPDIR/rke2/podlogs/$SYSTEM_NAMESPACE-$SYSTEM_POD 2>&1
        ${RKE2_DIR}/bin/kubectl --kubeconfig=$KUBECONFIG -n $SYSTEM_NAMESPACE logs -p --all-containers $SYSTEM_POD > $TMPDIR/rke2/podlogs/$SYSTEM_NAMESPACE-$SYSTEM_POD-previous 2>&1
      done
    done
  elif [ -f ${RKE2_DIR}/agent/kubelet.kubeconfig ]; then
    for SYSTEM_NAMESPACE in "${SYSTEM_NAMESPACES[@]}"; do
      if ls -d /var/log/pods/$SYSTEM_NAMESPACE* > /dev/null 2>&1; then
        cp -r -p /var/log/pods/$SYSTEM_NAMESPACE* $TMPDIR/rke2/podlogs/
      fi
    done
  fi

  techo "Collecting rke2 agent/server logs"
  for RKE2_LOG_DIR in agent server
    do
      if [ -d ${RKE2_DIR}/${RKE2_LOG_DIR}/logs/ ]; then
        cp -rp ${RKE2_DIR}/${RKE2_LOG_DIR}/logs/ $TMPDIR/rke2/${RKE2_LOG_DIR}-logs
      fi
  done

}

var-log() {

  techo "Collecting system logs from /var/log"
  mkdir -p $TMPDIR/systemlogs
  cp -p /var/log/syslog* /var/log/messages* /var/log/kern* /var/log/docker* /var/log/system-docker* /var/log/cloud-init* /var/log/audit/* $TMPDIR/systemlogs 2>/dev/null

  for STAT_PACKAGE in atop sa sysstat
    do
      if [ -d /var/log/${STAT_PACKAGE} ]
        then
          mkdir -p $TMPDIR/systemlogs/${STAT_PACKAGE}-data
          find /var/log/${STAT_PACKAGE} -mtime -14 -exec cp -p {} $TMPDIR/systemlogs/${STAT_PACKAGE}-data \;
      fi
  done

}

journald-log() {

  techo "Collecting system logs from journald"
  mkdir -p $TMPDIR/journald
  for JOURNALD_LOG in "${JOURNALD_LOGS[@]}"; do
    if $(grep $JOURNALD_LOG.service $TMPDIR/systeminfo/systemd-units > /dev/null 2>&1); then
      journalctl $SINCE_FLAG --unit=$JOURNALD_LOG > $TMPDIR/journald/$JOURNALD_LOG
    fi
  done

}

rke-certs() {

  # K8s directory state
  techo "Collecting k8s directory state"
  mkdir -p $TMPDIR/k8s/directories
  if [ -d /opt/rke/etc/kubernetes/ssl ]; then
    find /opt/rke/etc/kubernetes/ssl -type f -exec ls -la {} \; > $TMPDIR/k8s/directories/findoptrkeetckubernetesssl 2>&1
  elif [ -d /etc/kubernetes/ssl ]; then
    find /etc/kubernetes/ssl -type f -exec ls -la {} \; > $TMPDIR/k8s/directories/findetckubernetesssl 2>&1
  fi

  techo "Collecting k8s certificates"
  mkdir -p $TMPDIR/k8s/certs
  if [ -d /opt/rke/etc/kubernetes/ssl ]; then
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

}

k3s-certs() {

  if [ -d /var/lib/rancher/k3s ]
    then
      techo "Collecting k3s directory state"
      mkdir -p $TMPDIR/k3s/directories
      ls -lah /var/lib/rancher/k3s/agent > $TMPDIR/k3s/directories/k3sagent 2>&1
      ls -lah /var/lib/rancher/k3s/server/manifests > $TMPDIR/k3s/directories/k3sservermanifests 2>&1
      ls -lah /var/lib/rancher/k3s/server/tls > $TMPDIR/k3s/directories/k3sservertls 2>&1
      techo "Collecting k3s certificates"
      mkdir -p $TMPDIR/k3s/certs/{agent,server}
      AGENT_CERTS=$(find /var/lib/rancher/k3s/agent -maxdepth 1 -type f -name "*.crt" | grep -v "\-ca.crt$")
      for CERT in $AGENT_CERTS
        do
          openssl x509 -in $CERT -text -noout > $TMPDIR/k3s/certs/agent/$(basename $CERT) 2>&1
      done
      if [ -d /var/lib/rancher/k3s/server/tls ]; then
        techo "Collecting k3s server certificates"
        SERVER_CERTS=$(find /var/lib/rancher/k3s/server/tls -maxdepth 1 -type f -name "*.crt" | grep -v "\-ca.crt$")
        for CERT in $SERVER_CERTS
          do
            openssl x509 -in $CERT -text -noout > $TMPDIR/k3s/certs/server/$(basename $CERT) 2>&1
        done
      fi
  fi

}

rke2-certs() {

  if [ -d ${RKE2_DIR} ]
    then
      techo "Collecting rke2 directory state"
      mkdir -p $TMPDIR/rke2/directories
      ls -lah ${RKE2_DIR}/agent > $TMPDIR/rke2/directories/rke2agent 2>&1
      ls -lah ${RKE2_DIR}/server/manifests > $TMPDIR/rke2/directories/rke2servermanifests 2>&1
      ls -lah ${RKE2_DIR}/server/tls > $TMPDIR/rke2/directories/rke2servertls 2>&1
      techo "Collecting rke2 certificates"
      mkdir -p $TMPDIR/rke2/certs/{agent,server}
      AGENT_CERTS=$(find ${RKE2_DIR}/agent -maxdepth 1 -type f -name "*.crt" | grep -v "\-ca.crt$")
      for CERT in $AGENT_CERTS
        do
          openssl x509 -in $CERT -text -noout > $TMPDIR/rke2/certs/agent/$(basename $CERT) 2>&1
      done
      if [ -d ${RKE2_DIR}/server/tls ]; then
        techo "Collecting rke2 server certificates"
        SERVER_CERTS=$(find ${RKE2_DIR}/server/tls -maxdepth 1 -type f -name "*.crt" | grep -v "\-ca.crt$")
        for CERT in $SERVER_CERTS
          do
            openssl x509 -in $CERT -text -noout > $TMPDIR/rke2/certs/server/$(basename $CERT) 2>&1
        done
      fi
  fi

}

rke-etcd() {

  techo "Collecting rke etcd info"
  mkdir -p $TMPDIR/etcd
  if [ -d /var/lib/etcd ]; then
    find /var/lib/etcd -type f -exec ls -la {} \; > $TMPDIR/etcd/findvarlibetcd 2>&1
  elif [ -d /opt/rke/var/lib/etcd ]; then
    find /opt/rke/var/lib/etcd -type f -exec ls -la {} \; > $TMPDIR/etcd/findoptrkevarlibetcd 2>&1
  fi

  if [ -d /opt/rke/etcd-snapshots ]; then
    find /opt/rke/etcd-snapshots -type f -exec ls -la {} \; > $TMPDIR/etcd/findoptrkeetcdsnapshots 2>&1
  fi

  if docker ps --format='{{.Names}}' | grep -q ^etcd$ >/dev/null 2>&1; then
    techo "Collecting etcdctl output"
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
    docker exec -e ETCDCTL_ENDPOINTS=$(docker exec etcd /bin/sh -c "etcdctl $PARAM member list | cut -d, -f5 | sed -e 's/ //g' | paste -sd ','") etcd etcdctl endpoint status --write-out table > $TMPDIR/etcd/endpointstatus 2>&1
    docker exec -e ETCDCTL_ENDPOINTS=$(docker exec etcd /bin/sh -c "etcdctl $PARAM member list | cut -d, -f5 | sed -e 's/ //g' | paste -sd ','") etcd etcdctl endpoint health > $TMPDIR/etcd/endpointhealth 2>&1
    docker exec etcd sh -c "etcdctl $PARAM alarm list" > $TMPDIR/etcd/alarmlist 2>&1
  fi

}

rke2-etcd() {

  RKE2_ETCD=$(${RKE2_DIR}/bin/crictl ps --quiet --label io.kubernetes.container.name=etcd --state running)
  if [ ! -z ${RKE2_ETCD} ]; then
    techo "Collecting rke2 etcd info"
    mkdir -p $TMPDIR/etcd
    ETCDCTL_ENDPOINTS=$(${RKE2_DIR}/bin/crictl exec ${RKE2_ETCD} /bin/sh -c "etcdctl --cert ${RKE2_DIR}/server/tls/etcd/server-client.crt --key ${RKE2_DIR}/server/tls/etcd/server-client.key --cacert ${RKE2_DIR}/server/tls/etcd/server-ca.crt member list | cut -d, -f5 | sed -e 's/ //g' | paste -sd ','")
    ${RKE2_DIR}/bin/crictl exec ${RKE2_ETCD} /bin/sh -c "ETCDCTL_ENDPOINTS=$ETCDCTL_ENDPOINTS etcdctl --cert ${RKE2_DIR}/server/tls/etcd/server-client.crt --key ${RKE2_DIR}/server/tls/etcd/server-client.key --cacert ${RKE2_DIR}/server/tls/etcd/server-ca.crt --write-out table endpoint status" > $TMPDIR/etcd/endpointstatus 2>&1
    ${RKE2_DIR}/bin/crictl exec ${RKE2_ETCD} /bin/sh -c "ETCDCTL_ENDPOINTS=$ETCDCTL_ENDPOINTS etcdctl --cert ${RKE2_DIR}/server/tls/etcd/server-client.crt --key ${RKE2_DIR}/server/tls/etcd/server-client.key --cacert ${RKE2_DIR}/server/tls/etcd/server-ca.crt endpoint health" > $TMPDIR/etcd/endpointhealth 2>&1
    ${RKE2_DIR}/bin/crictl exec ${RKE2_ETCD} /bin/sh -c "ETCDCTL_ENDPOINTS=$ETCDCTL_ENDPOINTS etcdctl --cert ${RKE2_DIR}/server/tls/etcd/server-client.crt --key ${RKE2_DIR}/server/tls/etcd/server-client.key --cacert ${RKE2_DIR}/server/tls/etcd/server-ca.crt alarm list" > $TMPDIR/etcd/alarmlist 2>&1
  fi

  if [ -d "${RKE2_DIR}/server/db/etcd" ]; then
    find "${RKE2_DIR}/server/db/etcd" -type f -exec ls -la {} \; > $TMPDIR/etcd/findserverdbetcd 2>&1
  fi
  if [ -d "${RKE2_DIR}/server/db/snapshots" ]; then
    find "${RKE2_DIR}/server/db/snapshots" -type f -exec ls -la {} \; > $TMPDIR/etcd/findserverdbsnapshots 2>&1
  fi

}

timeout_cmd() {

  TIMEOUT_EXCEEDED_MSG="$1 command timed out, killing process to prevent hanging."
  WPID=$!
  sleep $TIMEOUT && if kill -0 $WPID > /dev/null 2>&1
    then
      echo "$1 command timed out, killing process to prevent hanging."; kill $WPID &> /dev/null;
  fi & KPID=$!; wait $WPID

}

archive() {

  FILEDIR=$(dirname $TMPDIR)
  FILENAME="$(hostname)-$(date +'%Y-%m-%d_%H_%M_%S').tar"
  tar --create --file ${FILEDIR}/${FILENAME} --directory ${TMPDIR}/ .
  ## gzip separately for Rancher OS
  gzip ${FILEDIR}/${FILENAME}

  techo "Created ${FILEDIR}/${FILENAME}.gz"

}

cleanup() {

  techo "Removing ${TMPDIR}"
  rm -r -f "${TMPDIR}" >/dev/null 2>&1

}

help() {

  echo "Rancher 2.x logs-collector
  Usage: rancher2_logs_collector.sh [ -d <directory> -s <days> -r <k8s distribution> -p -f ]

  All flags are optional

  -c    Custom data-dir for RKE2 (ex: -c /opt/rke2)
  -d    Output directory for temporary storage and .tar.gz archive (ex: -d /var/tmp)
  -s    Number of days history to collect from container and journald logs (ex: -s 7)
  -r    Override k8s distribution if not automatically detected (rke|k3s|rke2)
  -p    When supplied runs with the default nice/ionice priorities, otherwise use the lowest priorities
  -f    Force log collection if the minimum space isn't available"

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

while getopts "c:d:s:r:fph" opt; do
  case $opt in
    c)
      DATA_DIR="${OPTARG}"
      ;;
    d)
      MKTEMP_BASEDIR="-p ${OPTARG}"
      ;;
    s)
      START=$(date -d "-${OPTARG} days" '+%Y-%m-%d')
      SINCE_FLAG="--since ${START}"
      ;;
    r)
      DISTRO_FLAG="${OPTARG}"
      ;;
    f)
      FORCE=1
      ;;
    p)
      PRIORITY_DEFAULT=1
      ;;
    h)
      help && exit 0
      ;;
    :)
      techo "Option -$OPTARG requires an argument."
      exit 1
      ;;
    *)
      help && exit 0
  esac
done

setup
disk-space
if [ -n "${DISK_FULL}" ]
  then
    if [ -z "${FORCE}" ]
      then
        techo "Cleaning up and exiting"
        cleanup
        exit 1
      else
        techo "-f (force) used, continuing"
    fi
fi
sherlock
system-all
networking
if [[ "${OSRELEASE}" = "rhel" || "${OSRELEASE}" = "centos" ]]
  then
    system-rhel
elif [ "${OSRELEASE}" = "ubuntu" ]
  then
    system-ubuntu
fi
if [ "${DISTRO}" = "rke" ]
  then
    rke-logs
    rke-k8s
    rke-certs
    rke-etcd
elif [ "${DISTRO}" = "k3s" ]
  then
    k3s-logs
    k3s-k8s
    k3s-certs
elif [ "${DISTRO}" = "rke2" ]
  then
    rke2-logs
    rke2-k8s
    rke2-certs
    rke2-etcd
fi
var-log
if [ "${INIT}" = "systemd" ]
  then
    journald-log
fi
archive
cleanup
