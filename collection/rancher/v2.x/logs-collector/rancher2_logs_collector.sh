#!/bin/bash
# Rancher 2.x logs collector for supported Linux distributions
# https://rancher.com/support-maintenance-terms#rancher-support-matrix

# Included namespaces
SYSTEM_NAMESPACES=(kube-system kube-public cattle-system cattle-alerting cattle-logging cattle-pipeline cattle-provisioning-capi-system cattle-resources-system ingress-nginx cattle-prometheus istio-system longhorn-system cattle-global-data fleet-system fleet-default rancher-operator-system cattle-monitoring-system cattle-logging-system cattle-fleet-system cattle-fleet-local-system tigera-operator calico-system suse-observability)

# Included container logs
KUBE_CONTAINERS=(etcd etcd-rolling-snapshots kube-apiserver kube-controller-manager kubelet kube-scheduler kube-proxy nginx-proxy)

# Included journald logs
JOURNALD_LOGS=(docker k3s rke2-agent rke2-server containerd cloud-init systemd-network kubelet kubeproxy rancher-system-agent)

# Included /var/log files
VAR_LOG_FILES=(syslog messages kern docker cloud-init audit/ dmesg)

# Days of /var/log files to include
VAR_LOG_DAYS=7

# Minimum space needed to run the script (MB)
SPACE=1536

# Set TIMEOUT in seconds for select commands
TIMEOUT=60

# Default nice and ionice priorities
PRIORITY_NICE=19 # lowest
PRIORITY_IONICE="idle" # lowest

# Set the dmesg date to use English, as non-English environments such as Japanese will display non-English characters in it.
LANG=C

setup() {

  TMPDIR_BASE=$(mktemp -d $MKTEMP_BASEDIR) || { techo 'Creating temporary directory failed, please check options'; exit 1; }
  techo "Created ${TMPDIR_BASE}"
  LOGNAME="$(hostname)-$(date +'%Y-%m-%d_%H_%M_%S')"
  mkdir -p "${TMPDIR_BASE}/${LOGNAME}"
  TMPDIR="${TMPDIR_BASE}/${LOGNAME}"
  export PATH=$PATH:/usr/local/bin:/opt/rke2/bin:/opt/bin

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
      echo -n "$(timestamp): Detecting available commands... " | tee -a $TMPDIR/collector-output.log
      if $(command -v renice >/dev/null 2>&1); then
        renice -n ${PRIORITY_NICE} "$$" >/dev/null 2>&1
        echo -n "renice " | tee -a $TMPDIR/collector-output.log
      fi
      if $(command -v ionice >/dev/null 2>&1); then
        ionice -c ${PRIORITY_IONICE} -p "$$" >/dev/null 2>&1
        echo "ionoice" | tee -a $TMPDIR/collector-output.log
      fi
  fi

  echo -n "$(timestamp): Detecting OS... " | tee -a $TMPDIR/collector-output.log
  if [ -f /etc/os-release ]
    then
      OSRELEASE=$(grep -w ^ID /etc/os-release | cut -d= -f2 | sed 's/"//g')
      OSVERSION=$(grep -w ^VERSION_ID /etc/os-release | cut -d= -f2 | sed 's/"//g')
      echo "${OSRELEASE} ${OSVERSION}" | tee -a $TMPDIR/collector-output.log
    else
      echo -e "\n$(timestamp): couldn't detect OS" | tee -a $TMPDIR/collector-output.log
  fi
  if [ -n "${DISTRO_FLAG}" ]
    then
      techo "Setting k8s distro as ${DISTRO_FLAG}"
      DISTRO="${DISTRO_FLAG}"
      if [ "${DISTRO_FLAG}" = "rke2" ]
        then
          rke2-setup
      fi
      techo "Using RKE2 binary... ${RKE2_BIN}"
      techo "Using RKE2 data-dir... ${RKE2_DATA_DIR}"
    else
      echo -n "$(timestamp): Detecting k8s distribution... " | tee -a $TMPDIR/collector-output.log
      if $(command -v k3s >/dev/null 2>&1)
        then
          if $(k3s crictl ps >/dev/null 2>&1)
            then
              DISTRO=k3s
              echo "k3s" | tee -a $TMPDIR/collector-output.log
            else
              FOUND+="k3s "
          fi
      fi
      if $(command -v rke2 >/dev/null 2>&1)
        then
          rke2-setup
          if $(${RKE2_DATA_DIR}/bin/crictl ps >/dev/null 2>&1)
            then
              DISTRO=rke2
              echo "rke2" | tee -a $TMPDIR/collector-output.log
            else
              FOUND+="rke2 "
          fi
          techo "Using RKE2 binary... ${RKE2_BIN}"
          techo "Using RKE2 data-dir... ${RKE2_DATA_DIR}"
      fi
      if $(command -v docker >/dev/null 2>&1)
        then
          if $(docker ps >/dev/null 2>&1)
            then
              if [ -z "${DISTRO}" ]
                then
                  DISTRO=rke
                  echo "rke" | tee -a $TMPDIR/collector-output.log
                else
                  techo "Found rke, but another distribution ("${DISTRO}") was also found, using "${DISTRO}"..."
              fi
            else
              FOUND+="rke "
          fi
      fi
      if [ -z ${DISTRO} ]
        then
          echo -e "\n$(timestamp): couldn't detect k8s distro" | tee -a $TMPDIR/collector-output.log
          if [ -n "${FOUND}" ]
            then
              techo "Found ${FOUND} but could not execute commands successfully"
          fi
      fi
  fi

  echo -n "$(timestamp): Detecting init type... " | tee -a $TMPDIR/collector-output.log
  if $(command -v systemctl >/dev/null 2>&1)
    then
      INIT="systemd"
      echo "systemd" | tee -a $TMPDIR/collector-output.log
    else
      INIT="other"
      echo "other" | tee -a $TMPDIR/collector-output.log
  fi

}

rke2-setup() {

  which rke2 > /dev/null 2>&1
  if [ $? -eq 0 ]
    then
      RKE2_BIN=$(which rke2)
    else
      techo "rke2 commands run, but the binary can't be found"
  fi

  if [ -n "${FLAG_DATA_DIR}" ]
    then
      if [ -d "${FLAG_DATA_DIR}" ]
        then
          RKE2_DATA_DIR="${FLAG_DATA_DIR}"
        else
          techo "A custom data-dir was provided, but the directory doesn't exist"
      fi
  fi

  if [ -z "${RKE2_DATA_DIR}" ]
    then
      if [ -f /etc/rancher/rke2/config.yaml ]
        then
          CUSTOM_DATA_DIR=$(awk '$1 ~ /data-dir:/ {print $2}' /etc/rancher/rke2/config.yaml)
      fi
      if [ -f /etc/rancher/rke2/config.d/50-rancher.yaml ]
        then
          CUSTOM_DATA_DIR=$(awk '$1 ~ /data-dir:/ {print $2}' /etc/rancher/rke2/config.d/50-rancher.yaml)
      fi
      if [[ -n "${CUSTOM_DATA_DIR}" ]]
        then
          RKE2_DATA_DIR="${CUSTOM_DATA_DIR}"
        else
          RKE2_DATA_DIR="/var/lib/rancher/rke2"
      fi
  fi

  export CRI_CONFIG_FILE="${RKE2_DATA_DIR}/agent/etc/crictl.yaml"

}

system-all() {

  techo "Collecting system info"
  mkdir -p $TMPDIR/systeminfo
  hostname > $TMPDIR/systeminfo/hostname 2>&1
  hostname -f > $TMPDIR/systeminfo/hostnamefqdn 2>&1
  cp -p /etc/hosts $TMPDIR/systeminfo/etchosts 2>&1
  cp -p /etc/resolv.conf $TMPDIR/systeminfo/etcresolvconf 2>&1
  if [ -e /run/systemd/resolve/resolv.conf ]
    then
      cp -p /run/systemd/resolve/resolv.conf $TMPDIR/systeminfo/systemd-resolved 2>&1
  fi
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
  if $(command -v conntrack >/dev/null 2>&1); then
    conntrack -S > $TMPDIR/systeminfo/conntrack
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

system-sles() {

  if $(command -v rpm >/dev/null 2>&1); then
    rpm -qa > $TMPDIR/systeminfo/packages-rpm 2>&1
  fi
  if $(command -v apparmor_status >/dev/null 2>&1); then
    apparmor_status > $TMPDIR/systeminfo/sles-apparmorstatus 2>&1
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
  if $(command -v nft >/dev/null 2>&1); then
    nft list ruleset  > $TMPDIR/networking/nft_ruleset 2>&1
  fi
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
    ip neighbour > $TMPDIR/networking/ipneighbour 2>&1
    ip rule show > $TMPDIR/networking/iprule 2>&1
    ip -s link show > $TMPDIR/networking/iplinkshow 2>&1
    ip -6 neighbour > $TMPDIR/networking/ipv6neighbour 2>&1
    ip -6 rule show > $TMPDIR/networking/ipv6rule 2>&1
    ip -6 route show > $TMPDIR/networking/ipv6route 2>&1
    ip -6 addr show > $TMPDIR/networking/ipv6addrshow 2>&1
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

provisioning-crds() {

  if [[ "${DISTRO}" = "rke" && -f /etc/kubernetes/ssl/kubecfg-kube-controller-manager.yaml ]]
    then
      KUBECONFIG=/etc/kubernetes/ssl/kubecfg-kube-controller-manager.yaml
      ctlcmd="docker exec kubelet kubectl --kubeconfig=${KUBECONFIG}"
      CONTROL_PLANE=1
  elif [[ "${DISTRO}" = "k3s" && -d /var/lib/rancher/${DISTRO}/server ]]
    then
      KUBECONFIG=/etc/rancher/${DISTRO}/k3s.yaml
      ctlcmd="k3s kubectl --kubeconfig=${KUBECONFIG}"
      CONTROL_PLANE=1
  elif [[ "${DISTRO}" = "rke2" && -f /etc/rancher/${DISTRO}/rke2.yaml ]]
    then
      KUBECONFIG=/etc/rancher/${DISTRO}/rke2.yaml
      ctlcmd="${RKE2_DATA_DIR}/bin/kubectl --kubeconfig=${KUBECONFIG}"
      CONTROL_PLANE=1
  fi

  if [ -n "$CONTROL_PLANE" ]
    then
      RANCHER_PODS=$(${ctlcmd} get pod -l app=rancher -n cattle-system --ignore-not-found | wc -l)
      if [ $RANCHER_PODS -ne 0 ]
        then
          techo "Collecting provisioning info"
          mkdir -p $TMPDIR/${DISTRO}/kubectl/rancher-prov
          CRDS=("clusters.management.cattle.io" "nodes.management.cattle.io" "custommachines.rke.cattle.io" "etcdsnapshots.rke.cattle.io" "rkebootstraps.rke.cattle.io" "rkebootstraptemplates.rke.cattle.io" "rkeclusters.rke.cattle.io" "rkecontrolplanes.rke.cattle.io" "clusters.provisioning.cattle.io" "amazonec2machines.rke-machine.cattle.io" "amazonec2machinetemplates.rke-machine.cattle.io" "azuremachines.rke-machine.cattle.io" "azuremachinetemplates.rke-machine.cattle.io" "digitaloceanmachines.rke-machine.cattle.io" "digitaloceanmachinetemplates.rke-machine.cattle.io" "harvestermachines.rke-machine.cattle.io" "harvestermachinetemplates.rke-machine.cattle.io" "linodemachines.rke-machine.cattle.io" "linodemachinetemplates.rke-machine.cattle.io" "vmwarevspheremachines.rke-machine.cattle.io" "vmwarevspheremachinetemplates.rke-machine.cattle.io" "amazonec2configs.rke-machine-config.cattle.io" "azureconfigs.rke-machine-config.cattle.io" "digitaloceanconfigs.rke-machine-config.cattle.io" "harvesterconfigs.rke-machine-config.cattle.io" "linodeconfigs.rke-machine-config.cattle.io" "vmwarevsphereconfigs.rke-machine-config.cattle.io")

          for item in "${CRDS[@]}"; do
            ${ctlcmd} get ${item} -o yaml -A > $TMPDIR/${DISTRO}/kubectl/rancher-prov/${item} 2>&1
          done

          ${ctlcmd} get configmap cattle-controllers -n kube-system -o yaml > $TMPDIR/${DISTRO}/kubectl/rancher-prov/cattle-controller-cfgmap 2>&1
      fi
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
  mkdir -p $TMPDIR/${DISTRO}/crictl
  k3s check-config > $TMPDIR/${DISTRO}/check-config 2>&1
  k3s crictl ps -a > $TMPDIR/${DISTRO}/crictl/psa 2>&1
  k3s crictl pods > $TMPDIR/${DISTRO}/crictl/pods 2>&1
  k3s crictl info > $TMPDIR/${DISTRO}/crictl/info 2>&1
  k3s crictl stats -a > $TMPDIR/${DISTRO}/crictl/statsa 2>&1
  k3s crictl version > $TMPDIR/${DISTRO}/crictl/version 2>&1
  k3s crictl images > $TMPDIR/${DISTRO}/crictl/images 2>&1
  k3s crictl imagefsinfo > $TMPDIR/${DISTRO}/crictl/imagefsinfo 2>&1
  k3s crictl stats -a > $TMPDIR/${DISTRO}/crictl/statsa 2>&1
  if [ -f /etc/systemd/system/${DISTRO}.service ]
    then
      sed -e '/--token/{n;s/.*/\t<token redacted>/}' \
          -e '/--etcd-s3-access-key/{n;s/.*/\t<access-key redacted>/}' \
          -e '/--etcd-s3-secret-key/{n;s/.*/\t<secret-key redacted>/}' \
          /etc/systemd/system/${DISTRO}*.service >& $TMPDIR/${DISTRO}/${DISTRO}.service
  fi
  if [ -f /etc/rancher/${DISTRO}/config.yaml ]
    then
      grep -Ev "token|access-key|secret-key" /etc/rancher/${DISTRO}/config.yaml >& $TMPDIR/${DISTRO}/config.yaml
  fi
  if [ -d /etc/rancher/${DISTRO}/config.yaml.d ]
    then
      for _FILE in $(ls /etc/rancher/${DISTRO}/config.yaml.d)
        do
          grep -Ev "token|access-key|secret-key" /etc/rancher/${DISTRO}/config.yaml.d/$_FILE >& $TMPDIR/${DISTRO}/$_FILE
      done
  fi

}

rke2-logs() {

  techo "Collecting rke2 info"
  mkdir -p $TMPDIR/${DISTRO}/crictl
  ${RKE2_BIN} --version > $TMPDIR/${DISTRO}/version 2>&1
  ${RKE2_DATA_DIR}/bin/crictl --version > $TMPDIR/${DISTRO}/crictl/crictl-version 2>&1
  ${RKE2_DATA_DIR}/bin/containerd --version > $TMPDIR/${DISTRO}/crictl/containerd-version 2>&1
  ${RKE2_DATA_DIR}/bin/runc --version > $TMPDIR/${DISTRO}/crictl/runc-version 2>&1
  ${RKE2_DATA_DIR}/bin/crictl ps -a > $TMPDIR/${DISTRO}/crictl/psa 2>&1
  ${RKE2_DATA_DIR}/bin/crictl pods > $TMPDIR/${DISTRO}/crictl/pods 2>&1
  ${RKE2_DATA_DIR}/bin/crictl info > $TMPDIR/${DISTRO}/crictl/info 2>&1
  ${RKE2_DATA_DIR}/bin/crictl stats -a > $TMPDIR/${DISTRO}/crictl/statsa 2>&1
  ${RKE2_DATA_DIR}/bin/crictl version > $TMPDIR/${DISTRO}/crictl/version 2>&1
  ${RKE2_DATA_DIR}/bin/crictl images > $TMPDIR/${DISTRO}/crictl/images 2>&1
  ${RKE2_DATA_DIR}/bin/crictl imagefsinfo > $TMPDIR/${DISTRO}/crictl/imagefsinfo 2>&1
  ${RKE2_DATA_DIR}/bin/crictl stats -a > $TMPDIR/${DISTRO}/crictl/statsa 2>&1
  if [ -f /usr/local/lib/systemd/system/rke2-agent.service ]
    then
      cp -p /usr/local/lib/systemd/system/${DISTRO}*.service $TMPDIR/${DISTRO}/
  fi
  if [ -f /var/lib/rancher/${DISTRO}/agent/containerd/containerd.log ]
    then
      cp -p /var/lib/rancher/${DISTRO}/agent/containerd/containerd.log $TMPDIR/${DISTRO}
  fi
  if [ -f /etc/rancher/${DISTRO}/config.yaml ]
    then
      grep -Ev "token|access-key|secret-key" /etc/rancher/${DISTRO}/config.yaml >& $TMPDIR/${DISTRO}/config.yaml
  fi
  if [ -d /etc/rancher/${DISTRO}/config.yaml.d ]
    then
      for _FILE in $(ls /etc/rancher/${DISTRO}/config.yaml.d)
        do
          grep -Ev "token|access-key|secret-key" /etc/rancher/${DISTRO}/config.yaml.d/$_FILE >& $TMPDIR/${DISTRO}/$_FILE
      done
  fi

}

rke-k8s() {

  techo "Collecting rancher logs"
  mkdir -p $TMPDIR/rancher/{containerlogs,containerinspect}
  RANCHERSERVERS=$(docker ps -a | grep -E "k8s_rancher_rancher|rancher/rancher:|rancher/rancher " | awk '{ print $1 }')
  RANCHERAGENTS=$(docker ps -a | grep -E "k8s_agent_cattle|rancher/rancher-agent:|rancher/rancher-agent " | awk '{ print $1 }')

  for RANCHERSERVER in $RANCHERSERVERS; do
    docker inspect $RANCHERSERVER > $TMPDIR/rancher/containerinspect/server-$RANCHERSERVER 2>&1
    docker logs $SINCE_FLAG $UNTIL_FLAG -t $RANCHERSERVER > $TMPDIR/rancher/containerlogs/server-$RANCHERSERVER 2>&1
  done

  for RANCHERAGENT in $RANCHERAGENTS; do
    docker inspect $RANCHERAGENT > $TMPDIR/rancher/containerinspect/agent-$RANCHERAGENT 2>&1
    docker logs $SINCE_FLAG $UNTIL_FLAG -t $RANCHERAGENT 2>&1 | sed 's/with token.*/with token REDACTED/g' > $TMPDIR/rancher/containerlogs/agent-$RANCHERAGENT 2>&1
  done

  techo "Collecting k8s component logs"
  mkdir -p $TMPDIR/${DISTRO}/{containerlogs,containerinspect}
  for KUBE_CONTAINER in "${KUBE_CONTAINERS[@]}"; do
    if [ "$(docker ps -a -q -f name=$KUBE_CONTAINER)" ]; then
      docker inspect $KUBE_CONTAINER > $TMPDIR/${DISTRO}/containerinspect/$KUBE_CONTAINER 2>&1
      docker logs $SINCE_FLAG $UNTIL_FLAG -t $KUBE_CONTAINER > $TMPDIR/${DISTRO}/containerlogs/$KUBE_CONTAINER 2>&1
    fi
  done

  techo "Collecting system pod logs"
  mkdir -p $TMPDIR/${DISTRO}/{podlogs,podinspect}
  for SYSTEM_NAMESPACE in "${SYSTEM_NAMESPACES[@]}"; do
    CONTAINERS=$(docker ps -a --filter name=$SYSTEM_NAMESPACE --format "{{.Names}}")
    for CONTAINER in $CONTAINERS; do
      docker inspect $CONTAINER > $TMPDIR/${DISTRO}/podinspect/$CONTAINER 2>&1
      docker logs $SINCE_FLAG $UNTIL_FLAG -t $CONTAINER > $TMPDIR/${DISTRO}/podlogs/$CONTAINER 2>&1
    done
  done

  mkdir -p $TMPDIR/${DISTRO}/kubectl
  KUBECONFIG=/etc/kubernetes/ssl/kubecfg-kube-node.yaml
  docker exec kubelet kubectl get nodes -o wide --kubeconfig=$KUBECONFIG > $TMPDIR/${DISTRO}/kubectl/nodes 2>&1
  docker exec kubelet kubectl describe nodes --kubeconfig=$KUBECONFIG > $TMPDIR/${DISTRO}/kubectl/nodesdescribe 2>&1
  docker exec kubelet kubectl get pods -o wide --all-namespaces --kubeconfig=$KUBECONFIG > $TMPDIR/${DISTRO}/kubectl/pods 2>&1
  docker exec kubelet kubectl get svc -o wide --all-namespaces --kubeconfig=$KUBECONFIG > $TMPDIR/${DISTRO}/kubectl/services 2>&1
  docker exec kubelet kubectl get endpoints -o wide --all-namespaces --kubeconfig=$KUBECONFIG > $TMPDIR/${DISTRO}/kubectl/endpoints 2>&1
  docker exec kubelet kubectl get configmaps --all-namespaces --kubeconfig=$KUBECONFIG > $TMPDIR/${DISTRO}/kubectl/configmaps 2>&1
  docker exec kubelet kubectl get namespaces --kubeconfig=$KUBECONFIG > $TMPDIR/${DISTRO}/kubectl/namespaces 2>&1

  techo "Collecting nginx-proxy info"
  if docker inspect nginx-proxy >/dev/null 2>&1; then
    mkdir -p $TMPDIR/${DISTRO}/nginx-proxy
    docker exec nginx-proxy cat /etc/nginx/nginx.conf > $TMPDIR/${DISTRO}/nginx-proxy/nginx.conf 2>&1
  fi

}

k3s-k8s() {

  techo "Collecting k3s cluster logs"
  if [ -d /var/lib/rancher/${DISTRO}/agent ]; then
    mkdir -p $TMPDIR/${DISTRO}/kubectl
    KUBECONFIG=/var/lib/rancher/${DISTRO}/agent/kubelet.kubeconfig
    k3s kubectl --kubeconfig=$KUBECONFIG get nodes -o wide > $TMPDIR/${DISTRO}/kubectl/nodes 2>&1
    k3s kubectl --kubeconfig=$KUBECONFIG describe nodes > $TMPDIR/${DISTRO}/kubectl/nodesdescribe 2>&1
    k3s kubectl --kubeconfig=$KUBECONFIG version > $TMPDIR/${DISTRO}/kubectl/version 2>&1
    k3s kubectl --kubeconfig=$KUBECONFIG get pods -o wide --all-namespaces > $TMPDIR/${DISTRO}/kubectl/pods 2>&1
    k3s kubectl --kubeconfig=$KUBECONFIG get svc -o wide --all-namespaces > $TMPDIR/${DISTRO}/kubectl/services 2>&1
  fi

  if [ -d /var/lib/rancher/${DISTRO}/server ]; then
    unset KUBECONFIG
    k3s kubectl api-resources > $TMPDIR/${DISTRO}/kubectl/api-resources 2>&1
    K3S_OBJECTS=(clusterroles clusterrolebindings crds mutatingwebhookconfigurations namespaces nodes pv validatingwebhookconfigurations)
    K3S_OBJECTS_NAMESPACED=(apiservices configmaps cronjobs deployments daemonsets endpoints events helmcharts hpa ingress jobs leases networkpolicies pods pvc replicasets roles rolebindings statefulsets)
    for OBJECT in "${K3S_OBJECTS[@]}"; do
      k3s kubectl get ${OBJECT} -o wide > $TMPDIR/${DISTRO}/kubectl/${OBJECT} 2>&1
    done
    for OBJECT in "${K3S_OBJECTS_NAMESPACED[@]}"; do
      k3s kubectl get ${OBJECT} --all-namespaces -o wide > $TMPDIR/${DISTRO}/kubectl/${OBJECT} 2>&1
    done
  fi

  mkdir -p $TMPDIR/${DISTRO}/podlogs
  techo "Collecting system pod logs"
  if [ -d /var/lib/rancher/${DISTRO}/server ]; then
    for SYSTEM_NAMESPACE in "${SYSTEM_NAMESPACES[@]}"; do
      for SYSTEM_POD in $(k3s kubectl -n $SYSTEM_NAMESPACE get pods --no-headers -o custom-columns=NAME:.metadata.name); do
        k3s kubectl -n $SYSTEM_NAMESPACE logs --all-containers $SYSTEM_POD > $TMPDIR/${DISTRO}/podlogs/$SYSTEM_NAMESPACE-$SYSTEM_POD 2>&1
        k3s kubectl -n $SYSTEM_NAMESPACE logs -p --all-containers $SYSTEM_POD > $TMPDIR/${DISTRO}/podlogs/$SYSTEM_NAMESPACE-$SYSTEM_POD-previous 2>&1
      done
    done
  elif [ -d /var/lib/rancher/${DISTRO}/agent ]; then
    for SYSTEM_NAMESPACE in "${SYSTEM_NAMESPACES[@]}"; do
      if ls -d /var/log/pods/$SYSTEM_NAMESPACE* > /dev/null 2>&1; then
        cp -r -p /var/log/pods/$SYSTEM_NAMESPACE* $TMPDIR/${DISTRO}/podlogs/
      fi
    done
  fi

}

rke2-k8s() {

  techo "Collecting rke2 cluster logs"
  if [ -f ${RKE2_DATA_DIR}/agent/kubelet.kubeconfig ]; then
    mkdir -p $TMPDIR/${DISTRO}/kubectl
    KUBECONFIG=${RKE2_DATA_DIR}/agent/kubelet.kubeconfig
    ${RKE2_DATA_DIR}/bin/kubectl --kubeconfig=$KUBECONFIG get nodes -o wide > $TMPDIR/${DISTRO}/kubectl/nodes 2>&1
    ${RKE2_DATA_DIR}/bin/kubectl --kubeconfig=$KUBECONFIG describe nodes > $TMPDIR/${DISTRO}/kubectl/nodesdescribe 2>&1
    ${RKE2_DATA_DIR}/bin/kubectl --kubeconfig=$KUBECONFIG version > $TMPDIR/${DISTRO}/kubectl/version 2>&1
    ${RKE2_DATA_DIR}/bin/kubectl --kubeconfig=$KUBECONFIG get pods -o wide --all-namespaces > $TMPDIR/${DISTRO}/kubectl/pods 2>&1
    ${RKE2_DATA_DIR}/bin/kubectl --kubeconfig=$KUBECONFIG get svc -o wide --all-namespaces > $TMPDIR/${DISTRO}/kubectl/services 2>&1
  fi

  if [ -f /etc/rancher/${DISTRO}/rke2.yaml ]; then
    KUBECONFIG=/etc/rancher/${DISTRO}/rke2.yaml
    ${RKE2_DATA_DIR}/bin/kubectl --kubeconfig=$KUBECONFIG api-resources > $TMPDIR/${DISTRO}/kubectl/api-resources 2>&1
    RKE2_OBJECTS=(clusterroles clusterrolebindings crds mutatingwebhookconfigurations namespaces nodes pv validatingwebhookconfigurations)
    RKE2_OBJECTS_NAMESPACED=(apiservices configmaps cronjobs deployments daemonsets endpoints events helmcharts hpa ingress jobs leases networkpolicies pods pvc replicasets roles rolebindings statefulsets)
    for OBJECT in "${RKE2_OBJECTS[@]}"; do
      ${RKE2_DATA_DIR}/bin/kubectl --kubeconfig=$KUBECONFIG get ${OBJECT} -o wide > $TMPDIR/${DISTRO}/kubectl/${OBJECT} 2>&1
    done
    for OBJECT in "${RKE2_OBJECTS_NAMESPACED[@]}"; do
      ${RKE2_DATA_DIR}/bin/kubectl --kubeconfig=$KUBECONFIG get ${OBJECT} --all-namespaces -o wide > $TMPDIR/${DISTRO}/kubectl/${OBJECT} 2>&1
    done
  fi

  mkdir -p $TMPDIR/${DISTRO}/podlogs
  techo "Collecting rke2 system pod logs"
  if [ -f /etc/rancher/${DISTRO}/rke2.yaml ]; then
    KUBECONFIG=/etc/rancher/${DISTRO}/rke2.yaml
    for SYSTEM_NAMESPACE in "${SYSTEM_NAMESPACES[@]}"; do
      for SYSTEM_POD in $(${RKE2_DATA_DIR}/bin/kubectl --kubeconfig=$KUBECONFIG -n $SYSTEM_NAMESPACE get pods --no-headers -o custom-columns=NAME:.metadata.name); do
        ${RKE2_DATA_DIR}/bin/kubectl --kubeconfig=$KUBECONFIG -n $SYSTEM_NAMESPACE logs --all-containers $SYSTEM_POD > $TMPDIR/${DISTRO}/podlogs/$SYSTEM_NAMESPACE-$SYSTEM_POD 2>&1
        ${RKE2_DATA_DIR}/bin/kubectl --kubeconfig=$KUBECONFIG -n $SYSTEM_NAMESPACE logs -p --all-containers $SYSTEM_POD > $TMPDIR/${DISTRO}/podlogs/$SYSTEM_NAMESPACE-$SYSTEM_POD-previous 2>&1
      done
    done
  elif [ -f ${RKE2_DATA_DIR}/agent/kubelet.kubeconfig ]; then
    for SYSTEM_NAMESPACE in "${SYSTEM_NAMESPACES[@]}"; do
      if ls -d /var/log/pods/$SYSTEM_NAMESPACE* > /dev/null 2>&1; then
        cp -r -p /var/log/pods/$SYSTEM_NAMESPACE* $TMPDIR/${DISTRO}/podlogs/
      fi
    done
  fi

  if [ -d ${RKE2_DATA_DIR}/agent/pod-manifests ]; then
    techo "Collecting rke2 static pod manifests"
    mkdir -p $TMPDIR/${DISTRO}/pod-manifests
    cp -p ${RKE2_DATA_DIR}/agent/pod-manifests/* $TMPDIR/${DISTRO}/pod-manifests
  fi

  techo "Collecting rke2 agent/server logs"
  for RKE2_LOG_DIR in agent server
    do
      if [ -d ${RKE2_DATA_DIR}/${RKE2_LOG_DIR}/logs/ ]; then
        cp -rp ${RKE2_DATA_DIR}/${RKE2_LOG_DIR}/logs/ $TMPDIR/${DISTRO}/${RKE2_LOG_DIR}-logs
      fi
  done

}

kubeadm-k8s() {

  KUBEADM_DIR="/etc/kubernetes/"
  KUBEADM_STATIC_DIR="/etc/kubernetes/manifests/"
  if ! $(command -v kubeadm >/dev/null 2>&1); then
    techo "error: kubeadm command not found"
    exit 1
  fi

  if ! $(command -v kubectl >/dev/null 2>&1); then
    techo "error: kubectl command not found"
    exit 1
  fi

  KUBECONFIG=${KUBECONFIG:"$USER/.kube/config"}
  techo "Collecting k8s kubeadm cluster logs"
  mkdir -p $TMPDIR/kubeadm/kubectl
  kubectl --kubeconfig=$KUBECONFIG get nodes -o wide > $TMPDIR/kubeadm/kubectl/nodes 2>&1
  kubectl --kubeconfig=$KUBECONFIG describe nodes > $TMPDIR/kubeadm/kubectl/nodesdescribe 2>&1
  kubectl --kubeconfig=$KUBECONFIG version > $TMPDIR/kubeadm/kubectl/version 2>&1
  kubectl --kubeconfig=$KUBECONFIG get pods -o wide --all-namespaces > $TMPDIR/kubeadm/kubectl/pods 2>&1
  kubectl --kubeconfig=$KUBECONFIG get svc -o wide --all-namespaces > $TMPDIR/kubeadm/kubectl/services 2>&1
  kubectl --kubeconfig=$KUBECONFIG cluster-info dump > $TMPDIR/kubeadm/kubectl/cluster-info_dump 2>&1

  kubectl --kubeconfig=$KUBECONFIG api-resources > $TMPDIR/kubeadm/kubectl/api-resources 2>&1
  KUBEADM_OBJECTS=(clusterroles clusterrolebindings crds mutatingwebhookconfigurations namespaces nodes pv validatingwebhookconfigurations)
  KUBEADM_OBJECTS_NAMESPACED=(apiservices configmaps cronjobs deployments daemonsets endpoints events helmcharts hpa ingress jobs leases pods pvc replicasets roles rolebindings statefulsets)
  for OBJECT in "${KUBEADM_OBJECTS[@]}"; do
    kubectl --kubeconfig=$KUBECONFIG get ${OBJECT} -o wide > $TMPDIR/kubeadm/kubectl/${OBJECT} 2>&1
  done
  for OBJECT in "${KUBEADM_OBJECTS_NAMESPACED[@]}"; do
    kubectl --kubeconfig=$KUBECONFIG get ${OBJECT} --all-namespaces -o wide > $TMPDIR/kubeadm/kubectl/${OBJECT} 2>&1
  done

  mkdir -p $TMPDIR/kubeadm/podlogs
  techo "Collecting k8s kubeadm system pod logs"
  for SYSTEM_NAMESPACE in "${SYSTEM_NAMESPACES[@]}"; do
    for SYSTEM_POD in $(kubectl --kubeconfig=$KUBECONFIG -n $SYSTEM_NAMESPACE get pods --no-headers -o custom-columns=NAME:.metadata.name); do
      kubectl --kubeconfig=$KUBECONFIG -n $SYSTEM_NAMESPACE logs --all-containers $SYSTEM_POD > $TMPDIR/kubeadm/podlogs/$SYSTEM_NAMESPACE-$SYSTEM_POD 2>&1
      kubectl --kubeconfig=$KUBECONFIG -n $SYSTEM_NAMESPACE logs -p --all-containers $SYSTEM_POD > $TMPDIR/kubeadm/podlogs/$SYSTEM_NAMESPACE-$SYSTEM_POD-previous 2>&1
    done
  done
  for SYSTEM_NAMESPACE in "${SYSTEM_NAMESPACES[@]}"; do
    if ls -d /var/log/pods/$SYSTEM_NAMESPACE* > /dev/null 2>&1; then
      cp -r -p /var/log/pods/$SYSTEM_NAMESPACE* $TMPDIR/kubeadm/podlogs/
    fi
  done

  techo "Collecting k8s kubeadm metrics"
  kubectl --kubeconfig=$KUBECONFIG top node > $TMPDIR/kubeadm/metrics_pod 2>&1
  kubectl --kubeconfig=$KUBECONFIG top pod > $TMPDIR/kubeadm/metrics_nodes 2>&1
  kubectl --kubeconfig=$KUBECONFIG top pod --containers=true > $TMPDIR/kubeadm/metrics_containers 2>&1

  techo "Collecting k8s kubeadm static pods info and containers logs"
  if [ -d /var/log/containers/ ]; then
     cp -rp /var/log/containers $TMPDIR/kubeadm/containers-varlogs
  fi
  if [ -d $KUBEADM_STATIC_DIR ]; then
     ls -lah $KUBEADM_STATIC_DIR > $TMPDIR/kubeadm/staticpodlist 2>&1
  fi

}

var-log() {

  if [ "${OBFUSCATE}" ]
    then
      EXCLUDE_FILES="! ( -name "*.gz" -o -name "*.bz2" -o -name "*.xz" )"
  fi

  if [ -n "${START_DAY}" ]
    then
      VAR_LOG_DAYS=${START_DAY}
  fi

  techo "Collecting system logs from /var/log"
  mkdir -p $TMPDIR/systemlogs

  for LOG_FILE in "${VAR_LOG_FILES[@]}"
    do
      ls /var/log/${LOG_FILE}* > /dev/null 2>&1
      if [ $? -eq 0 ]
        then
          find /var/log/${LOG_FILE}* -mtime -${VAR_LOG_DAYS} -type f ${EXCLUDE_FILES} -exec cp -p {} $TMPDIR/systemlogs/ \;
      fi
  done

  for STAT_PACKAGE in atop sa sysstat
    do
      if [ -d /var/log/${STAT_PACKAGE} ]
        then
          mkdir -p $TMPDIR/systemlogs/${STAT_PACKAGE}-data
          find /var/log/${STAT_PACKAGE} -mtime -${VAR_LOG_DAYS} -type f ${EXCLUDE_FILES} -exec cp -p {} $TMPDIR/systemlogs/${STAT_PACKAGE}-data \;
      fi
  done

}

journald-log() {

  techo "Collecting system logs from journald"
  mkdir -p $TMPDIR/journald
  for JOURNALD_LOG in "${JOURNALD_LOGS[@]}"; do
    if $(grep $JOURNALD_LOG.service $TMPDIR/systeminfo/systemd-units > /dev/null 2>&1); then
      journalctl $SINCE_FLAG $UNTIL_FLAG --unit=$JOURNALD_LOG > $TMPDIR/journald/$JOURNALD_LOG
    fi
  done

}

rke-certs() {

  techo "Collecting k8s directory state"
  mkdir -p $TMPDIR/${DISTRO}/directories
  if [ -d /opt/rke/etc/kubernetes/ssl ]; then
    find /opt/rke/etc/kubernetes/ssl -type f -exec ls -la {} \; > $TMPDIR/${DISTRO}/directories/findoptrkeetckubernetesssl 2>&1
  elif [ -d /etc/kubernetes/ssl ]; then
    find /etc/kubernetes/ssl -type f -exec ls -la {} \; > $TMPDIR/${DISTRO}/directories/findetckubernetesssl 2>&1
  fi

  techo "Collecting k8s certificates"
  mkdir -p $TMPDIR/${DISTRO}/certs
  if [ -d /opt/rke/etc/kubernetes/ssl ]; then
    CERTS=$(find /opt/rke/etc/kubernetes/ssl -type f -name *.pem | grep -v "\-key\.pem$")
    for CERT in $CERTS; do
      openssl x509 -in $CERT -text -noout > $TMPDIR/${DISTRO}/certs/$(basename $CERT) 2>&1
    done
    if [ -d /opt/rke/etc/kubernetes/.tmp ]; then
      mkdir -p $TMPDIR/${DISTRO}/tmpcerts
      TMPCERTS=$(find /opt/rke/etc/kubernetes/.tmp -type f -name *.pem | grep -v "\-key\.pem$")
      for TMPCERT in $TMPCERTS; do
        openssl x509 -in $TMPCERT -text -noout > $TMPDIR/${DISTRO}/tmpcerts/$(basename $TMPCERT) 2>&1
      done
    fi
  elif [ -d /etc/kubernetes/ssl ]; then
    CERTS=$(find /etc/kubernetes/ssl -type f -name *.pem | grep -v "\-key\.pem$")
    for CERT in $CERTS; do
      openssl x509 -in $CERT -text -noout > $TMPDIR/${DISTRO}/certs/$(basename $CERT) 2>&1
    done
    if [ -d /etc/kubernetes/.tmp ]; then
      mkdir -p $TMPDIR/${DISTRO}/tmpcerts
      TMPCERTS=$(find /etc/kubernetes/.tmp -type f -name *.pem | grep -v "\-key\.pem$")
      for TMPCERT in $TMPCERTS; do
        openssl x509 -in $TMPCERT -text -noout > $TMPDIR/${DISTRO}/tmpcerts/$(basename $TMPCERT) 2>&1
      done
    fi
  fi

}

k3s-certs() {

  if [ -d /var/lib/rancher/k3s ]
    then
      techo "Collecting k3s directory state"
      mkdir -p $TMPDIR/${DISTRO}/directories
      ls -lah /var/lib/rancher/${DISTRO}/agent > $TMPDIR/${DISTRO}/directories/k3sagent 2>&1
      ls -lahR /var/lib/rancher/${DISTRO}/server/manifests > $TMPDIR/${DISTRO}/directories/k3sservermanifests 2>&1
      ls -lahR /var/lib/rancher/${DISTRO}/server/tls > $TMPDIR/${DISTRO}/directories/k3sservertls 2>&1
      techo "Collecting k3s certificates"
      mkdir -p $TMPDIR/${DISTRO}/certs/{agent,server}
      AGENT_CERTS=$(find /var/lib/rancher/${DISTRO}/agent -maxdepth 1 -type f -name "*.crt" | grep -v "\-ca.crt$")
      for CERT in $AGENT_CERTS
        do
          openssl x509 -in $CERT -text -noout > $TMPDIR/${DISTRO}/certs/agent/$(basename $CERT) 2>&1
      done
      if [ -d /var/lib/rancher/${DISTRO}/server/tls ]; then
        techo "Collecting k3s server certificates"
        SERVER_CERTS=$(find /var/lib/rancher/${DISTRO}/server/tls -maxdepth 1 -type f -name "*.crt" | grep -v "\-ca.crt$")
        for CERT in $SERVER_CERTS
          do
            openssl x509 -in $CERT -text -noout > $TMPDIR/${DISTRO}/certs/server/$(basename $CERT) 2>&1
        done
      fi
  fi

}

kubeadm-certs() {

  if ! $(command -v openssl >/dev/null 2>&1); then
    techo "error: openssl command not found"
    exit 1
  fi

  if [ -d /etc/kubernetes/pki/ ]
    then
      techo "Collecting k8s kubeadm directory state"
      mkdir -p $TMPDIR/kubeadm/directories
      ls -lah /etc/kubernetes/ > $TMPDIR/kubeadm/directories/kubeadm 2>&1
      techo "Collecting k8s kubeadm certificates"
      mkdir -p $TMPDIR/kubeadm/pki/{server,kubelet}
      SERVER_CERTS=$(find /etc/kubernetes/pki/ -maxdepth 2 -type f -name "*.crt" | grep -v "\-ca.crt$")
      for CERT in $SERVER_CERTS
        do
          openssl x509 -in $CERT -text -noout > $TMPDIR/kubeadm/pki/server/$(basename $CERT) 2>&1
      done
      if [ -d /var/lib/kubelet/pki/ ]; then
        techo "Collecting kubelet certificates"
        AGENT_CERTS=$(find /var/lib/kubelet/pki/ -maxdepth 2 -type f -name "*.crt" | grep -v "\-ca.crt$")
        for CERT in $AGENT_CERTS
          do
            openssl x509 -in $CERT -text -noout > $TMPDIR/kubeadm/pki/kubelet/$(basename $CERT) 2>&1
        done
      fi
  fi

}

rke2-certs() {

  if [ -d ${RKE2_DATA_DIR} ]
    then
      techo "Collecting rke2 directory state"
      mkdir -p $TMPDIR/${DISTRO}/directories
      ls -lah ${RKE2_DATA_DIR}/agent > $TMPDIR/${DISTRO}/directories/rke2agent 2>&1
      ls -lahR ${RKE2_DATA_DIR}/server/manifests > $TMPDIR/${DISTRO}/directories/rke2servermanifests 2>&1
      ls -lahR ${RKE2_DATA_DIR}/server/tls > $TMPDIR/${DISTRO}/directories/rke2servertls 2>&1
      techo "Collecting rke2 certificates"
      mkdir -p $TMPDIR/${DISTRO}/certs/{agent,server}
      AGENT_CERTS=$(find ${RKE2_DATA_DIR}/agent -maxdepth 1 -type f -name "*.crt" | grep -v "\-ca.crt$")
      for CERT in $AGENT_CERTS
        do
          openssl x509 -in $CERT -text -noout > $TMPDIR/${DISTRO}/certs/agent/$(basename $CERT) 2>&1
      done
      if [ -d ${RKE2_DATA_DIR}/server/tls ]; then
        techo "Collecting rke2 server certificates"
        SERVER_CERTS=$(find ${RKE2_DATA_DIR}/server/tls -maxdepth 1 -type f -name "*.crt" | grep -v "\-ca.crt$")
        for CERT in $SERVER_CERTS
          do
            openssl x509 -in $CERT -text -noout > $TMPDIR/${DISTRO}/certs/server/$(basename $CERT) 2>&1
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
    docker exec etcd etcdctl member list > $TMPDIR/etcd/memberlist 2>&1
    ETCDCTL_ENDPOINTS=$(cut -d, -f5 $TMPDIR/etcd/memberlist | sed -e 's/ //g' | paste -sd ',')
    docker exec -e ETCDCTL_ENDPOINTS=$ETCDCTL_ENDPOINTS etcd etcdctl endpoint status --write-out table > $TMPDIR/etcd/endpointstatus 2>&1
    docker exec -e ETCDCTL_ENDPOINTS=$ETCDCTL_ENDPOINTS etcd etcdctl endpoint health > $TMPDIR/etcd/endpointhealth 2>&1
    docker exec -e ETCDCTL_ENDPOINTS=$ETCDCTL_ENDPOINTS etcd etcdctl alarm list > $TMPDIR/etcd/alarmlist 2>&1

    techo "Collecting rke etcd metrics"
    KEY=$(find /etc/kubernetes/ssl/ -name "kube-etcd-*-key.pem" | head -n1)
    CERT=$(echo $KEY | sed 's/-key//g')
    ETCD_ENDPOINTS=$(grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}:2379\b' $TMPDIR/etcd/memberlist | uniq)
    for ENDPOINT in ${ETCD_ENDPOINTS}
      do
        curl -sL --connect-timeout 5 --cacert /etc/kubernetes/ssl/kube-ca.pem --key $KEY --cert $CERT https://$ENDPOINT/metrics > $TMPDIR/etcd/etcd-metrics-$ENDPOINT.txt
    done
  fi

}

rke2-etcd() {

  RKE2_ETCD=$(${RKE2_DATA_DIR}/bin/crictl ps --quiet --label io.kubernetes.container.name=etcd --state running)
  if [ ! -z ${RKE2_ETCD} ]; then
    techo "Collecting rke2 etcd info"
    mkdir -p $TMPDIR/etcd
    ETCD_CERT=${RKE2_DATA_DIR}/server/tls/etcd/server-client.crt
    ETCD_KEY=${RKE2_DATA_DIR}/server/tls/etcd/server-client.key
    ETCD_CACERT=${RKE2_DATA_DIR}/server/tls/etcd/server-ca.crt
    ${RKE2_DATA_DIR}/bin/crictl exec ${RKE2_ETCD} etcdctl --cert ${ETCD_CERT} --key ${ETCD_KEY} --cacert ${ETCD_CACERT} member list > $TMPDIR/etcd/memberlist 2>&1
    ETCDCTL_ENDPOINTS=$(cut -d, -f5 $TMPDIR/etcd/memberlist | sed -e 's/ //g' | paste -sd ',')
    ${RKE2_DATA_DIR}/bin/crictl exec ${RKE2_ETCD} etcdctl --cert ${ETCD_CERT} --key ${ETCD_KEY} --cacert ${ETCD_CACERT} --endpoints=$ETCDCTL_ENDPOINTS --write-out table endpoint status > $TMPDIR/etcd/endpointstatus 2>&1
    ${RKE2_DATA_DIR}/bin/crictl exec ${RKE2_ETCD} etcdctl --cert ${ETCD_CERT} --key ${ETCD_KEY} --cacert ${ETCD_CACERT} --endpoints=$ETCDCTL_ENDPOINTS endpoint health > $TMPDIR/etcd/endpointhealth 2>&1
    ${RKE2_DATA_DIR}/bin/crictl exec ${RKE2_ETCD} etcdctl --cert ${ETCD_CERT} --key ${ETCD_KEY} --cacert ${ETCD_CACERT} --endpoints=$ETCDCTL_ENDPOINTS alarm list > $TMPDIR/etcd/alarmlist 2>&1

    techo "Collecting rke2 etcd metrics"
    ETCD_ENDPOINTS=$(grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}:2379\b' $TMPDIR/etcd/memberlist | uniq)
    for ENDPOINT in ${ETCD_ENDPOINTS}
      do
        curl -sL --connect-timeout 5 --cacert ${ETCD_CACERT} --key ${ETCD_KEY} --cert ${ETCD_CERT} https://$ENDPOINT/metrics > $TMPDIR/etcd/etcd-metrics-$ENDPOINT.txt
    done
  fi

  if [ -d "${RKE2_DATA_DIR}/server/db/etcd" ]; then
    find "${RKE2_DATA_DIR}/server/db/etcd" -type f -exec ls -la {} \; > $TMPDIR/etcd/findserverdbetcd 2>&1
  fi
  if [ -d "${RKE2_DATA_DIR}/server/db/snapshots" ]; then
    find "${RKE2_DATA_DIR}/server/db/snapshots" -type f -exec ls -la {} \; > $TMPDIR/etcd/findserverdbsnapshots 2>&1
  fi

}

k3s-etcd() {

  (echo > /dev/tcp/127.0.0.1/2379) &> /dev/null
  if [ $? -eq 0  ]; then
    techo "Collecting k3s etcd info"
    mkdir -p $TMPDIR/etcd
    K3S_DIR=/var/lib/rancher/k3s
    ETCD_CERT=${K3S_DIR}/server/tls/etcd/server-client.crt
    ETCD_KEY=${K3S_DIR}/server/tls/etcd/server-client.key
    ETCD_CACERT=${K3S_DIR}/server/tls/etcd/server-ca.crt
    curl -sL --cacert ${ETCD_CACERT} --key ${ETCD_KEY} --cert ${ETCD_CERT} https://localhost:2379/v3/cluster/member/list -X POST > $TMPDIR/etcd/memberlist.json 2>&1

    techo "Collecting k3s etcd metrics"
    ETCD_ENDPOINTS=$(grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}:2379\b' $TMPDIR/etcd/memberlist.json | uniq)
    for ENDPOINT in ${ETCD_ENDPOINTS}
      do
        curl -sL --connect-timeout 5 --cacert ${ETCD_CACERT} --key ${ETCD_KEY} --cert ${ETCD_CERT} https://$ENDPOINT/metrics > $TMPDIR/etcd/etcd-metrics-$ENDPOINT.txt
    done
  fi

}

kubeadm-etcd() {

  KUBEADM_ETCD_DIR="/var/lib/etcd/"
  KUBEADM_ETCD_CERTS="/etc/kubernetes/pki/etcd/"

  if ! $(command -v etcdctl >/dev/null 2>&1); then
    techo "error: etcdctl command not found"
    exit 1
  fi

  if [ -d $KUBEADM_ETCD_DIR ]; then
    techo "Collecting kubeadm etcd info"
    mkdir -p $TMPDIR/etcd
    ETCDCTL_ENDPOINTS=$(etcdctl --cert ${KUBEADM_ETCD_CERTS}/server.crt --key ${KUBEADM_ETCD_CERTS}/server.key --cacert ${KUBEADM_ETCD_CERTS}/ca.crt --write-out="simple" endpoint status | cut -d "," -f 1)
    etcdctl --endpoints=$ETCDCTL_ENDPOINTS --cert ${KUBEADM_ETCD_CERTS}/server.crt --key ${KUBEADM_ETCD_CERTS}/server.key --cacert ${KUBEADM_ETCD_CERTS}/ca.crt --write-out table endpoint status > $TMPDIR/etcd/endpointstatus 2>&1
    etcdctl --endpoints=$ETCDCTL_ENDPOINTS --cert ${KUBEADM_ETCD_CERTS}/server.crt --key ${KUBEADM_ETCD_CERTS}/server.key --cacert ${KUBEADM_ETCD_CERTS}/ca.crt endpoint health > $TMPDIR/etcd/endpointhealth 2>&1
    etcdctl --endpoints=$ETCDCTL_ENDPOINTS --cert ${KUBEADM_ETCD_CERTS}/server.crt --key ${KUBEADM_ETCD_CERTS}/server.key --cacert ${KUBEADM_ETCD_CERTS}/ca.crt alarm list > $TMPDIR/etcd/alarmlist 2>&1
  fi

  if [ -d ${KUBEADM_ETCD_DIR} ]; then
    find ${KUBEADM_ETCD_DIR} -type f -exec ls -la {} \; > $TMPDIR/etcd/findserverdbetcd 2>&1
  fi

}

timeout_cmd() {

  TIMEOUT_EXCEEDED_MSG="$1 command timed out, killing process to prevent hanging."
  WPID=$!
  sleep $TIMEOUT && if kill -0 $WPID > /dev/null 2>&1
    then
      techo "$1 command timed out, killing process to prevent hanging."; kill $WPID &> /dev/null;
  fi & KPID=$!; wait $WPID

}

archive() {

  DIR_NAME=$(dirname ${TMPDIR_BASE})
  tar --create --gzip --file ${DIR_NAME}/${LOGNAME}.tar.gz --directory ${TMPDIR_BASE}/ .
  if [ $? -eq -0 ]
    then
      techo "Created ${DIR_NAME}/${LOGNAME}.tar.gz"
    else
      techo "Creating the tar archive did not complete successfully"
  fi

}

obfuscate() {

  which python3 > /dev/null 2>&1
  if [ $? -eq 0 ]
    then
      python3 -c "import petname" > /dev/null 2>&1
      if [ $? -eq 0 ]
        then
          techo "Obfuscating ${TMPDIR_BASE}"
          run-obf-python
        else
          techo "Could not import petname python module, please install this first, skipping obfuscation..."
      fi
    else
      techo "Could not find python3, skipping obfuscation..."
  fi
}

run-obf-python() {

python3 - "${TMPDIR_BASE}" << EOF
import json
import petname
import os
import re
import socket
import sys
#TODO implement logging

def load_mapping(mapping_file):
    if os.path.exists(mapping_file):
        with open(mapping_file, 'r') as file:
            return json.load(file)
    return {}

def save_mapping(mapping, mapping_file):
    with open(mapping_file, 'w') as file:
        json.dump(mapping, file, indent=2)

def extract_hostnames(text):
    # Regular expression to match fqdn hostnames
    hostname_regex = re.compile(r'\b(?:[a-zA-Z0-9-]+\.)+[a-zA-Z]{2,}\b')
    return set(hostname_regex.findall(text))

def extract_ip_addresses(text):
    # Regular expression to match IP addresses
    ip_regex = re.compile(r'\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b')
    return set(ip_regex.findall(text))

def obfuscate_subdomain(subdomain, mapping):
    if subdomain not in mapping:
        #print('subdomain passed in: ' + subdomain)
        # TODO check for collisions
        return petname.Generate(1)
    else:
        #print('subdomain found: ' + str(subdomain))
        return mapping[subdomain]

def obfuscate_hostname(hostname, mapping):
    subdomains = hostname.split('.')
    #print('subdomains: ' + str(subdomains))
    obfuscated_subdomains = [obfuscate_subdomain(sub, mapping) for sub in subdomains]
    obfuscated_hostname = '.'.join(obfuscated_subdomains)
    mapping[hostname] = obfuscated_hostname
    return obfuscated_hostname

def obfuscate_host(hostname, mapping):
    obfuscated_hostname = obfuscate_subdomain(hostname, mapping)
    #print('debug obf hostname:' + obfuscated_hostname)
    mapping[hostname] = obfuscated_hostname
    return obfuscated_hostname

def obfuscate_ip_address(ip_address, ip_mapping):
    octets = ip_address.split('.')
    if ip_address not in ip_mapping:
        obfuscated_octets = [octets[0]] + [petname.Generate(1) for _ in octets[1:]]
        ip_mapping[ip_address] = '.'.join(obfuscated_octets)
    return ip_mapping[ip_address]

def obfuscate_text(text, hostname_mapping, ip_mapping):
    hostnames = extract_hostnames(text)
    ip_addresses = extract_ip_addresses(text)
    short_hostname = socket.gethostname()

    for hostname in hostnames:
        #print("processing hostname:" + hostname)
        if hostname not in hostname_mapping:
            #print('hostname not in map. hostname: ' + hostname)
            obfuscated_name = obfuscate_hostname(hostname, hostname_mapping)
            #print('new obfuscated name: ' + obfuscated_name)
        else:
            obfuscated_name = hostname_mapping[hostname]
            #print("found obfuscated name:" + obfuscated_name)
        text = text.replace(hostname, obfuscated_name)

    for ip_address in ip_addresses:
        if ip_address not in ip_mapping:
            obfuscated_ip = obfuscate_ip_address(ip_address, ip_mapping)
        else:
            obfuscated_ip = ip_mapping[ip_address]
        text = text.replace(ip_address, obfuscated_ip)

    #search for hostname not fqdn
    if short_hostname not in hostname_mapping:
        #print("short_hostname not found. short hostname:" + short_hostname)
        obfuscated_name = obfuscate_host(short_hostname, hostname_mapping)
    else:
        #print("short hostname found")
        obfuscated_name = hostname_mapping[short_hostname]
    text = text.replace(short_hostname, obfuscated_name)

    return text

def process_file(input_file, output_file, hostname_mapping_file='hostname_mapping.json', ip_mapping_file='ip_mapping.json'):
    hostname_mapping = load_mapping(hostname_mapping_file)
    ip_mapping = load_mapping(ip_mapping_file)
    short_hostname = socket.gethostname()

    try:
        with open(input_file, 'r') as file:
            text = file.read()

        obfuscated_text = obfuscate_text(text, hostname_mapping, ip_mapping)

        with open(output_file, 'w') as file:
            file.write(obfuscated_text)

        save_mapping(hostname_mapping, hostname_mapping_file)
        save_mapping(ip_mapping, ip_mapping_file)
    except UnicodeDecodeError:
        pass

if __name__ == "__main__":
  directory = sys.argv[1]

  input_file = []
  output_file = []

  map_file = "ip_map.json"
  # iterate over files in directories
  for root, dirs, files in os.walk(directory):
    for filename in files:
      input_file = os.path.join(root, filename)
      tmp_output_file = 'obf_' + filename
      output_file = os.path.join(root, tmp_output_file)
      # if filename in process_list:
      print("processing file: " + str(filename))
      process_file(input_file, output_file)
      if os.path.isfile(output_file):
        os.remove(input_file)
        os.rename(output_file, input_file)

EOF

}

cleanup() {

  techo "Removing ${TMPDIR_BASE}"
  rm -r -f "${TMPDIR_BASE}" > /dev/null 2>&1

}

help() {

  echo "Rancher 2.x logs-collector
  Usage: rancher2_logs_collector.sh [ -d <directory> -s <days> -r <k8s distribution> -p -f ]

  All flags are optional

  -c    Custom data-dir for RKE2 (ex: -c /opt/rke2)
  -d    Output directory for temporary storage and .tar.gz archive (ex: -d /var/tmp)
  -s    Start day of journald and docker log collection. Specify the number of days before the current time (ex: -s 7)
  -e    End day of journald and docker log collection. Specify the number of days before the current time (ex: -e 5)
  -S    Start date of journald and docker log collection. (ex: -S 2022-12-05)
  -E    End date of journald and docker log collection. (ex: -E 2022-12-07)
  -r    Override k8s distribution if not automatically detected (rke|k3s|rke2|kubeadm)
  -p    When supplied runs with the default nice/ionice priorities, otherwise use the lowest priorities
  -f    Force log collection if the minimum space isn't available
  -o    Obfuscate IP addresses"

}

timestamp() {

  date "+%Y-%m-%d %H:%M:%S"

}

techo() {

  echo "$(timestamp): $*" | tee -a $TMPDIR/collector-output.log

}

# Check if we're running as root.
if [[ $EUID -ne 0 ]] && [[ "${DEV}" == "" ]]
  then
    help
    techo "This script must be run as root"
    exit 1
fi

while getopts "c:d:s:e:S:E:r:fpoh" opt; do
  case $opt in
    c)
      FLAG_DATA_DIR="${OPTARG}"
      ;;
    d)
      MKTEMP_BASEDIR="-p ${OPTARG}"
      ;;
    s)
      START_DAY=${OPTARG}
      START=$(date -d "-${OPTARG} days" '+%Y-%m-%d')
      SINCE_FLAG="--since ${START}"
      techo "Logging since $START"
      ;;
    e)
      END_DAY=${OPTARG}
      END_LOGGING=$(date -d "-${OPTARG} days" '+%Y-%m-%d')
      UNTIL_FLAG="--until ${END_LOGGING}"
      techo "Logging until $END_LOGGING"
      ;;
    S)
      SINCE_FLAG="--since ${OPTARG}"
      techo "Collecting logs starting ${OPTARG}"
      ;;
    E)
      UNTIL_FLAG="--until ${OPTARG}"
      techo "Collecting logs until ${OPTARG}"
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
    o)
      OBFUSCATE=true
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

if [ -n "${START_DAY}" ] && [ -n "${END_DAY}" ] && [ ${END_DAY} -ge ${START_DAY} ]
  then
    techo "Start day should be greater than end day"
    exit 1
fi

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
provisioning-crds
if [[ "${OSRELEASE}" = "rhel" || "${OSRELEASE}" = "centos" ]]
  then
    system-rhel
elif [ "${OSRELEASE}" = "ubuntu" ]
  then
    system-ubuntu
fi
if [ "${OSRELEASE}" = "sles" ]
  then
    system-sles
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
    k3s-etcd
elif [ "${DISTRO}" = "rke2" ]
  then
    rke2-logs
    rke2-k8s
    rke2-certs
    rke2-etcd
elif [ "${DISTRO}" = "kubeadm" ]
  then
    kubeadm-k8s
    kubeadm-certs
    kubeadm-etcd
fi
var-log
if [ "${INIT}" = "systemd" ]
  then
    journald-log
fi
if [ $OBFUSCATE ]
  then
    obfuscate
fi
archive
cleanup
echo "$(timestamp): Finished"
