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
          techo "Using RKE2 binary... ${RKE2_BIN}"
          techo "Using RKE2 data-dir... ${RKE2_DATA_DIR}"
      fi
    else
      echo -n "$(timestamp): Detecting k8s distribution... " | tee -a $TMPDIR/collector-output.log
      if $(command -v rke2 >/dev/null 2>&1)
        then
          rke2-setup
          if $(${RKE2_BIN} >/dev/null 2>&1)
            then
              DISTRO=rke2
              echo "rke2" | tee -a $TMPDIR/collector-output.log
            else
              FOUND+="rke2 "
          fi
          techo "Using RKE2 binary... ${RKE2_BIN}"
          techo "Using RKE2 data-dir... ${RKE2_DATA_DIR}"
      elif $(command -v k3s >/dev/null 2>&1)
        then
          if $(k3s >/dev/null 2>&1)
            then
              DISTRO=k3s
              echo "k3s" | tee -a $TMPDIR/collector-output.log
            else
              FOUND+="k3s "
          fi
      elif $(command -v docker >/dev/null 2>&1)
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
          echo -e "\n$(timestamp): Couldn't detect k8s distro" | tee -a $TMPDIR/collector-output.log
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
    for file in $(ls -p -R /etc/cni/net.d | grep -v /); do
      if grep -q "kubeconfig" <<< "$file"; then
        techo "skipping $file"
      else
        cp "/etc/cni/net.d/"$file $TMPDIR/networking/cni 2>&1
      fi
    done
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

  if ! k3s crictl ps > /dev/null 2>&1; then
      techo "[!] Containerd is offline, skipping crictl collection"
    else
      k3s crictl ps -a > $TMPDIR/${DISTRO}/crictl/psa 2>&1
      k3s crictl pods > $TMPDIR/${DISTRO}/crictl/pods 2>&1
      k3s crictl info > $TMPDIR/${DISTRO}/crictl/info 2>&1
      k3s crictl stats -a > $TMPDIR/${DISTRO}/crictl/statsa 2>&1
      k3s crictl version > $TMPDIR/${DISTRO}/crictl/version 2>&1
      k3s crictl images > $TMPDIR/${DISTRO}/crictl/images 2>&1
      k3s crictl imagefsinfo > $TMPDIR/${DISTRO}/crictl/imagefsinfo 2>&1
      k3s crictl stats -a > $TMPDIR/${DISTRO}/crictl/statsa 2>&1
  fi
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

  if ! ${RKE2_DATA_DIR}/bin/crictl ps > /dev/null 2>&1; then
      techo "[!] Containerd is offline, skipping crictl collection"
      export CONTAINERD_OFFLINE=true
    else
      ${RKE2_DATA_DIR}/bin/crictl ps -a > $TMPDIR/${DISTRO}/crictl/psa 2>&1
      ${RKE2_DATA_DIR}/bin/crictl pods > $TMPDIR/${DISTRO}/crictl/pods 2>&1
      ${RKE2_DATA_DIR}/bin/crictl info > $TMPDIR/${DISTRO}/crictl/info 2>&1
      ${RKE2_DATA_DIR}/bin/crictl stats -a > $TMPDIR/${DISTRO}/crictl/statsa 2>&1
      ${RKE2_DATA_DIR}/bin/crictl version > $TMPDIR/${DISTRO}/crictl/version 2>&1
      ${RKE2_DATA_DIR}/bin/crictl images > $TMPDIR/${DISTRO}/crictl/images 2>&1
      ${RKE2_DATA_DIR}/bin/crictl imagefsinfo > $TMPDIR/${DISTRO}/crictl/imagefsinfo 2>&1
      ${RKE2_DATA_DIR}/bin/crictl stats -a > $TMPDIR/${DISTRO}/crictl/statsa 2>&1
  fi
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

  if [ -d /var/lib/rancher/${DISTRO}/agent ]; then
    K3S_AGENT=true
    KUBECONFIG=/var/lib/rancher/${DISTRO}/agent/kubelet.kubeconfig
    k3s kubectl --kubeconfig=$KUBECONFIG get --raw='/healthz' --request-timeout=5s > /dev/null 2>&1
    if [ $? -ne 0 ]
      then
        API_SERVER_OFFLINE=true
        techo "[!] Kube-apiserver is offline, collecting local pod logs only"
    fi
  fi
  if [ -d /var/lib/rancher/${DISTRO}/server ]; then
    K3S_SERVER=true
    k3s kubectl get --raw='/healthz' --request-timeout=5s > /dev/null 2>&1
    if [ $? -ne 0 ]
      then
        API_SERVER_OFFLINE=true
        techo "[!] Kube-apiserver is offline, collecting local pod logs only"
    fi
  fi

  if [[ ${K3S_AGENT} && ! ${API_SERVER_OFFLINE} ]]; then
    techo "Collecting k3s cluster logs"
    mkdir -p $TMPDIR/${DISTRO}/kubectl
    KUBECONFIG=/var/lib/rancher/${DISTRO}/agent/kubelet.kubeconfig
    k3s kubectl --kubeconfig=$KUBECONFIG get nodes -o wide > $TMPDIR/${DISTRO}/kubectl/nodes 2>&1
    k3s kubectl --kubeconfig=$KUBECONFIG describe nodes > $TMPDIR/${DISTRO}/kubectl/nodesdescribe 2>&1
    k3s kubectl --kubeconfig=$KUBECONFIG version > $TMPDIR/${DISTRO}/kubectl/version 2>&1
    k3s kubectl --kubeconfig=$KUBECONFIG get pods -o wide --all-namespaces > $TMPDIR/${DISTRO}/kubectl/pods 2>&1
    k3s kubectl --kubeconfig=$KUBECONFIG get svc -o wide --all-namespaces > $TMPDIR/${DISTRO}/kubectl/services 2>&1
  fi

  if [[ ${K3S_SERVER} && ! ${API_SERVER_OFFLINE} ]]; then
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

  if [[ ${K3S_SERVER} && ! ${API_SERVER_OFFLINE} ]]; then
    techo "Collecting system pod logs"
    mkdir -p $TMPDIR/${DISTRO}/podlogs
    for SYSTEM_NAMESPACE in "${SYSTEM_NAMESPACES[@]}"; do
      for SYSTEM_POD in $(k3s kubectl -n $SYSTEM_NAMESPACE get pods --no-headers -o custom-columns=NAME:.metadata.name); do
        k3s kubectl -n $SYSTEM_NAMESPACE logs --all-containers $SYSTEM_POD > $TMPDIR/${DISTRO}/podlogs/$SYSTEM_NAMESPACE-$SYSTEM_POD 2>&1
        k3s kubectl -n $SYSTEM_NAMESPACE logs -p --all-containers $SYSTEM_POD > $TMPDIR/${DISTRO}/podlogs/$SYSTEM_NAMESPACE-$SYSTEM_POD-previous 2>&1
      done
    done
  elif [[ ${K3S_AGENT} || ${API_SERVER_OFFLINE} ]]; then
    mkdir -p $TMPDIR/${DISTRO}/podlogs
    for SYSTEM_NAMESPACE in "${SYSTEM_NAMESPACES[@]}"; do
      if ls -d /var/log/pods/$SYSTEM_NAMESPACE* > /dev/null 2>&1; then
        cp -r -p /var/log/pods/$SYSTEM_NAMESPACE* $TMPDIR/${DISTRO}/podlogs/
      fi
    done
  fi

}

rke2-k8s() {

  if [ -f ${RKE2_DATA_DIR}/agent/kubelet.kubeconfig ]; then
    RKE2_AGENT=true
    KUBECONFIG=${RKE2_DATA_DIR}/agent/kubelet.kubeconfig
    ${RKE2_DATA_DIR}/bin/kubectl --kubeconfig=$KUBECONFIG get --raw='/healthz' --request-timeout=5s > /dev/null 2>&1
    if [ $? -ne 0 ]
      then
        API_SERVER_OFFLINE=true
        techo "[!] Kube-apiserver is offline, collecting local pod logs only"
    fi
  fi
  if [ -f /etc/rancher/${DISTRO}/rke2.yaml ]; then
    RKE2_SERVER=true
    KUBECONFIG=/etc/rancher/${DISTRO}/rke2.yaml
    ${RKE2_DATA_DIR}/bin/kubectl --kubeconfig=$KUBECONFIG get --raw='/healthz' --request-timeout=5s > /dev/null 2>&1
    if [[ $? -ne 0 && ! ${API_SERVER_OFFLINE} ]]
      then
        API_SERVER_OFFLINE=true
        techo "[!] Kube-apiserver is offline, collecting local pod logs only"
    fi
  fi

  if [[ ${RKE2_AGENT} && ! ${API_SERVER_OFFLINE} ]]; then
    techo "Collecting rke2 cluster logs"
    mkdir -p $TMPDIR/${DISTRO}/kubectl
    KUBECONFIG=${RKE2_DATA_DIR}/agent/kubelet.kubeconfig
    ${RKE2_DATA_DIR}/bin/kubectl --kubeconfig=$KUBECONFIG get nodes -o wide > $TMPDIR/${DISTRO}/kubectl/nodes 2>&1
    ${RKE2_DATA_DIR}/bin/kubectl --kubeconfig=$KUBECONFIG describe nodes > $TMPDIR/${DISTRO}/kubectl/nodesdescribe 2>&1
    ${RKE2_DATA_DIR}/bin/kubectl --kubeconfig=$KUBECONFIG version > $TMPDIR/${DISTRO}/kubectl/version 2>&1
    ${RKE2_DATA_DIR}/bin/kubectl --kubeconfig=$KUBECONFIG get pods -o wide --all-namespaces > $TMPDIR/${DISTRO}/kubectl/pods 2>&1
    ${RKE2_DATA_DIR}/bin/kubectl --kubeconfig=$KUBECONFIG get svc -o wide --all-namespaces > $TMPDIR/${DISTRO}/kubectl/services 2>&1
  fi

  if [[ ${RKE2_SERVER} && ! ${API_SERVER_OFFLINE} ]]; then
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

  if [[ ${RKE2_SERVER} && ! ${API_SERVER_OFFLINE} ]]; then
    techo "Collecting rke2 system pod logs"
    mkdir -p $TMPDIR/${DISTRO}/podlogs
    KUBECONFIG=/etc/rancher/${DISTRO}/rke2.yaml
    for SYSTEM_NAMESPACE in "${SYSTEM_NAMESPACES[@]}"; do
      for SYSTEM_POD in $(${RKE2_DATA_DIR}/bin/kubectl --kubeconfig=$KUBECONFIG -n $SYSTEM_NAMESPACE get pods --no-headers -o custom-columns=NAME:.metadata.name); do
        ${RKE2_DATA_DIR}/bin/kubectl --kubeconfig=$KUBECONFIG -n $SYSTEM_NAMESPACE logs --all-containers $SYSTEM_POD > $TMPDIR/${DISTRO}/podlogs/$SYSTEM_NAMESPACE-$SYSTEM_POD 2>&1
        ${RKE2_DATA_DIR}/bin/kubectl --kubeconfig=$KUBECONFIG -n $SYSTEM_NAMESPACE logs -p --all-containers $SYSTEM_POD > $TMPDIR/${DISTRO}/podlogs/$SYSTEM_NAMESPACE-$SYSTEM_POD-previous 2>&1
      done
    done
  elif [[ ${RKE2_AGENT} || ${API_SERVER_OFFLINE} ]]; then
    mkdir -p $TMPDIR/${DISTRO}/podlogs
    for SYSTEM_NAMESPACE in "${SYSTEM_NAMESPACES[@]}"; do
      if ls -d /var/log/pods/$SYSTEM_NAMESPACE* > /dev/null 2>&1; then
        cp -r -p /var/log/pods/$SYSTEM_NAMESPACE* $TMPDIR/${DISTRO}/podlogs/
      fi
    done
  fi

  if $(ls -A1q ${RKE2_DATA_DIR}/agent/pod-manifests | grep -q .); then
      techo "Collecting rke2 static pod manifests"
      mkdir -p $TMPDIR/${DISTRO}/pod-manifests
      cp -p ${RKE2_DATA_DIR}/agent/pod-manifests/* $TMPDIR/${DISTRO}/pod-manifests
    else
      techo "[!] Static pod manifest directory is empty, skipping"
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
    techo "Collecting etcdctl info"
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

  if [ ! ${CONTAINERD_OFFLINE} ]
    then
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
        ETCD_ENDPOINTS=$(grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}:2381\b' /var/lib/rancher/rke2/server/db/etcd/config | uniq)
        for ENDPOINT in ${ETCD_ENDPOINTS}
          do
            curl -s --connect-timeout 5 http://$ENDPOINT/metrics > $TMPDIR/etcd/etcd-metrics-$ENDPOINT.txt
        done
      fi
    else
      techo "[!] Containerd is offline, skipping etcd collection"
  fi

  if [ -d "${RKE2_DATA_DIR}/server/db/etcd" ]; then
    mkdir -p $TMPDIR/etcd
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
      techo "Obfuscating ${TMPDIR_BASE}"
      run-obf-python
  else
    techo "Could not find python3, skipping obfuscation..."
  fi
}

run-obf-python() {

python3 - "${TMPDIR_BASE}" << EOF
#!/usr/bin/env python3
import json
import os
import re
import socket
import sys
import random

#TODO implement logging
adjectives = ['abandoned', 'abdominal', 'abhorrent', 'abiding', 'abject', 'able', 'able-bodied', 'abnormal', 'abounding', 'abrasive', 'abrupt', 'absent', 'absentminded', 'absolute', 'absorbed', 'absorbing', 'abstracted', 'absurd', 'abundant', 'abysmal', 'academic', 'acceptable', 'accepting', 'accessible', 'accidental', 'acclaimed', 'accommodating', 'accompanying', 'accountable', 'accurate', 'accusative', 'accused', 'accusing', 'acerbic', 'achievable', 'aching', 'acid', 'acidic', 'acknowledged', 'acoustic', 'acrid', 'acrimonious', 'acrobatic', 'actionable', 'active', 'actual', 'adhoc', 'adamant', 'adaptable', 'adaptive', 'addicted', 'addictive', 'additional', 'adept', 'adequate', 'adhesive', 'adjacent', 'adjoining', 'adjustable', 'administrative', 'admirable', 'admired', 'admiring', 'adopted', 'adoptive', 'adorable', 'adored', 'adoring', 'adrenalized', 'adroit', 'advanced', 'advantageous', 'adventurous', 'adversarial', 'advisable', 'aerial', 'affable', 'affected', 'affectionate', 'affirmative', 'affordable', 'afraid', 'afternoon', 'ageless', 'aggravated', 'aggravating', 'aggressive', 'agitated', 'agonizing', 'agrarian', 'agreeable', 'aimless', 'airline', 'airsick', 'ajar', 'alarmed', 'alarming', 'alert', 'algebraic', 'alien', 'alienated', 'alike', 'alive', 'all', 'all-around', 'alleged', 'allowable', 'all-purpose', 'all-too-common', 'alluring', 'allusive', 'alone', 'aloof', 'alterable', 'alternating', 'alternative', 'amazed', 'amazing', 'ambiguous', 'ambitious', 'ambulant', 'ambulatory', 'amiable', 'amicable', 'amphibian', 'amused', 'amusing', 'an', 'ancient', 'anecdotal', 'anemic', 'angelic', 'angered', 'angry', 'angular', 'animal', 'animated', 'annoyed', 'annoying', 'annual', 'anonymous', 'another', 'antagonistic', 'anticipated', 'anticlimactic', 'anticorrosive', 'antiquated', 'antiseptic', 'antisocial', 'antsy', 'anxious', 'any', 'apathetic', 'apologetic', 'apologizing', 'appalling', 'appealing', 'appetizing', 'applauding', 'applicable', 'applicative', 'appreciative', 'apprehensive', 'approachable', 'approaching', 'appropriate', 'approving', 'approximate', 'aquatic', 'architectural', 'ardent', 'arduous', 'arguable', 'argumentative', 'arid', 'aristocratic', 'aromatic', 'arresting', 'arrogant', 'artful', 'artificial', 'artistic', 'artless', 'ashamed', 'aspiring', 'assertive', 'assignable', 'assorted', 'assumable', 'assured', 'assuring', 'astonished', 'astonishing', 'astounded', 'astounding', 'astringent', 'astronomical', 'astute', 'asymmetrical', 'athletic', 'atomic', 'atrocious', 'attachable', 'attainable', 'attentive', 'attractive', 'attributable', 'atypical', 'audacious', 'auspicious', 'authentic', 'authoritarian', 'authoritative', 'autobiographic', 'autographed', 'automatic', 'autonomous', 'available', 'avant-garde', 'avenging', 'average', 'avian', 'avid', 'avoidable', 'awake', 'awakening', 'aware', 'away', 'awesome', 'awful', 'awkward', 'axiomatic', 'babbling', 'baby', 'background', 'backhanded', 'bacterial', 'bad', 'bad-tempered', 'baffled', 'baffling', 'bald', 'balding', 'balmy', 'bandaged', 'banging', 'bankable', 'banned', 'bantering', 'barbaric', 'barbarous', 'barbequed', 'barefooted', 'barking', 'barren', 'bashful', 'basic', 'battered', 'batty', 'bawling', 'beady', 'beaming', 'bearable', 'beautiful', 'beckoning', 'bedazzled', 'bedazzling', 'beefy', 'beeping', 'befitting', 'befuddled', 'beginning', 'belching', 'believable', 'bellicose', 'belligerent', 'bellowing', 'bendable', 'beneficial', 'benevolent', 'benign', 'bent', 'berserk', 'best', 'betrayed', 'better', 'better off', 'better-late-than-never', 'bewildered', 'bewildering', 'bewitched', 'bewitching', 'biased', 'biblical', 'big', 'big-city', 'bigger', 'biggest', 'big-headed', 'bighearted', 'bigoted', 'bilingual', 'billable', 'billowy', 'binary', 'binding', 'bioactive', 'biodegradable', 'biographical', 'bite-sized', 'biting', 'bitter', 'bizarre', 'black', 'black-and-blue', 'blamable', 'blameless', 'bland', 'blank', 'blaring', 'blasphemous', 'blatant', 'blazing', 'bleached', 'bleak', 'bleary', 'bleary-eyed', 'blessed', 'blind', 'blindfolded', 'blinding', 'blissful', 'blistering', 'bloated', 'blonde', 'bloodied', 'blood-red', 'bloodthirsty', 'bloody', 'blooming', 'blossoming', 'blue', 'blundering', 'blunt', 'blurred', 'blurry', 'blushing', 'boastful', 'bodacious', 'bohemian', 'boiling', 'boisterous', 'bold', 'bookish', 'booming', 'boorish', 'bordering', 'bored', 'boring', 'born', 'bossy', 'both', 'bothered', 'bouncing', 'bouncy', 'boundless', 'bountiful', 'boyish', 'braided', 'brainless', 'brainy', 'brash', 'brassy', 'brave', 'brawny', 'brazen', 'breakable', 'breathable', 'breathless', 'breathtaking', 'breezy', 'bribable', 'brick', 'brief', 'bright', 'bright-eyed', 'bright-red', 'brilliant', 'briny', 'brisk', 'bristly', 'broad', 'broken', 'broken-hearted', 'bronchial', 'bronze', 'bronzed', 'brooding', 'brown', 'bruised', 'brunette', 'brutal', 'brutish', 'bubbly', 'budget', 'built-in', 'bulky', 'bumpy', 'bungling', 'buoyant', 'bureaucratic', 'burly', 'burnable', 'burning', 'bushy', 'busiest', 'business', 'bustling', 'busy', 'buzzing', 'cackling', 'caged', 'cagey', 'calculable', 'calculated', 'calculating', 'callous', 'calm', 'calming', 'camouflaged', 'cancelled', 'cancerous', 'candid', 'cantankerous', 'capable', 'capricious', 'captivated', 'captivating', 'captive', 'carefree', 'careful', 'careless', 'caring', 'carnivorous', 'carpeted', 'carsick', 'casual', 'catastrophic', 'catatonic', 'catchable', 'caustic', 'cautious', 'cavalier', 'cavernous', 'ceaseless', 'celebrated', 'celestial', 'centered', 'central', 'cerebral', 'ceremonial', 'certain', 'certifiable', 'certified', 'challenged', 'challenging', 'chance', 'changeable', 'changing', 'chanting', 'charging', 'charismatic', 'charitable', 'charmed', 'charming', 'chattering', 'chatting', 'chatty', 'cheap', 'cheapest', 'cheeky', 'cheerful', 'cheering', 'cheerless', 'cheery', 'chemical', 'chewable', 'chewy', 'chic', 'chicken', 'chief', 'childish', 'childlike', 'chilling', 'chilly', 'chivalrous', 'choice', 'choking', 'choppy', 'chronological', 'chubby', 'chuckling', 'chunky', 'cinematic', 'circling', 'circular', 'circumstantial', 'civil', 'civilian', 'civilized', 'clammy', 'clamoring', 'clandestine', 'clanging', 'clapping', 'clashing', 'classic', 'classical', 'classifiable', 'classified', 'classy', 'clean', 'cleanable', 'clear', 'cleared', 'clearheaded', 'clever', 'climatic', 'climbable', 'clinging', 'clingy', 'clinical', 'cliquish', 'clogged', 'cloistered', 'close', 'closeable', 'closed', 'close-minded', 'cloudless', 'cloudy', 'clownish', 'clueless', 'clumsy', 'cluttered', 'coachable', 'coarse', 'cockamamie', 'cocky', 'codified', 'coercive', 'cognitive', 'coherent', 'cohesive', 'coincidental', 'cold', 'coldhearted', 'collaborative', 'collapsed', 'collapsing', 'collectable', 'collegial', 'colloquial', 'colonial', 'colorful', 'colorless', 'colossal', 'combative', 'combined', 'comfortable', 'comforted', 'comforting', 'comical', 'commanding', 'commemorative', 'commendable', 'commercial', 'committed', 'common', 'communal', 'communicable', 'communicative', 'communist', 'compact', 'comparable', 'comparative', 'compassionate', 'compelling', 'competent', 'competitive', 'complacent', 'complaining', 'complete', 'completed', 'complex', 'compliant', 'complicated', 'complimentary', 'compound', 'comprehensive', 'compulsive', 'compulsory', 'computer', 'computerized', 'concealable', 'concealed', 'conceited', 'conceivable', 'concerned', 'concerning', 'concerted', 'concise', 'concurrent', 'condemned', 'condensed', 'condescending', 'conditional', 'confident', 'confidential', 'confirmable', 'confirmed', 'conflicted', 'conflicting', 'conformable', 'confounded', 'confused', 'confusing', 'congenial', 'congested', 'congressional', 'congruent', 'congruous', 'connectable', 'connected', 'connecting', 'connective', 'conscientious', 'conscious', 'consecutive', 'consensual', 'consenting', 'conservative', 'considerable', 'considerate', 'consistent', 'consoling', 'conspicuous', 'conspiratorial', 'constant', 'constitutional', 'constrictive', 'constructive', 'consumable', 'consummate', 'contagious', 'containable', 'contemplative', 'contemporary', 'contemptible', 'contemptuous', 'content', 'contented', 'contentious', 'contextual', 'continual', 'continuing', 'continuous', 'contoured', 'contractual', 'contradicting', 'contradictory', 'contrarian', 'contrary', 'contributive', 'contrite', 'controllable', 'controlling', 'controversial', 'convenient', 'conventional', 'conversational', 'convinced', 'convincing', 'convoluted', 'convulsive', 'cooing', 'cooked', 'cool', 'coolest', 'cooperative', 'coordinated', 'copious', 'coquettish', 'cordial', 'corner', 'cornered', 'corny', 'corporate', 'corpulent', 'correct', 'correctable', 'corrective', 'corresponding', 'corrosive', 'corrupt', 'corrupting', 'corruptive', 'cosmetic', 'cosmic', 'costly', 'cottony', 'coughing', 'courageous', 'courteous', 'covert', 'coveted', 'cowardly', 'cowering', 'coy', 'cozy', 'crabby', 'cracked', 'crackling', 'crafty', 'craggy', 'crammed', 'cramped', 'cranky', 'crashing', 'crass', 'craven', 'crawling', 'crazy', 'creaking', 'creaky', 'creative', 'credible', 'creeping', 'creepy', 'crestfallen', 'criminal', 'crisp', 'crispy', 'critical', 'crooked', 'cropped', 'cross', 'crossed', 'crotchety', 'crowded', 'crucial', 'crude', 'cruel', 'crumbling', 'crumbly', 'crumply', 'crunchable', 'crunching', 'crunchy', 'crushable', 'crushed', 'crusty', 'crying', 'cryptic', 'crystalline', 'crystallized', 'cuddly', 'culpable', 'cultural', 'cultured', 'cumbersome', 'cumulative', 'cunning', 'curable', 'curative', 'curious', 'curly', 'current', 'cursed', 'curt', 'curved', 'curvy', 'customary', 'cut', 'cute', 'cutting', 'cylindrical', 'cynical', 'daffy', 'daft', 'daily', 'dainty', 'damaged', 'damaging', 'damp', 'danceable', 'dandy', 'dangerous', 'dapper', 'daring', 'dark', 'darkened', 'dashing', 'daughterly', 'daunting', 'dawdling', 'day', 'dazed', 'dazzling', 'dead', 'deadly', 'deadpan', 'deafening', 'dear', 'debatable', 'debonair', 'decadent', 'decayed', 'decaying', 'deceitful', 'deceivable', 'deceiving', 'decent', 'decentralized', 'deceptive', 'decimated', 'decipherable', 'decisive', 'declining', 'decorative', 'decorous', 'decreasing', 'decrepit', 'dedicated', 'deep', 'deepening', 'defeated', 'defective', 'defendable', 'defenseless', 'defensible', 'defensive', 'defiant', 'deficient', 'definable', 'definitive', 'deformed', 'dehydrated', 'dejected', 'delectable', 'deliberate', 'deliberative', 'delicate', 'delicious', 'delighted', 'delightful', 'delinquent', 'delirious', 'deliverable', 'deluded', 'demanding', 'demented', 'democratic', 'demonic', 'demonstrative', 'demure', 'deniable', 'dense', 'dependable', 'dependent', 'deplorable', 'deploring', 'depraved', 'depressed', 'depressing', 'depressive', 'deprived', 'deranged', 'derivative', 'derogative', 'derogatory', 'descriptive', 'deserted', 'designer', 'desirable', 'desirous', 'desolate', 'despairing', 'desperate', 'despicable', 'despised', 'despondent', 'destroyed', 'destructive', 'detachable', 'detached', 'detailed', 'detectable', 'determined', 'detestable', 'detrimental', 'devastated', 'devastating', 'devious', 'devoted', 'devout', 'dexterous', 'diabolical', 'diagonal', 'didactic', 'different', 'difficult', 'diffuse', 'digestive', 'digital', 'dignified', 'digressive', 'dilapidated', 'diligent', 'dim', 'diminishing', 'diminutive', 'dingy', 'diplomatic', 'dire', 'direct', 'direful', 'dirty', 'disabled', 'disadvantaged', 'disadvantageous', 'disaffected', 'disagreeable', 'disappearing', 'disappointed', 'disappointing', 'disapproving', 'disarming', 'disastrous', 'discarded', 'discernable', 'disciplined', 'disconnected', 'discontented', 'discordant', 'discouraged', 'discouraging', 'discourteous', 'discredited', 'discreet', 'discriminating', 'discriminatory', 'discussable', 'disdainful', 'diseased', 'disenchanted', 'disgraceful', 'disgruntled', 'disgusted', 'disgusting', 'disheartened', 'disheartening', 'dishonest', 'dishonorable', 'disillusioned', 'disinclined', 'disingenuous', 'disinterested', 'disjointed', 'dislikeable', 'disliked', 'disloyal', 'dismal', 'dismissive', 'disobedient', 'disorderly', 'disorganized', 'disparaging', 'disparate', 'dispassionate', 'dispensable', 'displaced', 'displeased', 'displeasing', 'disposable', 'disproportionate', 'disproved', 'disputable', 'disputatious', 'disputed', 'disreputable', 'disrespectful', 'disruptive', 'dissatisfied', 'dissimilar', 'dissolvable', 'dissolving', 'dissonant', 'dissuasive', 'distant', 'distasteful', 'distinct', 'distinctive', 'distinguished', 'distracted', 'distracting', 'distraught', 'distressed', 'distressing', 'distrustful', 'disturbed', 'disturbing', 'divergent', 'diverging', 'diverse', 'diversified', 'divided', 'divine', 'divisive', 'dizzy', 'dizzying', 'doable', 'documentary', 'dogged', 'doggish', 'dogmatic', 'doleful', 'dollish', 'domed', 'domestic', 'dominant', 'domineering', 'dorsal', 'doting', 'double', 'doubtful', 'doubting', 'dovish', 'dowdy', 'down', 'down-and-out', 'downhearted', 'downloadable', 'downtown', 'downward', 'dozing', 'drab', 'drained', 'dramatic', 'drastic', 'dreaded', 'dreadful', 'dreaming', 'dreamy', 'dreary', 'drenched', 'dress', 'dressy', 'dried', 'dripping', 'drivable', 'driven', 'droll', 'drooping', 'droopy', 'drowsy', 'drunk', 'dry', 'dual', 'dubious', 'due', 'dulcet', 'dull', 'duplicitous', 'durable', 'dusty', 'dutiful', 'dwarfish', 'dwindling', 'dynamic', 'dysfunctional', 'each', 'eager', 'early', 'earnest', 'ear-piercing', 'ear-splitting', 'earthshaking', 'earthy', 'east', 'eastern', 'easy', 'eatable', 'eccentric', 'echoing', 'ecological', 'economic', 'economical', 'economy', 'ecstatic', 'edgy', 'editable', 'educated', 'educational', 'eerie', 'effective', 'effervescent', 'efficacious', 'efficient', 'effortless', 'effusive', 'egalitarian', 'egocentric', 'egomaniacal', 'egotistical', 'eight', 'eighth', 'either', 'elaborate', 'elastic', 'elated', 'elderly', 'electric', 'electrical', 'electrifying', 'electronic', 'elegant', 'elementary', 'elevated', 'elfish', 'eligible', 'elite', 'eloquent', 'elusive', 'emaciated', 'embarrassed', 'embarrassing', 'embattled', 'embittered', 'emblematic', 'emboldened', 'embroiled', 'emergency', 'eminent', 'emotional', 'emotionless', 'empirical', 'empty', 'enamored', 'enchanted', 'enchanting', 'encouraged', 'encouraging', 'encrusted', 'endangered', 'endearing', 'endemic', 'endless', 'endurable', 'enduring', 'energetic', 'energizing', 'enforceable', 'engaging', 'engrossing', 'enhanced', 'enigmatic', 'enjoyable', 'enlarged', 'enlightened', 'enormous', 'enough', 'enraged', 'ensuing', 'enterprising', 'entertained', 'entertaining', 'enthralled', 'enthused', 'enthusiastic', 'enticing', 'entire', 'entranced', 'entrepreneurial', 'enumerable', 'enviable', 'envious', 'environmental', 'episodic', 'equable', 'equal', 'equidistant', 'equitable', 'equivalent', 'erasable', 'erect', 'eroding', 'errant', 'erratic', 'erroneous', 'eruptive', 'escalating', 'esoteric', 'essential', 'established', 'estimated', 'estranged', 'eternal', 'ethereal', 'ethical', 'euphemistic', 'euphoric', 'evasive', 'even', 'evenhanded', 'evening', 'eventful', 'eventual', 'everlasting', 'every', 'evil', 'evocative', 'exacerbating', 'exact', 'exacting', 'exaggerated', 'exalted', 'exasperated', 'exasperating', 'excellent', 'exceptional', 'excessive', 'exchangeable', 'excitable', 'excited', 'exciting', 'exclusive', 'excruciating', 'excusable', 'executable', 'exemplary', 'exhausted', 'exhausting', 'exhaustive', 'exhilarated', 'exhilarating', 'existing', 'exotic', 'expandable', 'expanded', 'expanding', 'expansive', 'expectant', 'expected', 'expedient', 'expeditious', 'expendable', 'expensive', 'experimental', 'expert', 'expired', 'expiring', 'explainable', 'explicit', 'exploding', 'exploitative', 'exploited', 'explosive', 'exponential', 'exposed', 'express', 'expressionistic', 'expressionless', 'expressive', 'exquisite', 'extemporaneous', 'extendable', 'extended', 'extension', 'extensive', 'exterior', 'external', 'extra', 'extra-large', 'extraneous', 'extraordinary', 'extra-small', 'extravagant', 'extreme', 'exuberant', 'eye-popping', 'fabled', 'fabulous', 'facetious', 'facial', 'factitious', 'factual', 'faded', 'fading', 'failed', 'faint', 'fainthearted', 'fair', 'faithful', 'faithless', 'fallacious', 'false', 'falsified', 'faltering', 'familiar', 'famished', 'famous', 'fanatical', 'fanciful', 'fancy', 'fantastic', 'far', 'faraway', 'farcical', 'far-flung', 'farsighted', 'fascinated', 'fascinating', 'fascistic', 'fashionable', 'fast', 'fastest', 'fastidious', 'fast-moving', 'fat', 'fatal', 'fateful', 'fatherly', 'fathomable', 'fathomless', 'fatigued', 'faulty', 'favorable', 'favorite', 'fawning', 'feared', 'fearful', 'fearless', 'fearsome', 'feathered', 'feathery', 'feckless', 'federal', 'feeble', 'feebleminded', 'feeling', 'feigned', 'felonious', 'female', 'feminine', 'fermented', 'ferocious', 'fertile', 'fervent', 'fervid', 'festive', 'fetching', 'fetid', 'feudal', 'feverish', 'few,', 'fewer', 'fictional', 'fictitious', 'fidgeting', 'fidgety', 'fiendish', 'fierce', 'fiery', 'fifth', 'filmy', 'filtered', 'filthy', 'final', 'financial', 'fine', 'finicky', 'finite', 'fireproof', 'firm', 'first', 'fiscal', 'fishy', 'fit', 'fitted', 'fitting', 'five', 'fixable', 'fixed', 'flabby', 'flagrant', 'flaky', 'flamboyant', 'flaming', 'flammable', 'flashy', 'flat', 'flattened', 'flattered', 'flattering', 'flavored', 'flavorful', 'flavorless', 'flawed', 'flawless', 'fleeting', 'flexible', 'flickering', 'flimsy', 'flippant', 'flirtatious', 'floating', 'flooded', 'floppy', 'floral', 'flowering', 'flowery', 'fluent', 'fluffy', 'flushed', 'fluttering', 'flying', 'foamy', 'focused', 'foggy', 'folded', 'following', 'fond', 'foolhardy', 'foolish', 'forbidding', 'forceful', 'foreboding', 'foregoing', 'foreign', 'forensic', 'foreseeable', 'forged', 'forgetful', 'forgettable', 'forgivable', 'forgiving', 'forgotten', 'forked', 'formal', 'formative', 'former', 'formidable', 'formless', 'formulaic', 'forthright', 'fortuitous', 'fortunate', 'forward', 'foul', 'foul-smelling', 'four', 'fourth', 'foxy', 'fractional', 'fractious', 'fragile', 'fragmented', 'fragrant', 'frail', 'frank', 'frantic', 'fraternal', 'fraudulent', 'frayed', 'freakish', 'freaky', 'freckled', 'free', 'freezing', 'frequent', 'fresh', 'fretful', 'fried', 'friendly', 'frightened', 'frightening', 'frightful', 'frigid', 'frilly', 'frisky', 'frivolous', 'front', 'frosty', 'frothy', 'frowning', 'frozen', 'frugal', 'fruitful', 'fruitless', 'fruity', 'frumpy', 'frustrated', 'frustrating', 'fulfilled', 'fulfilling', 'full', 'fully-grown', 'fumbling', 'fuming', 'fun', 'functional', 'fundamental', 'fun-loving', 'funniest', 'funny', 'furious', 'furry', 'furthest', 'furtive', 'fussy', 'futile', 'future', 'futuristic', 'fuzzy', 'gabby', 'gainful', 'gallant', 'galling', 'game', 'gangly', 'garbled', 'gargantuan', 'garish', 'garrulous', 'gasping', 'gaudy', 'gaunt', 'gauzy', 'gawky', 'general', 'generative', 'generic', 'generous', 'genial', 'gentle', 'genuine', 'geographic', 'geologic', 'geometric', 'geriatric', 'ghastly', 'ghostly', 'ghoulish', 'giant', 'giddy', 'gifted', 'gigantic', 'giggling', 'gilded', 'giving', 'glad', 'glamorous', 'glaring', 'glass', 'glassy', 'gleaming', 'glib', 'glistening', 'glittering', 'global', 'globular', 'gloomy', 'glorious', 'glossy', 'glowing', 'gluey', 'glum', 'gluttonous', 'gnarly', 'gold', 'golden', 'good', 'good-looking', 'good-natured', 'gooey', 'goofy', 'gorgeous', 'graceful', 'gracious', 'gradual', 'grainy', 'grand', 'grandiose', 'graphic', 'grateful', 'gratified', 'gratifying', 'grating', 'gratis', 'gratuitous', 'grave', 'gray', 'greasy', 'great', 'greatest', 'greedy', 'green', 'gregarious', 'grey', 'grieving', 'grim', 'grimacing', 'grimy', 'grinding', 'grinning', 'gripping', 'gritty', 'grizzled', 'groaning', 'groggy', 'groomed', 'groovy', 'gross', 'grotesque', 'grouchy', 'growling', 'grown-up', 'grubby', 'grueling', 'gruesome', 'gruff', 'grumbling', 'grumpy', 'guaranteed', 'guarded', 'guiltless', 'guilt-ridden', 'guilty', 'gullible', 'gurgling', 'gushing', 'gushy', 'gusty', 'gutsy', 'habitable', 'habitual', 'haggard', 'hairless', 'hairy', 'half', 'halfhearted', 'hallowed', 'halting', 'handsome', 'handy', 'hanging', 'haphazard', 'hapless', 'happy', 'hard', 'hard-to-find', 'hardworking', 'hardy', 'harebrained', 'harmful', 'harmless', 'harmonic', 'harmonious', 'harried', 'harsh', 'hasty', 'hated', 'hateful', 'haughty', 'haunting', 'hawkish', 'hazardous', 'hazy', 'head', 'heady', 'healthy', 'heartbreaking', 'heartbroken', 'heartless', 'heartrending', 'hearty', 'heated', 'heavenly', 'heavy', 'hectic', 'hefty', 'heinous', 'helpful', 'helpless', 'her', 'heroic', 'hesitant', 'hideous', 'high', 'highest', 'highfalutin', 'high-functioning', 'high-maintenance', 'high-pitched', 'high-risk', 'hilarious', 'his', 'hissing', 'historical', 'hoarse', 'hoggish', 'holiday', 'holistic', 'hollow', 'home', 'homeless', 'homely', 'homeopathic', 'homey', 'homogeneous', 'honest', 'honking', 'honorable', 'hopeful', 'hopeless', 'horizontal', 'hormonal', 'horned', 'horrendous', 'horrible', 'horrid', 'horrific', 'horrified', 'horrifying', 'hospitable', 'hostile', 'hot', 'hot pink', 'hot-blooded', 'hotheaded', 'hot-shot', 'hot-tempered', 'hour-long', 'house', 'howling', 'huffy', 'huge', 'huggable', 'hulking', 'human', 'humanitarian', 'humanlike', 'humble', 'humdrum', 'humid', 'humiliated', 'humiliating', 'humming', 'humongous', 'humorless', 'humorous', 'hungry', 'hurried', 'hurt', 'hurtful', 'hushed', 'husky', 'hydraulic', 'hydrothermal', 'hygienic', 'hyper-active', 'hyperbolic', 'hypercritical', 'hyperirritable', 'hypersensitive', 'hypertensive', 'hypnotic', 'hypnotizable', 'hypothetical', 'hysterical', 'icky', 'iconoclastic', 'icy', 'icy-cold', 'ideal', 'idealistic', 'identical', 'identifiable', 'idiosyncratic', 'idiotic', 'idyllic', 'ignorable', 'ill', 'illegal', 'illegible', 'illegitimate', 'ill-equipped', 'ill-fated', 'ill-humored', 'illicit', 'ill-informed', 'illogical', 'illuminating', 'illusive', 'illustrious', 'imaginable', 'imaginary', 'imaginative', 'imitative', 'immaculate', 'immanent', 'immature', 'immeasurable', 'immediate', 'immense', 'immensurable', 'imminent', 'immobile', 'immodest', 'immoral', 'immortal', 'immovable', 'impartial', 'impassable', 'impassioned', 'impatient', 'impeccable', 'impenetrable', 'imperative', 'imperceptible', 'imperceptive', 'imperfect', 'imperial', 'imperialistic', 'impermeable', 'impersonal', 'impertinent', 'impervious', 'impetuous', 'impish', 'implausible', 'implicit', 'implosive', 'impolite', 'imponderable', 'important', 'imported', 'imposing', 'impossible', 'impoverished', 'impractical', 'imprecise', 'impressionable', 'impressive', 'improbable', 'improper', 'improvable', 'improved', 'improving', 'imprudent', 'impulsive', 'impure', 'inaccessible', 'inaccurate', 'inactive', 'inadequate', 'inadmissible', 'inadvertent', 'inadvisable', 'inalienable', 'inalterable', 'inane', 'inanimate', 'inapplicable', 'inappropriate', 'inapt', 'inarguable', 'inarticulate', 'inartistic', 'inattentive', 'inaudible', 'inauspicious', 'incalculable', 'incandescent', 'incapable', 'incessant', 'incidental', 'inclusive', 'incoherent', 'incomparable', 'incompatible', 'incompetent', 'incomplete', 'incomprehensible', 'inconceivable', 'inconclusive', 'incongruent', 'incongruous', 'inconsequential', 'inconsiderable', 'inconsiderate', 'inconsistent', 'inconsolable', 'inconspicuous', 'incontrovertible', 'inconvenient', 'incorrect', 'incorrigible', 'incorruptible', 'increasing', 'incredible', 'incredulous', 'incremental', 'incurable', 'indecent', 'indecipherable', 'indecisive', 'indefensible', 'indefinable', 'indefinite', 'indelible', 'independent', 'indescribable', 'indestructible', 'indeterminable', 'indeterminate', 'indicative', 'indifferent', 'indigenous', 'indignant', 'indirect', 'indiscreet', 'indiscriminate', 'indispensable', 'indisputable', 'indistinct', 'individual', 'individualistic', 'indivisible', 'indomitable', 'inductive', 'indulgent', 'industrial', 'industrious', 'ineffective', 'ineffectual', 'inefficient', 'inelegant', 'ineloquent', 'inequitable', 'inert', 'inescapable', 'inevitable', 'inexact', 'inexcusable', 'inexhaustible', 'inexpedient', 'inexpensive', 'inexplicable', 'inexpressible', 'inexpressive', 'inextricable', 'infallible', 'infamous', 'infantile', 'infatuated', 'infected', 'infectious', 'inferable', 'inferior', 'infernal', 'infinite', 'infinitesimal', 'inflamed', 'inflammable', 'inflammatory', 'inflatable', 'inflated', 'inflexible', 'influential', 'informal', 'informative', 'informed', 'infrequent', 'infuriated', 'infuriating', 'ingenious', 'ingenuous', 'inglorious', 'ingratiating', 'inhabitable', 'inharmonious', 'inherent', 'inhibited', 'inhospitable', 'inhuman', 'inhumane', 'initial', 'injudicious', 'injured', 'injurious', 'innate', 'inner', 'innocent', 'innocuous', 'innovative', 'innumerable', 'inoffensive', 'inoperable', 'inoperative', 'inopportune', 'inordinate', 'inorganic', 'inquiring', 'inquisitive', 'insatiable', 'inscrutable', 'insecure', 'insensible', 'insensitive', 'inseparable', 'inside', 'insidious', 'insightful', 'insignificant', 'insincere', 'insipid', 'insistent', 'insolent', 'inspirational', 'inspired', 'inspiring', 'instant', 'instantaneous', 'instinctive', 'instinctual', 'institutional', 'instructive', 'instrumental', 'insubordinate', 'insufferable', 'insufficient', 'insulted', 'insulting', 'insurable', 'insurmountable', 'intangible', 'integral', 'intellectual', 'intelligent', 'intelligible', 'intended', 'intense', 'intensive', 'intentional', 'interactive', 'interchangeable', 'interdepartmental', 'interdependent', 'interested', 'interesting', 'interior', 'intermediate', 'intermittent', 'internal', 'international', 'interpersonal', 'interracial', 'intestinal', 'intimate', 'intimidating', 'intolerable', 'intolerant', 'intravenous', 'intrepid', 'intricate', 'intrigued', 'intriguing', 'intrinsic', 'introductory', 'introspective', 'introverted', 'intrusive', 'intuitive', 'invalid', 'invaluable', 'invasive', 'inventive', 'invigorating', 'invincible', 'invisible', 'invited', 'inviting', 'involuntary', 'involved', 'inward', 'irascible', 'irate', 'iridescent', 'irksome', 'iron', 'iron-fisted', 'ironic', 'irrational', 'irreconcilable', 'irrefutable', 'irregular', 'irrelative', 'irrelevant', 'irremovable', 'irreparable', 'irreplaceable', 'irrepressible', 'irresistible', 'irresponsible', 'irretrievably', 'irreverent', 'irreversible', 'irrevocable', 'irritable', 'irritated', 'irritating', 'isolated', 'itchy', 'its', 'itty-bitty', 'jabbering', 'jaded', 'jagged', 'jarring', 'jaundiced', 'jazzy', 'jealous', 'jeering', 'jerky', 'jiggling', 'jittery', 'jobless', 'jocular', 'joint', 'jolly', 'jovial', 'joyful', 'joyless', 'joyous', 'jubilant', 'judgmental', 'judicious', 'juicy', 'jumbled', 'jumpy', 'junior', 'just', 'justifiable', 'juvenile', 'kaput', 'keen', 'key', 'kind', 'kindhearted', 'kindly', 'kinesthetic', 'kingly', 'kitchen', 'knavish', 'knightly', 'knobbed', 'knobby', 'knotty', 'knowable', 'knowing', 'knowledgeable', 'known', 'labored', 'laborious', 'lackadaisical', 'lacking', 'lamentable', 'languid', 'languishing', 'lanky', 'larcenous', 'large', 'larger', 'largest', 'lascivious', 'last', 'lasting', 'late', 'latent', 'later', 'lateral', 'latest', 'latter', 'laudable', 'laughable', 'laughing', 'lavish', 'lawful', 'lawless', 'lax', 'lazy', 'lead', 'leading', 'lean', 'learnable', 'learned', 'leased', 'least', 'leather', 'leathery', 'lecherous', 'leering', 'left', 'left-handed', 'legal', 'legendary', 'legible', 'legislative', 'legitimate', 'lengthy', 'lenient', 'less', 'lesser', 'lesser-known', 'less-qualified', 'lethal', 'lethargic', 'level', 'liable', 'libelous', 'liberal', 'licensed', 'life', 'lifeless', 'lifelike', 'lifelong', 'light', 'light-blue', 'lighthearted', 'likable', 'likeable', 'likely', 'like-minded', 'lily-livered', 'limber', 'limited', 'limitless', 'limp', 'limping', 'linear', 'lined', 'lingering', 'linguistic', 'liquid', 'listless', 'literal', 'literary', 'literate', 'lithe', 'lithographic', 'litigious', 'little', 'livable', 'live', 'lively', 'livid', 'living', 'loathsome', 'local', 'locatable', 'locked', 'lofty', 'logarithmic', 'logical', 'logistic', 'lonely', 'long', 'longer', 'longest', 'longing', 'long-term', 'long-winded', 'loose', 'lopsided', 'loquacious', 'lordly', 'lost', 'loud', 'lousy', 'loutish', 'lovable', 'loveable', 'lovely', 'loving', 'low', 'low-calorie', 'low-carb', 'lower', 'low-fat', 'lowly', 'low-maintenance', 'low-ranking', 'low-risk', 'loyal', 'lucent', 'lucid', 'lucky', 'lucrative', 'ludicrous', 'lukewarm', 'lulling', 'luminescent', 'luminous', 'lumpy', 'lurid', 'luscious', 'lush', 'lustrous', 'luxurious', 'lying', 'lyrical', 'macabre', 'Machiavellian', 'macho', 'mad', 'maddening', 'magenta', 'magic', 'magical', 'magnanimous', 'magnetic', 'magnificent', 'maiden', 'main', 'maintainable', 'majestic', 'major', 'makeable', 'makeshift', 'maladjusted', 'male', 'malevolent', 'malicious', 'malignant', 'malleable', 'mammoth', 'manageable', 'managerial', 'mandatory', 'maneuverable', 'mangy', 'maniacal', 'manic', 'manicured', 'manipulative', 'man-made', 'manual', 'many,', 'marbled', 'marginal', 'marked', 'marketable', 'married', 'marvelous', 'masked', 'massive', 'master', 'masterful', 'matchless', 'material', 'materialistic', 'maternal', 'mathematical', 'matronly', 'matted', 'mature', 'maximum', 'meager', 'mean', 'meandering', 'meaningful', 'meaningless', 'mean-spirited', 'measly', 'measurable', 'meat-eating', 'meaty', 'mechanical', 'medical', 'medicinal', 'meditative', 'medium', 'medium-rare', 'meek', 'melancholy', 'mellow', 'melodic', 'melodious', 'melodramatic', 'melted', 'memorable', 'menacing', 'menial', 'mental', 'merciful', 'merciless', 'mercurial', 'mere', 'merry', 'messy', 'metabolic', 'metallic', 'metaphoric', 'meteoric', 'meticulous', 'microscopic', 'microwaveable', 'middle', 'middle-class', 'midweek', 'mighty', 'mild', 'militant', 'militaristic', 'military', 'milky', 'mincing', 'mind-bending', 'mindful', 'mindless', 'mini', 'miniature', 'minimal', 'minimum', 'minor', 'minute', 'miraculous', 'mirthful', 'miscellaneous', 'mischievous', 'miscreant', 'miserable', 'miserly', 'misguided', 'misleading', 'mission', 'mistaken', 'mistrustful', 'mistrusting', 'misty', 'mixed', 'mnemonic', 'moaning', 'mobile', 'mocking', 'moderate', 'modern', 'modest', 'modified', 'modular', 'moist', 'moldy', 'momentary', 'momentous', 'monetary', 'money-grubbing', 'monopolistic', 'monosyllabic', 'monotone', 'monotonous', 'monstrous', 'monumental', 'moody', 'moral', 'moralistic', 'morbid', 'mordant', 'more', 'moronic', 'morose', 'mortal', 'mortified', 'most', 'mother', 'motherly', 'motionless', 'motivated', 'motivating', 'motivational', 'motor', 'mountain', 'mountainous', 'mournful', 'mouthwatering', 'movable', 'moved', 'moving', 'much', 'muddled', 'muddy', 'muffled', 'muggy', 'multicultural', 'multifaceted', 'multipurpose', 'multitalented', 'mumbled', 'mundane', 'municipal', 'murky', 'muscular', 'mushy', 'musical', 'musky', 'musty', 'mutative', 'mute', 'muted', 'mutinous', 'muttering', 'mutual', 'my', 'myopic', 'mysterious', 'mystic', 'mystical', 'mystified', 'mystifying', 'mythical', 'naive', 'nameless', 'narcissistic', 'narrow', 'narrow-minded', 'nasal', 'nasty', 'national', 'native', 'natural', 'naughty', 'nauseating', 'nauseous', 'nautical', 'navigable', 'navy-blue', 'near', 'nearby', 'nearest', 'nearsighted', 'neat', 'nebulous', 'necessary', 'needless', 'nefarious', 'negative', 'neglected', 'neglectful', 'negligent', 'negligible', 'negotiable', 'neighborly', 'neither', 'nerve-racking', 'nervous', 'neurological', 'neurotic', 'neutral', 'new', 'newest', 'next', 'next-door', 'nice', 'nifty', 'nightmarish', 'nimble', 'nine', 'ninth', 'nippy', 'no', 'noble', 'nocturnal', 'noiseless', 'noisy', 'nominal', 'nonabrasive', 'nonaggressive', 'nonchalant', 'noncommittal', 'noncompetitive', 'nonconsecutive', 'nondescript', 'nondestructive', 'nonexclusive', 'nonnegotiable', 'nonproductive', 'nonrefundable', 'nonrenewable', 'nonresponsive', 'nonrestrictive', 'nonreturnable', 'nonsensical', 'nonspecific', 'nonstop', 'nontransferable', 'nonverbal', 'nonviolent', 'normal', 'north', 'northeast', 'northerly', 'northwest', 'nostalgic', 'nosy', 'notable', 'noticeable', 'notorious', 'novel', 'noxious', 'null', 'numb', 'numberless', 'numbing', 'numerable', 'numeric', 'numerous', 'nutritional', 'nutritious', 'nutty', 'oafish', 'obedient', 'obeisant', 'objectionable', 'objective', 'obligatory', 'obliging', 'oblique', 'oblivious', 'oblong', 'obnoxious', 'obscene', 'obscure', 'observable', 'observant', 'obsessive', 'obsolete', 'obstinate', 'obstructive', 'obtainable', 'obtrusive', 'obtuse', 'obvious', 'occasional', 'occupational', 'occupied', 'oceanic', 'odd', 'odd-looking', 'odiferous', 'odious', 'odorless', 'odorous', 'offbeat', 'offensive', 'offhanded', 'official', 'officious', 'oily', 'OK', 'okay', 'old', 'older', 'oldest', 'old-fashioned', 'ominous', 'omniscient', 'omnivorous', 'one', 'one-hour', 'onerous', 'one-sided', 'only', 'opaque', 'open', 'opened', 'openhanded', 'openhearted', 'opening', 'open-minded', 'operable', 'operatic', 'operational', 'operative', 'opinionated', 'opportune', 'opportunistic', 'opposable', 'opposed', 'opposing', 'opposite', 'oppressive', 'optimal', 'optimistic', 'optional', 'opulent', 'oral', 'orange', 'ordinary', 'organic', 'organizational', 'original', 'ornamental', 'ornate', 'ornery', 'orphaned', 'orthopedic', 'ossified', 'ostentatious', 'other', 'otherwise', 'our', 'outer', 'outermost', 'outgoing', 'outlandish', 'outraged', 'outrageous', 'outside', 'outspoken', 'outstanding', 'outward', 'oval', 'overactive', 'overaggressive', 'overall', 'overambitious', 'overassertive', 'overbearing', 'overcast', 'overcautious', 'overconfident', 'overcritical', 'overcrowded', 'overemotional', 'overenthusiastic', 'overjoyed', 'overoptimistic', 'overpowering', 'overpriced', 'overprotective', 'overqualified', 'overrated', 'oversensitive', 'oversized', 'overt', 'overwhelmed', 'overwhelming', 'overworked', 'overwrought', 'overzealous', 'own', 'oxymoronic', 'padded', 'painful', 'painless', 'painstaking', 'palatable', 'palatial', 'pale', 'pallid', 'palpable', 'paltry', 'pampered', 'panicky', 'panoramic', 'paradoxical', 'parallel', 'paranormal', 'parasitic', 'parched', 'pardonable', 'parental', 'parenthetic', 'parking', 'parsimonious', 'partial', 'particular', 'partisan', 'part-time', 'party', 'passing', 'passionate', 'passive', 'past', 'pastoral', 'patched', 'patchy', 'patented', 'paternal', 'paternalistic', 'pathetic', 'pathological', 'patient', 'patriotic', 'patronizing', 'patterned', 'payable', 'peaceable', 'peaceful', 'peculiar', 'pedantic', 'pedestrian', 'peerless', 'peeved', 'peevish', 'penetrable', 'penetrating', 'pensive', 'peppery', 'perceivable', 'perceptible', 'perceptive', 'perceptual', 'peremptory', 'perennial', 'perfect', 'perfumed', 'perilous', 'period', 'periodic', 'peripheral', 'perishable', 'perky', 'permanent', 'permeable', 'permissible', 'permissive', 'pernicious', 'perpendicular', 'perpetual', 'perplexed', 'perplexing', 'persevering', 'persistent', 'personable', 'personal', 'persuasive', 'pert', 'pertinent', 'perturbed', 'perturbing', 'pervasive', 'pessimistic', 'petite', 'pettish', 'petty', 'petulant', 'pharmaceutical', 'phenomenal', 'philanthropic', 'philosophical', 'phobic', 'phonemic', 'phonetic', 'phosphorescent', 'photographic', 'physical', 'physiological', 'picturesque', 'piercing', 'pigheaded', 'pink', 'pious', 'piquant', 'pitch-dark', 'pitch-perfect', 'piteous', 'pithy', 'pitiful', 'pitiless', 'pivotal', 'placid', 'plaid', 'plain', 'plane', 'planned', 'plastic', 'platonic', 'plausible', 'playful', 'pleading', 'pleasant', 'pleased', 'pleasing', 'pleasurable', 'plentiful', 'pliable', 'plodding', 'plopping', 'plucky', 'plump', 'pluralistic', 'plus', 'plush', 'pneumatic', 'poetic', 'poignant', 'pointless', 'poised', 'poisonous', 'polished', 'polite', 'political', 'polka-dotted', 'polluted', 'polyunsaturated', 'pompous', 'ponderous', 'poor', 'poorer', 'poorest', 'popping', 'popular', 'populous', 'porous', 'portable', 'portly', 'positive', 'possessive', 'possible', 'post hoc', 'posthumous', 'postoperative', 'potable', 'potent', 'potential', 'powdery', 'powerful', 'powerless', 'practical', 'pragmatic', 'praiseworthy', 'precarious', 'precious', 'precipitous', 'precise', 'precocious', 'preconceived', 'predicative', 'predictable', 'predisposed', 'predominant', 'preeminent', 'preemptive', 'prefabricated', 'preferable', 'preferential', 'pregnant', 'prehistoric', 'prejudiced', 'prejudicial', 'preliminary', 'premature', 'premeditated', 'premium', 'prenatal', 'preoccupied', 'preoperative', 'preparative', 'prepared', 'preposterous', 'prescriptive', 'present', 'presentable', 'presidential', 'pressing', 'pressurized', 'prestigious', 'presumable', 'presumptive', 'presumptuous', 'pretend', 'pretentious', 'pretty', 'prevalent', 'preventable', 'preventative', 'preventive', 'previous', 'priceless', 'pricey', 'prickly', 'prim', 'primary', 'primitive', 'primordial', 'princely', 'principal', 'principled', 'prior', 'prissy', 'pristine', 'private', 'prize', 'prized', 'proactive', 'probabilistic', 'probable', 'problematic', 'procedural', 'prodigious', 'productive', 'profane', 'professed', 'professional', 'professorial', 'proficient', 'profitable', 'profound', 'profuse', 'programmable', 'progressive', 'prohibitive', 'prolific', 'prominent', 'promised', 'promising', 'prompt', 'pronounceable', 'pronounced', 'proof', 'proper', 'prophetic', 'proportional', 'proportionate', 'proportioned', 'prospective', 'prosperous', 'protective', 'prototypical', 'proud', 'proverbial', 'provisional', 'provocative', 'provoking', 'proximal', 'proximate', 'prudent', 'prudential', 'prying', 'psychedelic', 'psychiatric', 'public', 'puckish', 'puffy', 'pugnacious', 'pumped', 'punctual', 'pungent', 'punishable', 'punitive', 'puny', 'pure', 'purified', 'puritanical', 'purple', 'purported', 'purposeful', 'purposeless', 'purring', 'pushy', 'pusillanimous', 'putrid', 'puzzled', 'puzzling', 'pyrotechnic', 'quackish', 'quacky', 'quaint', 'qualified', 'qualitative', 'quality', 'quantifiable', 'quantitative', 'quarrelsome', 'queasy', 'queenly', 'querulous', 'questionable', 'quick', 'quick-acting', 'quick-drying', 'quickest', 'quick-minded', 'quick-paced', 'quick-tempered', 'quick-thinking', 'quick-witted', 'quiet', 'quintessential', 'quirky', 'quivering', 'quizzical', 'quotable', 'rabid', 'racial', 'radiant', 'radical', 'radioactive', 'ragged', 'raging', 'rainbow colored', 'rainy', 'rakish', 'rambling', 'rambunctious', 'rampageous', 'rampant', 'rancid', 'rancorous', 'random', 'rank', 'rapid', 'rapid-fire', 'rapturous', 'rare', 'rascally', 'rash', 'rasping', 'raspy', 'rational', 'ratty', 'ravenous', 'raving', 'ravishing', 'raw', 'razor-edged', 'reactive', 'ready', 'real', 'realistic', 'reasonable', 'reassured', 'reassuring', 'rebel', 'rebellious', 'receding', 'recent', 'receptive', 'recessive', 'rechargeable', 'reciprocal', 'reckless', 'reclusive', 'recognizable', 'recognized', 'rectangular', 'rectifiable', 'recurrent', 'recyclable', 'red', 'red-blooded', 'reddish', 'redeemable', 'redolent', 'redundant', 'referential', 'refillable', 'reflective', 'refractive', 'refreshing', 'refundable', 'refurbished', 'refutable', 'regal', 'regional', 'regretful', 'regrettable', 'regular', 'reigning', 'relatable', 'relative', 'relaxed', 'relaxing', 'relentless', 'relevant', 'reliable', 'relieved', 'religious', 'reluctant', 'remaining', 'remarkable', 'remedial', 'reminiscent', 'remorseful', 'remorseless', 'remote', 'removable', 'renegotiable', 'renewable', 'rented', 'repairable', 'repaired', 'repeatable', 'repeated', 'repentant', 'repetitious', 'repetitive', 'replaceable', 'replicable', 'reported', 'reprehensible', 'representative', 'repressive', 'reproachful', 'reproductive', 'republican', 'repugnant', 'repulsive', 'reputable', 'reputed', 'rescued', 'resealable', 'resentful', 'reserved', 'resident', 'residential', 'residual', 'resilient', 'resolute', 'resolvable', 'resonant', 'resounding', 'resourceful', 'respectable', 'respectful', 'respective', 'responsible', 'responsive', 'rested', 'restful', 'restless', 'restored', 'restrained', 'restrictive', 'retired', 'retroactive', 'retrogressive', 'retrospective', 'reusable', 'revamped', 'revealing', 'revengeful', 'reverent', 'reverential', 'reverse', 'reversible', 'reviewable', 'reviled', 'revisable', 'revised', 'revocable', 'revolting', 'revolutionary', 'rewarding', 'rhetorical', 'rhythmic', 'rich', 'richer', 'richest', 'ridiculing', 'ridiculous', 'right', 'righteous', 'rightful', 'right-handed', 'rigid', 'rigorous', 'ringing', 'riotous', 'ripe', 'rippling', 'risky', 'ritualistic', 'ritzy', 'riveting', 'roaring', 'roasted', 'robotic', 'robust', 'rocketing', 'roguish', 'romantic', 'roomy', 'rosy', 'rotating', 'rotten', 'rotting', 'rotund', 'rough', 'round', 'roundtable', 'rousing', 'routine', 'rowdy', 'royal', 'ruddy', 'rude', 'rudimentary', 'rueful', 'rugged', 'ruined', 'ruinous', 'rumbling', 'rumpled', 'ruptured', 'rural', 'rusted', 'rustic', 'rustling', 'rusty', 'ruthless', 'rutted', 'saccharin', 'sacred', 'sacrificial', 'sacrilegious', 'sad', 'saddened', 'safe', 'saintly', 'salacious', 'salient', 'salt', 'salted', 'salty', 'salvageable', 'salvaged', 'same', 'sanctimonious', 'sandy', 'sane', 'sanguine', 'sanitary', 'sappy', 'sarcastic', 'sardonic', 'sassy', 'satin', 'satiny', 'satiric', 'satirical', 'satisfactory', 'satisfied', 'satisfying', 'saucy', 'savage', 'savory', 'savvy', 'scalding', 'scaly', 'scandalous', 'scant', 'scanty', 'scarce', 'scared', 'scarred', 'scary', 'scathing', 'scattered', 'scenic', 'scented', 'scheduled', 'schematic', 'scholarly', 'scholastic', 'scientific', 'scintillating', 'scorching', 'scornful', 'scrabbled', 'scraggly', 'scrappy', 'scratched', 'scratchy', 'scrawny', 'screaming', 'screeching', 'scribbled', 'scriptural', 'scruffy', 'scrumptious', 'scrupulous', 'sculpted', 'sculptural', 'scummy', 'sea', 'sealed', 'seamless', 'searching', 'searing', 'seasick', 'seasonable', 'seasonal', 'secluded', 'second', 'secondary', 'second-hand', 'secret', 'secretive', 'secular', 'secure', 'secured', 'sedate', 'seditious', 'seductive', 'seedy', 'seeming', 'seemly', 'seething', 'seismic', 'select', 'selected', 'selective', 'self-absorbed', 'self-aggrandizing', 'self-assured', 'self-centered', 'self-confident', 'self-directed', 'self-disciplined', 'self-effacing', 'self-indulgent', 'self-interested', 'selfish', 'selfless', 'self-reliant', 'self-respect', 'self-satisfied', 'sellable', 'semiconscious', 'semiofficial', 'semiprecious', 'semiprofessional', 'senior', 'sensational', 'senseless', 'sensible', 'sensitive', 'sensual', 'sensuous', 'sentimental', 'separate', 'sequential', 'serendipitous', 'serene', 'serial', 'serious', 'serrated', 'serviceable', 'seven', 'seventh', 'several', 'severe', 'shabbiest', 'shabby', 'shaded', 'shadowed', 'shadowy', 'shady', 'shaggy', 'shaky', 'shallow', 'shamefaced', 'shameful', 'shameless', 'shapeless', 'shapely', 'sharp', 'sharpened', 'shattered', 'shattering', 'sheepish', 'sheer', 'sheltered', 'shifty', 'shimmering', 'shining', 'shiny', 'shivering', 'shivery', 'shocked', 'shocking', 'shoddy', 'short', 'short-lived', 'shortsighted', 'short-tempered', 'short-term', 'showy', 'shrewd', 'shrieking', 'shrill', 'shut', 'shy', 'sick', 'sickened', 'sickening', 'sickly', 'side-splitting', 'signed', 'significant', 'silent', 'silky', 'silly', 'silver', 'silver-tongued', 'simian', 'similar', 'simple', 'simpleminded', 'simplified', 'simplistic', 'simultaneous', 'sincere', 'sinful', 'single', 'single-minded', 'singular', 'sinister', 'sinuous', 'sisterly', 'six', 'sixth', 'sizable', 'sizzling', 'skeptical', 'sketchy', 'skilled', 'skillful', 'skimpy', 'skin-deep', 'skinny', 'skittish', 'sky-blue', 'slanderous', 'slanted', 'slanting', 'sleek', 'sleeping', 'sleepless', 'sleepy', 'slender', 'slick', 'slight', 'slim', 'slimy', 'slippery', 'sloped', 'sloping', 'sloppy', 'slothful', 'slow-moving', 'sluggish', 'slushy', 'sly', 'small', 'smaller', 'smallest', 'small-minded', 'small-scale', 'small-time', 'small-town', 'smarmy', 'smart', 'smarter', 'smartest', 'smashing', 'smeared', 'smelly', 'smiling', 'smoggy', 'smoked', 'smoky', 'smooth', 'smothering', 'smudged', 'smug', 'snapping', 'snappish', 'snappy', 'snarling', 'sneaky', 'snide', 'snippy', 'snobbish', 'snoopy', 'snooty', 'snoring', 'snow-white', 'snug', 'snuggly', 'soaked', 'soaking', 'soaking wet', 'soaring', 'sober', 'sociable', 'social', 'socialist', 'sociological', 'soft', 'softhearted', 'soggy', 'solar', 'soldierly', 'sole', 'solemn', 'solicitous', 'solid', 'solitary', 'somatic', 'somber', 'some,', 'sonic', 'sonly', 'soothed', 'soothing', 'sophisticated', 'sordid', 'sore', 'sorrowful', 'sorry', 'soulful', 'soulless', 'soundless', 'sour', 'south', 'southeasterly', 'southern', 'southwestern', 'spacious', 'spare', 'sparing', 'sparkling', 'sparkly', 'sparse', 'spasmodic', 'spastic', 'spatial', 'spattered', 'special', 'specialist', 'specialized', 'specific', 'speckled', 'spectacular', 'spectral', 'speculative', 'speechless', 'speedy', 'spellbinding', 'spendthrift', 'spherical', 'spicy', 'spiffy', 'spiky', 'spinal', 'spineless', 'spiral', 'spiraled', 'spirited', 'spiritless', 'spiritual', 'spiteful', 'splashing', 'splashy', 'splattered', 'splendid', 'splintered', 'spoiled', 'spoken', 'spongy', 'spontaneous', 'spooky', 'sporadic', 'sporting', 'spotless', 'spotted', 'spotty', 'springy', 'sprite', 'spry', 'spurious', 'squalid', 'squandered', 'square', 'squashed', 'squashy', 'squatting', 'squawking', 'squealing', 'squeamish', 'squeezable', 'squiggly', 'squirming', 'squirrelly', 'stable', 'stackable', 'staggering', 'stagnant', 'stained', 'stale', 'stanch', 'standard', 'standing', 'standoffish', 'starched', 'star-crossed', 'stark', 'startled', 'startling', 'starving', 'stately', 'static', 'statistical', 'statuesque', 'status', 'statutory', 'staunch', 'steadfast', 'steady', 'stealth', 'steaming', 'steamy', 'steel', 'steely', 'steep', 'stereophonic', 'stereotyped', 'stereotypical', 'sterile', 'stern', 'sticky', 'stifled', 'stifling', 'stigmatic', 'still', 'stilled', 'stilted', 'stimulating', 'stinging', 'stingy', 'stinking', 'stinky', 'stirring', 'stock', 'stodgy', 'stoic', 'stony', 'stormy', 'stout', 'straggly', 'straightforward', 'stranded', 'strange', 'strategic', 'streaked', 'street', 'strenuous', 'stressful', 'stretchy', 'strict', 'strident', 'striking', 'stringent', 'striped', 'strong', 'stronger', 'strongest', 'structural', 'stubborn', 'stubby', 'stuck-up', 'studied', 'studious', 'stuffed', 'stuffy', 'stumbling', 'stunned', 'stunning', 'stupendous', 'sturdy', 'stuttering', 'stylish', 'stylistic', 'suave', 'subconscious', 'subdued', 'subject', 'subjective', 'sublime', 'subliminal', 'submissive', 'subordinate', 'subsequent', 'subservient', 'substantial', 'substantiated', 'substitute', 'subterranean', 'subtitled', 'subtle', 'subversive', 'successful', 'successive', 'succinct', 'succulent', 'such', 'sudden', 'suffering', 'sufficient', 'sugary', 'suggestive', 'suitable', 'sulky', 'sullen', 'sumptuous', 'sunny', 'super', 'superabundant', 'superb', 'supercilious', 'superficial', 'superhuman', 'superior', 'superlative', 'supernatural', 'supersensitive', 'supersonic', 'superstitious', 'supple', 'supportive', 'supposed', 'suppressive', 'supreme', 'sure', 'sure-footed', 'surgical', 'surly', 'surmountable', 'surprised', 'surprising', 'surrealistic', 'survivable', 'susceptible', 'suspected', 'suspicious', 'sustainable', 'swaggering', 'swanky', 'swaying', 'sweaty', 'sweeping', 'sweet', 'sweltering', 'swift', 'swimming', 'swinish', 'swishing', 'swollen', 'swooping', 'syllabic', 'syllogistic', 'symbiotic', 'symbolic', 'symmetrical', 'sympathetic', 'symptomatic', 'synergistic', 'synonymous', 'syntactic', 'synthetic', 'systematic', 'taboo', 'tacit', 'tacky', 'tactful', 'tactical', 'tactless', 'tactual', 'tainted', 'take-charge', 'talented', 'talkative', 'tall', 'taller', 'tallest', 'tame', 'tamed', 'tan', 'tangential', 'tangible', 'tangled', 'tangy', 'tanned', 'tantalizing', 'tapered', 'tardy', 'targeted', 'tarnished', 'tart', 'tasteful', 'tasteless', 'tasty', 'tattered', 'taunting', 'taut', 'taxing', 'teachable', 'tearful', 'tearing', 'teasing', 'technical', 'technological', 'tectonic', 'tedious', 'teenage', 'teensy', 'teeny', 'teeny-tiny', 'telegraphic', 'telekinetic', 'telepathic', 'telephonic', 'telescopic', 'telling', 'temperamental', 'temperate', 'tempestuous', 'temporary', 'tempted', 'tempting', 'ten', 'tenable', 'tenacious', 'tender', 'tenderhearted', 'ten-minute', 'tense', 'tentative', 'tenth', 'tenuous', 'tepid', 'terminal', 'terrestrial', 'terrible', 'terrific', 'terrified', 'terrifying', 'territorial', 'terse', 'tested', 'testy', 'tetchy', 'textual', 'textural', 'thankful', 'thankless', 'that', 'the', 'theatrical', 'their', 'thematic', 'theological', 'theoretical', 'therapeutic', 'thermal', 'these', 'thick', 'thievish', 'thin', 'thinkable', 'third', 'thirsty', 'this', 'thorny', 'thorough', 'those', 'thoughtful', 'thoughtless', 'thrashed', 'threatened', 'threatening', 'three', 'thriftless', 'thrifty', 'thrilled', 'thrilling', 'throbbing', 'thumping', 'thundering', 'thunderous', 'ticking', 'tickling', 'ticklish', 'tidal', 'tidy', 'tight', 'tightfisted', 'time', 'timeless', 'timely', 'timid', 'timorous', 'tiny', 'tipsy', 'tired', 'tireless', 'tiresome', 'tiring', 'tolerable', 'tolerant', 'tonal', 'tone-deaf', 'toneless', 'toothsome', 'toothy', 'top', 'topical', 'topographical', 'tormented', 'torpid', 'torrential', 'torrid', 'torturous', 'total', 'touched', 'touching', 'touchy', 'tough', 'towering', 'toxic', 'traditional', 'tragic', 'trainable', 'trained', 'training', 'traitorous', 'tranquil', 'transcendent', 'transcendental', 'transformational', 'transformative', 'transformed', 'transient', 'transitional', 'transitory', 'translucent', 'transparent', 'transplanted', 'trapped', 'trashed', 'trashy', 'traumatic', 'treacherous', 'treasonable', 'treasonous', 'treasured', 'treatable', 'tremendous', 'tremulous', 'trenchant', 'trendy', 'triangular', 'tribal', 'trick', 'tricky', 'trim', 'tripping', 'trite', 'triumphant', 'trivial', 'tropical', 'troubled', 'troublesome', 'troubling', 'truculent', 'true', 'trusted', 'trustful', 'trusting', 'trustworthy', 'trusty', 'truthful', 'trying', 'tumultuous', 'tuneful', 'tuneless', 'turbulent', 'twinkling', 'twinkly', 'twisted', 'twitchy', 'two', 'typical', 'tyrannical', 'tyrannous', 'ubiquitous', 'ugly', 'ultimate', 'ultraconservative', 'ultrasensitive', 'ultrasonic', 'ultraviolet', 'unabashed', 'unabated', 'unable', 'unacceptable', 'unaccompanied', 'unaccountable', 'unaccustomed', 'unacknowledged', 'unadorned', 'unadulterated', 'unadventurous', 'unadvised', 'unaffected', 'unaffordable', 'unafraid', 'unaggressive', 'unaided', 'unalienable', 'unalterable', 'unaltered', 'unambiguous', 'unanimous', 'unannounced', 'unanswerable', 'unanticipated', 'unapologetic', 'unappealing', 'unappetizing', 'unappreciative', 'unapproachable', 'unashamed', 'unassailable', 'unassertive', 'unassisted', 'unattached', 'unattainable', 'unattractive', 'unauthorized', 'unavailable', 'unavailing', 'unavoidable', 'unbalanced', 'unbearable', 'unbeatable', 'unbeaten', 'unbecoming', 'unbelievable', 'unbelieving', 'unbendable', 'unbending', 'unbiased', 'unblemished', 'unblinking', 'unblushing', 'unbounded', 'unbreakable', 'unbridled', 'uncanny', 'uncaring', 'unceasing', 'unceremonious', 'uncertain', 'unchangeable', 'unchanging', 'uncharacteristic', 'uncharitable', 'uncharted', 'uncivil', 'uncivilized', 'unclassified', 'unclean', 'uncluttered', 'uncomely', 'uncomfortable', 'uncommitted', 'uncommon', 'uncommunicative', 'uncomplaining', 'uncomprehending', 'uncompromising', 'unconcerned', 'unconditional', 'unconfirmed', 'unconquerable', 'unconscionable', 'unconscious', 'unconstitutional', 'unconstrained', 'unconstructive', 'uncontainable', 'uncontrollable', 'unconventional', 'unconvinced', 'unconvincing', 'uncooked', 'uncooperative', 'uncoordinated', 'uncouth', 'uncovered', 'uncreative', 'uncritical', 'undamaged', 'undated', 'undaunted', 'undeclared', 'undefeated', 'undefined', 'undemocratic', 'undeniable', 'undependable', 'underdeveloped', 'underfunded', 'underhanded', 'underprivileged', 'understandable', 'understanding', 'understated', 'understood', 'undeserved', 'undesirable', 'undetected', 'undeterred', 'undeveloped', 'undeviating', 'undifferentiated', 'undignified', 'undiminished', 'undiplomatic', 'undisciplined', 'undiscovered', 'undisguised', 'undisputed', 'undistinguished', 'undivided', 'undoubted', 'unearthly', 'uneasy', 'uneducated', 'unemotional', 'unemployed', 'unencumbered', 'unending', 'unendurable', 'unenforceable', 'unenthusiastic', 'unenviable', 'unequal', 'unequaled', 'unequivocal', 'unerring', 'uneven', 'uneventful', 'unexceptional', 'unexcited', 'unexpected', 'unexplainable', 'unexplored', 'unexpressive', 'unfailing', 'unfair', 'unfaithful', 'unfaltering', 'unfamiliar', 'unfashionable', 'unfathomable', 'unfavorable', 'unfeeling', 'unfettered', 'unfilled', 'unflagging', 'unflappable', 'unflattering', 'unflinching', 'unfocused', 'unforeseeable', 'unforgettable', 'unforgivable', 'unforgiving', 'unfortunate', 'unfriendly', 'unfulfilled', 'ungallant', 'ungenerous', 'ungentlemanly', 'unglamorous', 'ungraceful', 'ungracious', 'ungrateful', 'unguarded', 'unhandsome', 'unhappy', 'unharmed', 'unhealthy', 'unheated', 'unheeded', 'unhelpful', 'unhesitating', 'unhurried', 'uniform', 'unilateral', 'unimaginable', 'unimaginative', 'unimpeachable', 'unimpeded', 'unimpressive', 'unincorporated', 'uninformed', 'uninhabitable', 'uninhibited', 'uninitiated', 'uninjured', 'uninspired', 'uninsurable', 'unintelligent', 'unintelligible', 'unintended', 'unintentional', 'uninterested', 'uninterrupted', 'uninvited', 'unique', 'united', 'universal', 'unjust', 'unjustifiable', 'unkempt', 'unkind', 'unknowing', 'unknown', 'unlawful', 'unlicensed', 'unlikable', 'unlikely', 'unlivable', 'unloved', 'unlucky', 'unmanageable', 'unmanned', 'unmarketable', 'unmasked', 'unmatched', 'unmemorable', 'unmentionable', 'unmerciful', 'unmistakable', 'unmitigated', 'unmodified', 'unmotivated', 'unnatural', 'unnecessary', 'unnerved', 'unnerving', 'unnoticeable', 'unobserved', 'unobtainable', 'unobtrusive', 'unofficial', 'unopened', 'unopposed', 'unorthodox', 'unostentatious', 'unpalatable', 'unpardonable', 'unpersuasive', 'unperturbed', 'unplanned', 'unpleasant', 'unprecedented', 'unpredictable', 'unpretentious', 'unprincipled', 'unproductive', 'unprofessional', 'unprofitable', 'unpromising', 'unpronounceable', 'unprovoked', 'unqualified', 'unquantifiable', 'unquenchable', 'unquestionable', 'unquestioned', 'unquestioning', 'unraveled', 'unreachable', 'unreadable', 'unrealistic', 'unrealized', 'unreasonable', 'unreceptive', 'unrecognizable', 'unrecognized', 'unredeemable', 'unregulated', 'unrelenting', 'unreliable', 'unremarkable', 'unremitting', 'unrepentant', 'unrepresentative', 'unrepresented', 'unreserved', 'unrespectable', 'unresponsive', 'unrestrained', 'unripe', 'unrivaled', 'unromantic', 'unruffled', 'unruly', 'unsafe', 'unsalvageable', 'unsatisfactory', 'unsatisfied', 'unscheduled', 'unscholarly', 'unscientific', 'unscrupulous', 'unseasonable', 'unseemly', 'unselfish', 'unsettled', 'unsettling', 'unshakable', 'unshapely', 'unsightly', 'unsigned', 'unsinkable', 'unskilled', 'unsociable', 'unsolicited', 'unsolvable', 'unsolved', 'unsophisticated', 'unsound', 'unsparing', 'unspeakable', 'unspoiled', 'unstable', 'unstated', 'unsteady', 'unstoppable', 'unstressed', 'unstructured', 'unsubstantial', 'unsubstantiated', 'unsuccessful', 'unsuitable', 'unsuited', 'unsupervised', 'unsupported', 'unsure', 'unsurpassable', 'unsurpassed', 'unsurprising', 'unsuspected', 'unsuspecting', 'unsustainable', 'unsympathetic', 'unsystematic', 'untainted', 'untamable', 'untamed', 'untapped', 'untenable', 'untested', 'unthinkable', 'unthinking', 'untidy', 'untimely', 'untitled', 'untouchable', 'untraditional', 'untrained', 'untried', 'untroubled', 'untrustworthy', 'untruthful', 'unused', 'unusual', 'unverified', 'unwary', 'unwashed', 'unwatchable', 'unwavering', 'unwholesome', 'unwieldy', 'unwilling', 'unwise', 'unwitting', 'unworkable', 'unworldly', 'unworthy', 'unwritten', 'unyielding', 'upbeat', 'upmost', 'upper', 'uppity', 'upright', 'uproarious', 'upset', 'upsetting', 'upstairs', 'uptight', 'up-to-date', 'up-to-the-minute', 'upward', 'urbane', 'urgent', 'usable', 'used', 'useful', 'useless', 'usual', 'utilitarian', 'utopian', 'utter', 'uttermost', 'vacant', 'vacillating', 'vacuous', 'vagabond', 'vagrant', 'vague', 'vain', 'valiant', 'valid', 'valorous', 'valuable', 'vanishing', 'vapid', 'vaporous', 'variable', 'varied', 'various', 'varying', 'vast', 'vegetable', 'vegetarian', 'vegetative', 'vehement', 'velvety', 'venal', 'venerable', 'vengeful', 'venomous', 'venturesome', 'venturous', 'veracious', 'verbal', 'verbose', 'verdant', 'verifiable', 'verified', 'veritable', 'vernacular', 'versatile', 'versed', 'vertical', 'very', 'vexed', 'vexing', 'viable', 'vibrant', 'vibrating', 'vicarious', 'vicious', 'victorious', 'vigilant', 'vigorous', 'vile', 'villainous', 'vindictive', 'vinegary', 'violent', 'violet', 'viperous', 'viral', 'virtual', 'virtuous', 'virulent', 'visceral', 'viscous', 'visible', 'visionary', 'visual', 'vital', 'vitriolic', 'vivacious', 'vivid', 'vocal', 'vocational', 'voiceless', 'volatile', 'volcanic', 'voluminous', 'voluntary', 'voluptuous', 'voracious', 'vulgar', 'vulnerable', 'wacky', 'wailing', 'waiting', 'wakeful', 'wandering', 'wanting', 'wanton', 'warlike', 'warm', 'warmest', 'warning', 'warring', 'wary', 'waspish', 'waste', 'wasted', 'wasteful', 'watchful', 'waterlogged', 'waterproof', 'watertight', 'watery', 'wavering', 'wax', 'waxen', 'weak', 'weakened', 'weak-willed', 'wealthy', 'wearisome', 'weary', 'wee', 'weedy', 'week-long', 'weekly', 'weightless', 'weighty', 'weird', 'welcoming', 'well', 'well-adjusted', 'well-argued', 'well-aware', 'well-balanced', 'well-behaved', 'well-built', 'well-conceived', 'well-considered', 'well-crafted', 'well-deserved', 'well-developed', 'well-done', 'well-dressed', 'well-educated', 'well-equipped', 'well-established', 'well-founded', 'well-groomed', 'well-heeled', 'well-honed', 'well-informed', 'well-intentioned', 'well-kempt', 'well-known', 'well-liked', 'well-lit', 'well-made', 'well-maintained', 'well-mannered', 'well-meaning', 'well-off', 'well-placed', 'well-planned', 'well-prepared', 'well-qualified', 'well-read', 'well-received', 'well-rounded', 'well-spoken', 'well-suited', 'well-thought-of', 'well-thought-out', 'well-to-do', 'well-traveled', 'well-used', 'well-versed', 'well-worn', 'well-written', 'west', 'western', 'wet', 'what', 'wheezing', 'which', 'whimpering', 'whimsical', 'whining', 'whispering', 'whistling', 'white', 'whole', 'wholehearted', 'wholesale', 'wholesome', 'whooping', 'whopping', 'whose', 'wicked', 'wide', 'wide-eyed', 'wide-ranging', 'widespread', 'wiggly', 'wild', 'willful', 'willing', 'wily', 'windy', 'winning', 'winsome', 'winter', 'wintery', 'wiry', 'wise', 'wishful', 'wispy', 'wistful', 'withering', 'witless', 'witty', 'wizardly', 'wobbly', 'woeful', 'wolfish', 'wonderful', 'wondrous', 'wonted', 'wood', 'wooden', 'wooing', 'wool', 'woolen', 'woozy', 'wordless', 'wordy', 'work', 'workable', 'working', 'work-oriented', 'worldly', 'worn', 'worn down', 'worn out', 'worried', 'worrisome', 'worrying', 'worse', 'worshipful', 'worst', 'worth', 'worthless', 'worthwhile', 'worthy', 'wounding', 'wrathful', 'wrenching', 'wretched', 'wriggling', 'wriggly', 'wrinkled', 'wrinkly', 'written', 'wrong', 'wrongful', 'wry', 'yawning', 'yearly', 'yearning', 'yellow', 'yelping', 'yielding', 'young', 'younger', 'youngest', 'youthful', 'yummy', 'zany', 'zealous', 'zestful', 'zesty', 'zippy', 'zonked', 'zoological']
nouns = ['aardvark', 'abacus', 'abbey', 'abbreviation', 'abdomen', 'ability', 'abnormality', 'abolishment', 'abortion', 'abrogation', 'absence', 'abundance', 'academics', 'academy', 'accelerant', 'accelerator', 'accent', 'acceptance', 'access', 'accessory', 'accident', 'accommodation', 'accompanist', 'accomplishment', 'accord', 'accordance', 'accordion', 'account', 'accountability', 'accountant', 'accounting', 'accuracy', 'accusation', 'acetate', 'achievement', 'achiever', 'acid', 'acknowledgment', 'acoustics', 'acquaintance', 'acquisition', 'acre', 'acrylic', 'act', 'action', 'activation', 'activist', 'activity', 'actor', 'actress', 'acupuncture', 'ad', 'adaptation', 'adapter', 'addiction', 'addition', 'address', 'adjective', 'adjustment', 'admin', 'administration', 'administrator', 'admire', 'admission', 'adobe', 'adoption', 'adrenalin', 'adrenaline', 'advance', 'advancement', 'advantage', 'advent', 'advertisement', 'advertising', 'advice', 'adviser', 'advocacy', 'advocate', 'affair', 'affect', 'affidavit', 'affiliate', 'affinity', 'afoul', 'afterlife', 'aftermath', 'afternoon', 'aftershave', 'aftershock', 'afterthought', 'age', 'agency', 'agenda', 'agent', 'aggradation', 'aggression', 'aglet', 'agony', 'agreement', 'agriculture', 'aid', 'aide', 'aim', 'air', 'airbag', 'airbus', 'aircraft', 'airfare', 'airfield', 'airforce', 'airline', 'airmail', 'airman', 'airplane', 'airport', 'airship', 'airspace', 'alarm', 'alb', 'albatross', 'album', 'alcohol', 'alcove', 'alder', 'alert', 'algebra', 'algorithm', 'alias', 'alibi', 'alien', 'allegation', 'allergist', 'alley', 'alliance', 'alligator', 'allocation', 'allowance', 'alloy', 'alluvium', 'almanac', 'almighty', 'almond', 'alpaca', 'alpenglow', 'alpenhorn', 'alpha', 'alphabet', 'altar', 'alteration', 'alternative', 'altitude', 'alto', 'aluminium', 'aluminum', 'amazement', 'amazon', 'ambassador', 'amber', 'ambience', 'ambiguity', 'ambition', 'ambulance', 'amendment', 'amenity', 'ammunition', 'amnesty', 'amount', 'amusement', 'anagram', 'analgesia', 'analog', 'analogue', 'analogy', 'analysis', 'analyst', 'analytics', 'anarchist', 'anarchy', 'anatomy', 'ancestor', 'android', 'anesthesiologist', 'anesthesiology', 'angel', 'anger', 'angina', 'angiosperm', 'angle', 'angora', 'angstrom', 'anguish', 'animal', 'anime', 'ankle', 'anklet', 'anniversary', 'announcement', 'annual', 'anorak', 'answer', 'ant', 'anteater', 'antecedent', 'antechamber', 'antelope', 'antennae', 'anterior', 'anthropology', 'antibody', 'anticipation', 'anticodon', 'antigen', 'antique', 'antiquity', 'antler', 'anxiety', 'anybody', 'anyone', 'anything', 'anywhere', 'apartment', 'ape', 'aperitif', 'apology', 'app', 'apparatus', 'apparel', 'appeal', 'appearance', 'appellation', 'appendix', 'appetite', 'applause', 'apple', 'applewood', 'appliance', 'application', 'appointment', 'appreciation', 'apprehension', 'approach', 'appropriation', 'approval', 'apron', 'apse', 'aquarium', 'aquifer', 'arcade', 'arch', 'arch-rival', 'archaeologist', 'archaeology', 'archeology', 'archer', 'architect', 'architecture', 'archives', 'area', 'arena', 'argument', 'arithmetic', 'ark', 'arm', 'arm-rest', 'armadillo', 'armament', 'armchair', 'armoire', 'armor', 'armour', 'armpit', 'armrest', 'army', 'arrangement', 'array', 'arrest', 'arrival', 'arrogance', 'arrow', 'art', 'artery', 'arthur', 'artichoke', 'article', 'artifact', 'artificer', 'artist', 'ascend', 'ascent', 'ascot', 'ash', 'ashram', 'ashtray', 'aside', 'asparagus', 'aspect', 'asphalt', 'ass', 'assassination', 'assault', 'assembly', 'assertion', 'assessment', 'asset', 'assignment', 'assist', 'assistance', 'assistant', 'associate', 'association', 'assumption', 'assurance', 'asterisk', 'astrakhan', 'astrolabe', 'astrologer', 'astrology', 'astronomy', 'asymmetry', 'atelier', 'atheist', 'athlete', 'athletics', 'ATM', 'atmosphere', 'atom', 'atrium', 'attachment', 'attack', 'attacker', 'attainment', 'attempt', 'attendance', 'attendant', 'attention', 'attenuation', 'attic', 'attitude', 'attorney', 'attraction', 'attribute', 'auction', 'audience', 'audit', 'auditorium', 'aunt', 'authentication', 'authenticity', 'author', 'authorisation', 'authority', 'authorization', 'auto', 'autoimmunity', 'automaton', 'autumn', 'availability', 'avalanche', 'avenue', 'average', 'award', 'awareness', 'awe', 'axis', 'azimuth', 'babe', 'baboon', 'babushka', 'baby', 'bachelor', 'back', 'back-up', 'backbone', 'backburn', 'backdrop', 'background', 'backpack', 'backup', 'backyard', 'bacon', 'bacterium', 'badge', 'badger', 'bafflement', 'bag', 'bagel', 'baggage', 'baggy', 'bagpipe', 'bail', 'bait', 'bake', 'baker', 'bakery', 'bakeware', 'balaclava', 'balalaika', 'balance', 'balcony', 'ball', 'ballet', 'balloon', 'balloonist', 'ballot', 'ballpark', 'bamboo', 'ban', 'banana', 'band', 'bandana', 'bandanna', 'bandolier', 'bandwidth', 'bangle', 'banjo', 'bank', 'bankbook', 'banker', 'banking', 'bankruptcy', 'banner', 'banquette', 'banyan', 'baobab', 'bar', 'barbecue', 'barbeque', 'barber', 'barbiturate', 'bargain', 'barge', 'baritone', 'barium', 'bark', 'barn', 'barometer', 'barracks', 'barrage', 'barrel', 'barrier', 'barstool', 'bartender', 'base', 'baseball', 'baseboard', 'baseline', 'basement', 'basics', 'basin', 'basis', 'basket', 'basketball', 'bass', 'bassinet', 'bassoon', 'bat', 'bath', 'bather', 'bathhouse', 'bathrobe', 'bathroom', 'bathtub', 'battalion', 'batter', 'battery', 'batting', 'battle', 'battleship', 'bay', 'bayou', 'beach', 'bead', 'beak', 'beam', 'bean', 'beanie', 'beanstalk', 'bear', 'beard', 'beast', 'beastie', 'beat', 'beating', 'beauty', 'beaver', 'beck', 'bed', 'bedrock', 'bedroom', 'bee', 'beech', 'beef', 'beer', 'beet', 'beetle', 'beggar', 'beginner', 'beginning', 'begonia', 'behalf', 'behavior', 'behaviour', 'beheading', 'behest', 'behold', 'being', 'belfry', 'belief', 'believer', 'bell', 'belligerency', 'bellows', 'belly', 'belt', 'ben', 'bench', 'bend', 'beneficiary', 'benefit', 'bengal', 'beret', 'berry', 'best-seller', 'bestseller', 'bet', 'beverage', 'beyond', 'bias', 'bibliography', 'bicycle', 'bid', 'bidder', 'bidding', 'bidet', 'bifocals', 'bijou', 'bike', 'bikini', 'bill', 'billboard', 'billing', 'billion', 'bin', 'binoculars', 'biology', 'biopsy', 'biosphere', 'biplane', 'birch', 'bird', 'bird-watcher', 'birdbath', 'birdcage', 'birdhouse', 'birth', 'birthday', 'bit', 'bite', 'bitter', 'black', 'blackberry', 'blackbird', 'blackboard', 'blackfish', 'bladder', 'blade', 'blame', 'blank', 'blanket', 'blast', 'blazer', 'blend', 'blessing', 'blight', 'blinker', 'blister', 'blizzard', 'block', 'blocker', 'blog', 'blogger', 'blood', 'bloodflow', 'bloom', 'bloomer', 'bloomers', 'blossom', 'blouse', 'blow', 'blowgun', 'blowhole', 'blue', 'blueberry', 'blush', 'boar', 'board', 'boat', 'boatload', 'boatyard', 'bob', 'bobcat', 'body', 'bog', 'bolero', 'bolt', 'bomb', 'bomber', 'bombing', 'bond', 'bonding', 'bondsman', 'bone', 'bonfire', 'bongo', 'bonnet', 'bonsai', 'bonus', 'boogeyman', 'book', 'bookcase', 'bookend', 'booking', 'booklet', 'boolean', 'boom', 'boon', 'boost', 'booster', 'boot', 'bootee', 'bootie', 'booty', 'border', 'bore', 'borrower', 'borrowing', 'bosom', 'boss', 'botany', 'bother', 'bottle', 'bottling', 'bottom', 'bottom-line', 'boudoir', 'bough', 'boulder', 'boulevard', 'boundary', 'bouquet', 'bourgeoisie', 'bout', 'boutique', 'bow', 'bower', 'bowl', 'bowler', 'bowling', 'bowtie', 'box', 'boxer', 'boxspring', 'boy', 'boycott', 'boyfriend', 'boyhood', 'bra', 'brace', 'bracelet', 'bracket', 'brain', 'brake', 'branch', 'brand', 'brandy', 'brass', 'brassiere', 'bratwurst', 'bread', 'breadcrumb', 'break', 'breakdown', 'breakfast', 'breakpoint', 'breakthrough', 'breastplate', 'breath', 'breeze', 'brewer', 'bribery', 'brick', 'bricklaying', 'bride', 'bridge', 'brief', 'briefing', 'briefly', 'briefs', 'brilliant', 'brink', 'broad', 'broadcast', 'broccoli', 'brochure', 'broiler', 'broker', 'bronchitis', 'bronco', 'bronze', 'brooch', 'brood', 'brook', 'broom', 'brother', 'brother-in-law', 'brow', 'brown', 'browser', 'browsing', 'brush', 'brushfire', 'brushing', 'bubble', 'buck', 'bucket', 'buckle', 'bud', 'buddy', 'budget', 'buffalo', 'buffer', 'buffet', 'bug', 'buggy', 'bugle', 'building', 'bulb', 'bulk', 'bull', 'bull-fighter', 'bulldozer', 'bullet', 'bump', 'bumper', 'bun', 'bunch', 'bungalow', 'bunghole', 'bunkhouse', 'burden', 'bureau', 'burglar', 'burial', 'burlesque', 'burn', 'burn-out', 'burning', 'burst', 'bus', 'bush', 'business', 'businessman', 'bust', 'bustle', 'butane', 'butcher', 'butler', 'butter', 'butterfly', 'button', 'buy', 'buyer', 'buying', 'buzz', 'buzzard', 'c-clamp', 'cabana', 'cabbage', 'cabin', 'cabinet', 'cable', 'caboose', 'cacao', 'cactus', 'caddy', 'cadet', 'cafe', 'caffeine', 'caftan', 'cage', 'cake', 'calcification', 'calculation', 'calculator', 'calculus', 'calendar', 'calf', 'caliber', 'calibre', 'calico', 'call', 'calm', 'camel', 'cameo', 'camera', 'camp', 'campaign', 'campaigning', 'campanile', 'camper', 'campus', 'can', 'canal', 'cancel', 'cancer', 'candelabra', 'candidacy', 'candidate', 'candle', 'candy', 'cane', 'cannibal', 'cannon', 'canoe', 'canon', 'canopy', 'canteen', 'canvas', 'cap', 'capability', 'capacity', 'cape', 'capital', 'capitalism', 'capitulation', 'capon', 'cappelletti', 'cappuccino', 'captain', 'caption', 'captor', 'car', 'caravan', 'carbon', 'carboxyl', 'card', 'cardboard', 'cardigan', 'care', 'career', 'cargo', 'carload', 'carnation', 'carnival', 'carol', 'carotene', 'carp', 'carpenter', 'carpet', 'carpeting', 'carport', 'carriage', 'carrier', 'carrot', 'carry', 'cart', 'cartel', 'carter', 'cartilage', 'cartload', 'cartoon', 'cartridge', 'carving', 'cascade', 'case', 'casement', 'cash', 'cashier', 'casino', 'casket', 'casserole', 'cassock', 'cast', 'castanet', 'castle', 'casualty', 'cat', 'catacomb', 'catalogue', 'catalysis', 'catalyst', 'catamaran', 'catastrophe', 'catch', 'catcher', 'category', 'caterpillar', 'cathedral', 'cation', 'catsup', 'cattle', 'cauliflower', 'causal', 'cause', 'causeway', 'caution', 'cave', 'caviar', 'CD', 'ceiling', 'celebration', 'celebrity', 'celeriac', 'celery', 'cell', 'cellar', 'cello', 'celsius', 'cement', 'cemetery', 'cenotaph', 'census', 'cent', 'center', 'centimeter', 'centre', 'centurion', 'century', 'cephalopod', 'ceramic', 'ceramics', 'cereal', 'ceremony', 'certainty', 'certificate', 'certification', 'cesspool', 'chafe', 'chain', 'chainstay', 'chair', 'chairlift', 'chairman', 'chairperson', 'chaise', 'chalet', 'chalice', 'chalk', 'challenge', 'chamber', 'champagne', 'champion', 'championship', 'chance', 'chandelier', 'change', 'channel', 'chaos', 'chap', 'chapel', 'chaplain', 'chapter', 'character', 'characteristic', 'characterization', 'chard', 'charge', 'charity', 'charlatan', 'charm', 'charset', 'chart', 'charter', 'chasm', 'chassis', 'chastity', 'chasuble', 'chateau', 'chatter', 'chauffeur', 'check', 'checking', 'checkout', 'checkroom', 'cheek', 'cheer', 'cheese', 'cheetah', 'chef', 'chem', 'chemical', 'chemistry', 'chemotaxis', 'cheque', 'cherry', 'chess', 'chest', 'chick', 'chicken', 'chicory', 'chief', 'chiffonier', 'child', 'childbirth', 'childhood', 'chili', 'chill', 'chime', 'chimpanzee', 'chin', 'chino', 'chip', 'chipmunk', 'chit-chat', 'chivalry', 'chive', 'chocolate', 'choice', 'choir', 'choker', 'cholesterol', 'choosing', 'chop', 'chopstick', 'chord', 'chorus', 'chowder', 'chrome', 'chromolithograph', 'chronicle', 'chronograph', 'chronometer', 'chub', 'chuck', 'chug', 'church', 'churn', 'cicada', 'cigarette', 'cinema', 'circadian', 'circle', 'circuit', 'circulation', 'circumference', 'circumstance', 'cirrhosis', 'cirrus', 'citizen', 'citizenship', 'city', 'civilian', 'civilisation', 'civilization', 'claim', 'clam', 'clan', 'clank', 'clapboard', 'clarification', 'clarinet', 'clarity', 'clasp', 'class', 'classic', 'classification', 'classmate', 'classroom', 'clause', 'clave', 'clavicle', 'clavier', 'claw', 'clay', 'cleaner', 'clearance', 'clearing', 'cleat', 'cleavage', 'clef', 'cleft', 'clergyman', 'cleric', 'clerk', 'click', 'client', 'cliff', 'climate', 'climb', 'clinic', 'clip', 'clipboard', 'clipper', 'cloak', 'cloakroom', 'clock', 'clockwork', 'clogs', 'cloister', 'clone', 'close', 'closet', 'closing', 'closure', 'cloth', 'clothes', 'clothing', 'cloud', 'cloudburst', 'clove', 'clover', 'club', 'clue', 'cluster', 'clutch', 'co-producer', 'coach', 'coal', 'coalition', 'coast', 'coat', 'cob', 'cobweb', 'cockpit', 'cockroach', 'cocktail', 'cocoa', 'coconut', 'cod', 'code', 'codepage', 'codon', 'codpiece', 'coevolution', 'cofactor', 'coffee', 'coffin', 'cohesion', 'cohort', 'coil', 'coin', 'coincidence', 'coinsurance', 'coke', 'cold', 'coliseum', 'collaboration', 'collagen', 'collapse', 'collar', 'collateral', 'colleague', 'collection', 'collectivisation', 'collectivization', 'collector', 'college', 'collision', 'colloquy', 'colon', 'colonial', 'colonialism', 'colonisation', 'colonization', 'colony', 'color', 'colorlessness', 'colt', 'column', 'columnist', 'comb', 'combat', 'combination', 'combine', 'comeback', 'comedy', 'comfort', 'comfortable', 'comic', 'comics', 'comma', 'command', 'commander', 'commandment', 'comment', 'commerce', 'commercial', 'commission', 'commitment', 'committee', 'commodity', 'common', 'commonsense', 'commotion', 'communicant', 'communication', 'communion', 'communist', 'community', 'commuter', 'company', 'comparison', 'compass', 'compassion', 'compassionate', 'compensation', 'competence', 'competition', 'competitor', 'complaint', 'complement', 'completion', 'complex', 'complexity', 'compliance', 'complication', 'complicity', 'compliment', 'component', 'comportment', 'composer', 'composite', 'composition', 'compost', 'comprehension', 'compress', 'compromise', 'comptroller', 'compulsion', 'computer', 'comradeship', 'con', 'concentrate', 'concentration', 'concept', 'conception', 'concern', 'concert', 'conclusion', 'concrete', 'condition', 'condominium', 'condor', 'conduct', 'conductor', 'cone', 'confectionery', 'conference', 'confidence', 'confidentiality', 'configuration', 'confirmation', 'conflict', 'conformation', 'confusion', 'conga', 'congo', 'congregation', 'congress', 'congressman', 'congressperson', 'conifer', 'connection', 'connotation', 'conscience', 'consciousness', 'consensus', 'consent', 'consequence', 'conservation', 'conservative', 'consideration', 'consignment', 'consist', 'consistency', 'console', 'consonant', 'conspiracy', 'conspirator', 'constant', 'constellation', 'constitution', 'constraint', 'construction', 'consul', 'consulate', 'consulting', 'consumer', 'consumption', 'contact', 'contact lens', 'contagion', 'container', 'content', 'contention', 'contest', 'context', 'continent', 'contingency', 'continuity', 'contour', 'contract', 'contractor', 'contrail', 'contrary', 'contrast', 'contribution', 'contributor', 'control', 'controller', 'controversy', 'convection', 'convenience', 'convention', 'conversation', 'conversion', 'convert', 'convertible', 'conviction', 'cook', 'cookie', 'cooking', 'coonskin', 'cooperation', 'coordination', 'coordinator', 'cop', 'cop-out', 'cope', 'copper', 'copy', 'copying', 'copyright', 'copywriter', 'coral', 'cord', 'corduroy', 'core', 'cork', 'cormorant', 'corn', 'corner', 'cornerstone', 'cornet', 'corporal', 'fall', 'fallacy', 'falling-out', 'fame', 'familiar', 'familiarity', 'family', 'fan', 'fang', 'fanlight', 'fanny', 'fanny-pack', 'fantasy', 'farm', 'farmer', 'farming', 'farmland', 'fascia', 'fashion', 'fat', 'fate', 'father', 'father-in-law', 'fatigue', 'fatigues', 'faucet', 'fault', 'fav', 'favor', 'favorite', 'fawn', 'fax', 'fear', 'feast', 'feather', 'feature', 'fedelini', 'federation', 'fedora', 'fee', 'feed', 'feedback', 'feeding', 'feel', 'feeling', 'fellow', 'felony', 'female', 'fen', 'fence', 'fencing', 'fender', 'feng', 'ferry', 'ferryboat', 'fertilizer', 'festival', 'fetus', 'few', 'fiber', 'fiberglass', 'fibre', 'fibroblast', 'fibrosis', 'ficlet', 'fiction', 'fiddle', 'field', 'fiery', 'fiesta', 'fifth', 'fig', 'fight', 'fighter', 'figure', 'figurine', 'file', 'filing', 'fill', 'filly', 'film', 'filter', 'filth', 'final', 'finance', 'financing', 'finding', 'fine', 'finer', 'finger', 'fingernail', 'finish', 'finisher', 'fir', 'fire', 'fireman', 'fireplace', 'firewall', 'firm', 'first', 'fish', 'fishbone', 'fisherman', 'fishery', 'fishing', 'fishmonger', 'fishnet', 'fisting', 'fit', 'fitness', 'fix', 'fixture', 'flag', 'flair', 'flame', 'flanker', 'flare', 'flash', 'flat', 'flatboat', 'flavor', 'flax', 'fleck', 'fleece', 'flesh', 'flexibility', 'flick', 'flicker', 'flight', 'flint', 'flintlock', 'flip-flops', 'flock', 'flood', 'floodplain', 'floor', 'flour', 'flow', 'flower', 'flu', 'flugelhorn', 'fluke', 'flume', 'flung', 'flute', 'fly', 'flytrap', 'foam', 'fob', 'focus', 'fog', 'fold', 'folder', 'folk', 'folklore', 'follower', 'following', 'fondue', 'font', 'food', 'fool', 'foot', 'footage', 'football', 'footnote', 'footprint', 'footrest', 'footstep', 'footstool', 'footwear', 'forage', 'forager', 'foray', 'force', 'ford', 'forearm', 'forebear', 'forecast', 'forehead', 'foreigner', 'forelimb', 'forest', 'forestry', 'forever', 'forgery', 'fork', 'form', 'formal', 'formamide', 'format', 'formation', 'former', 'formula', 'fort', 'forte', 'fortnight', 'fortress', 'fortune', 'forum', 'foundation', 'founder', 'founding', 'fountain', 'fourths', 'fowl', 'fox', 'foxglove', 'fraction', 'fragrance', 'frame', 'framework', 'fratricide', 'fraud', 'fraudster', 'freak', 'freckle', 'freedom', 'freelance', 'freezer', 'freezing', 'freight', 'freighter', 'frenzy', 'freon', 'frequency', 'fresco', 'friction', 'fridge', 'friend', 'friendship', 'frigate', 'fright', 'fringe', 'frock', 'frog', 'front', 'frontier', 'frost', 'frown', 'fruit', 'frustration', 'fry', 'fuel', 'fugato', 'fulfillment', 'full', 'fun', 'function', 'functionality', 'fund', 'funding', 'fundraising', 'funeral', 'fur', 'furnace', 'furniture', 'furry', 'fusarium', 'futon', 'future', 'gadget', 'gaffe', 'gaffer', 'gain', 'gaiters', 'gale', 'gall-bladder', 'gallery', 'galley', 'gallon', 'galoshes', 'gambling', 'game', 'gamebird', 'gaming', 'gamma-ray', 'gander', 'gang', 'gap', 'garage', 'garb', 'garbage', 'garden', 'garlic', 'garment', 'garter', 'gas', 'gasket', 'gasoline', 'gasp', 'gastropod', 'gate', 'gateway', 'gather', 'gathering', 'gator', 'gauge', 'gauntlet', 'gavel', 'gazebo', 'gazelle', 'gear', 'gearshift', 'geek', 'gel', 'gelding', 'gem', 'gemsbok', 'gender', 'gene', 'general', 'generation', 'generator', 'generosity', 'genetics', 'genie', 'genius', 'genocide', 'genre', 'gentleman', 'geography', 'geology', 'geometry', 'geranium', 'gerbil', 'gesture', 'geyser', 'gherkin', 'ghost', 'giant', 'gift', 'gig', 'gigantism', 'giggle', 'ginseng', 'giraffe', 'girdle', 'girl', 'girlfriend', 'git', 'glacier', 'gladiolus', 'glance', 'gland', 'glass', 'glasses', 'glee', 'glen', 'glider', 'gliding', 'glimpse', 'globe', 'glockenspiel', 'gloom', 'glory', 'glove', 'glow', 'glucose', 'glue', 'glut', 'glutamate', 'go-kart', 'goal', 'goat', 'gobbler', 'god', 'goddess', 'godfather', 'godmother', 'godparent', 'goggles', 'going', 'gold', 'goldfish', 'golf', 'gondola', 'gong', 'good', 'good-bye', 'goodbye', 'goodie', 'goodness', 'goodnight', 'goodwill', 'goose', 'gopher', 'gore-tex', 'gorilla', 'gosling', 'gossip', 'governance', 'government', 'governor', 'gown', 'grab-bag', 'grace', 'grade', 'gradient', 'graduate', 'graduation', 'graffiti', 'graft', 'grain', 'gram', 'grammar', 'gran', 'grand', 'grant', 'grape', 'grapefruit', 'graph', 'graphic', 'grasp', 'grass', 'grasshopper', 'grassland', 'gratitude', 'gravel', 'gravitas', 'gravity', 'gray', 'grease', 'greatness', 'greed', 'green', 'greenhouse', 'grenade', 'grey', 'grief', 'grill', 'grin', 'grip', 'gripper', 'grit', 'grocery', 'ground', 'group', 'grouper', 'grouse', 'growth', 'guarantee', 'guard', 'guerrilla', 'guess', 'guest', 'guestbook', 'guidance', 'guide', 'guideline', 'guilder', 'guilt', 'guilty', 'guitar', 'guitarist', 'gum', 'gumshoe', 'gun', 'gunpowder', 'gutter', 'guy', 'gym', 'gymnast', 'gymnastics', 'gynaecology', 'gyro', 'habit', 'habitat', 'hacienda', 'hacksaw', 'hackwork', 'hail', 'hair', 'haircut', 'half', 'half-brother', 'half-sister', 'halibut', 'hall', 'halloween', 'hallway', 'halt', 'hamburger', 'hammer', 'hammock', 'hamster', 'hand', 'hand-holding', 'handball', 'handful', 'handgun', 'handicap', 'handle', 'handlebar', 'handmaiden', 'handover', 'handrail', 'handsaw', 'happening', 'happiness', 'harald', 'harbor', 'harbour', 'hard-hat', 'hardboard', 'hardcover', 'hardening', 'hardhat', 'hardship', 'hardware', 'hare', 'harm', 'harmonica', 'harmonise', 'harmonize', 'harmony', 'harp', 'harpooner', 'harpsichord', 'harvest', 'harvester', 'hashtag', 'hassock', 'haste', 'hat', 'hatbox', 'hatchet', 'hate', 'hatred', 'haunt', 'haven', 'haversack', 'havoc', 'hawk', 'hay', 'haze', 'hazel', 'head', 'headache', 'headlight', 'headline', 'headquarters', 'headrest', 'health', 'health-care', 'hearing', 'hearsay', 'heart', 'heart-throb', 'heartache', 'heartbeat', 'hearth', 'hearthside', 'heartwood', 'heat', 'heater', 'heating', 'heaven', 'heavy', 'hectare', 'hedge', 'hedgehog', 'heel', 'height', 'heir', 'heirloom', 'helicopter', 'helium', 'hell', 'hellcat', 'hello', 'helmet', 'helo', 'help', 'hemisphere', 'hemp', 'hen', 'hepatitis', 'herb', 'heritage', 'hermit', 'hero', 'heroine', 'heron', 'herring', 'hesitation', 'heterosexual', 'hexagon', 'heyday', 'hiccups', 'hide', 'hierarchy', 'high', 'high-rise', 'highland', 'highlight', 'highway', 'hike', 'hiking', 'hill', 'hint', 'hip', 'hippodrome', 'hippopotamus', 'hire', 'hiring', 'historian', 'history', 'hit', 'hive', 'hobbit', 'hobby', 'hockey', 'hoe', 'hog', 'hold', 'holder', 'hole', 'holiday', 'home', 'homeland', 'homeownership', 'hometown', 'homework', 'homicide', 'homogenate', 'homonym', 'honesty', 'honey', 'honeybee', 'honor', 'honoree', 'hood', 'hoof', 'hook', 'hop', 'hope', 'hops', 'horde', 'horizon', 'hormone', 'horn', 'hornet', 'horror', 'horse', 'horst', 'hose', 'hosiery', 'hospice', 'hospital', 'hospitalization', 'hospitality', 'hospitalization', 'host', 'hostel', 'hostess', 'hotdog', 'hotel', 'hour', 'hourglass', 'house', 'houseboat', 'household', 'housewife', 'housework', 'housing', 'hovel', 'hovercraft', 'howard', 'howitzer', 'hub', 'hubcap', 'hubris', 'hug', 'hugger', 'hull', 'human', 'humanity', 'humidity', 'humor', 'humour', 'hunchback', 'hundred', 'hunger', 'hunt', 'hunter', 'hunting', 'hurdle', 'hurdler', 'hurricane', 'hurry', 'hurt', 'husband', 'hut', 'hutch', 'hyacinth', 'hybridisation', 'hybridization', 'hydrant', 'hydraulics', 'hydrocarb', 'hydrocarbon', 'hydrofoil', 'hydrogen', 'hydrolyse', 'hydrolysis', 'hydrolyze', 'hydroxyl', 'hyena', 'hygienic', 'hype', 'hyphenation', 'hypochondria', 'hypothermia', 'hypothesis', 'ice', 'ice-cream', 'icebreaker', 'icecream', 'icicle', 'icon', 'icy', 'id', 'idea', 'ideal', 'identification', 'identity', 'ideology', 'idiom', 'idiot', 'igloo',  'ikebana',  'illusion', 'illustration', 'image', 'imagination', 'imbalance', 'imitation', 'immigrant', 'immigration', 'immortal', 'impact', 'impairment', 'impediment', 'implement', 'implementation', 'implication', 'import', 'importance', 'impostor', 'impress', 'impression', 'imprisonment', 'impropriety', 'improvement', 'impudence', 'impulse', 'in-joke', 'in-laws', 'inability', 'inauguration', 'inbox', 'incandescence', 'incarnation', 'incense', 'incentive', 'inch', 'incidence', 'incident', 'incision', 'inclusion', 'income', 'incompetence', 'inconvenience', 'increase', 'incubation', 'independence', 'independent', 'index', 'indication', 'indicator', 'indigence', 'individual', 'industrialisation', 'industrialization', 'industry', 'inequality', 'inevitable', 'infancy', 'infant', 'infarction', 'infection', 'infiltration', 'infinite', 'infix', 'inflammation', 'inflation', 'influence', 'influx', 'info', 'information', 'infrastructure', 'infusion', 'inglenook', 'ingrate', 'ingredient', 'inhabitant', 'inheritance', 'inhibition', 'inhibitor', 'initial', 'initialise', 'initialize', 'initiative', 'injunction', 'injury', 'injustice', 'ink', 'inlay', 'inn', 'innervation', 'innocence', 'innocent', 'innovation', 'input', 'inquiry', 'inscription', 'insect', 'insert', 'inside', 'insight', 'insolence', 'insomnia', 'inspection', 'inspector', 'inspiration', 'installation', 'instance', 'instant', 'instinct', 'institute', 'institution', 'instruction', 'instructor', 'instrument', 'instrumentalist', 'instrumentation', 'insulation', 'insurance', 'insurgence', 'insurrection', 'integer', 'integral', 'integration', 'integrity', 'intellect', 'intelligence', 'intensity', 'intent', 'intention', 'intentionality', 'interaction', 'interchange', 'interconnection', 'intercourse', 'interest', 'interface', 'interferometer', 'interior', 'interject', 'interloper', 'internet', 'interpretation', 'interpreter', 'interval', 'intervenor', 'intervention', 'interview', 'interviewer', 'intestine', 'introduction', 'intuition', 'invader', 'invasion', 'invention', 'inventor', 'inventory', 'inverse', 'inversion', 'investigation', 'investigator', 'investment', 'investor', 'invitation', 'invite', 'invoice', 'involvement', 'iridescence', 'iris', 'iron', 'ironclad', 'irony', 'irrigation', 'ischemia', 'island', 'isogloss', 'isolation', 'issue', 'item', 'itinerary', 'ivory', 'jack', 'jackal', 'jacket', 'jade', 'jaguar', 'jail', 'jailhouse', 'jam', 'jar', 'jasmine', 'jaw', 'jazz', 'jealousy', 'jeans', 'jeep', 'jelly', 'jellyfish', 'jerk', 'jet', 'jewel', 'jeweller', 'jewellery', 'jewelry', 'jiffy', 'job', 'jockey', 'jodhpurs', 'joey', 'jogging', 'joint', 'joke', 'jot', 'journal', 'journalism', 'journalist', 'journey', 'joy', 'judge', 'judgment', 'judo', 'juggernaut', 'juice', 'jumbo', 'jump', 'jumper', 'jumpsuit', 'jungle', 'junior', 'junk', 'junker', 'junket', 'jury', 'justice', 'justification', 'jute', 'kale', 'kamikaze', 'kangaroo', 'karate', 'kayak', 'kazoo', 'keep', 'keeper', 'kendo', 'ketch', 'ketchup', 'kettle', 'kettledrum', 'key', 'keyboard', 'keyboarding', 'keystone', 'kick', 'kick-off', 'kid', 'kidney', 'kielbasa', 'kill', 'killer', 'killing', 'kilogram', 'kilometer', 'kilt', 'kimono', 'kinase', 'kind', 'kindness', 'king', 'kingdom', 'kingfish', 'kiosk', 'kiss', 'kit', 'kitchen', 'kite', 'kitsch', 'kitten', 'kitty', 'knee', 'kneejerk', 'knickers', 'knife', 'knife-edge', 'knight', 'knitting', 'knock', 'knot', 'know-how', 'knowledge', 'knuckle', 'koala', 'kohlrabi', 'lab', 'label', 'labor', 'laboratory', 'laborer', 'labour', 'labourer', 'lace', 'lack', 'lacquerware', 'lad', 'ladder', 'lady', 'ladybug', 'lag', 'lake', 'lamb', 'lament', 'lamp', 'lanai', 'land', 'landform', 'landing', 'landmine', 'landscape', 'lane', 'language', 'lantern', 'lap', 'laparoscope', 'lapdog', 'laptop', 'larch', 'larder', 'lark', 'larva', 'laryngitis', 'lasagna', 'lashes', 'last', 'latency', 'latex', 'lathe', 'latitude', 'latte', 'latter', 'laugh', 'laughter', 'laundry', 'lava', 'law', 'lawmaker', 'lawn', 'lawsuit', 'lawyer', 'lay', 'layer', 'layout', 'lead', 'leader', 'leadership', 'leading', 'leaf', 'league', 'leaker', 'leap', 'learning', 'leash', 'leather', 'leave', 'leaver', 'lecture', 'leek', 'leeway', 'left', 'leg', 'legacy', 'legal', 'legend', 'legging', 'legislation', 'legislator', 'legislature', 'legitimacy', 'legume', 'leisure', 'lemon', 'lemonade', 'lemur', 'lender', 'lending', 'length', 'lens', 'lentil', 'leopard', 'leprosy', 'lesson', 'letter', 'lettuce', 'level', 'lever', 'leverage', 'liability', 'liar', 'liberty', 'libido', 'library', 'license', 'licensing', 'lid', 'lie', 'lieu', 'lieutenant', 'life', 'lifestyle', 'lifetime', 'lift', 'ligand', 'light', 'lighting', 'lightning', 'lightscreen', 'ligula', 'likelihood', 'likeness', 'lilac', 'lily', 'limb', 'limestone', 'limit', 'limitation', 'limo', 'line', 'linen', 'liner', 'linguist', 'linguistics', 'lining', 'link', 'linkage', 'linseed', 'lion', 'lip', 'lipid', 'lipoprotein', 'lipstick', 'liquid', 'liquidity', 'liquor', 'list', 'listening', 'listing', 'literate', 'literature', 'litigation', 'litmus', 'litter', 'liver', 'livestock', 'living', 'lizard', 'llama', 'load', 'loading', 'loaf', 'loafer', 'loan', 'lobby', 'lobotomy', 'lobster', 'local', 'locality', 'location', 'lock', 'locker', 'locket', 'locomotive', 'locust', 'loft', 'log', 'loggia', 'logic', 'login', 'logistics', 'logo', 'loincloth', 'loneliness', 'longboat', 'longitude', 'look', 'lookout', 'loop', 'loophole', 'lord', 'loss', 'lot', 'lotion', 'lottery', 'lounge', 'lout', 'love', 'lover', 'loyalty', 'luck', 'luggage', 'lumber', 'lumberman', 'lunch', 'luncheonette', 'lunchroom', 'lung', 'lunge', 'lust', 'lute', 'luxury', 'lycra', 'lye', 'lymphocyte', 'lynx', 'lyocell', 'lyre', 'lyrics', 'lysine', 'macadamia', 'macaroni', 'machine', 'machinery', 'macrame', 'macro', 'macrofauna', 'madam', 'maelstrom', 'maestro', 'magazine', 'magic', 'magnet', 'magnitude', 'maid', 'maiden', 'mail', 'mailbox', 'mailer', 'mailing', 'mailman', 'main', 'mainland', 'mainstream', 'maintenance', 'major', 'major-league', 'majority', 'makeover', 'ruler', 'ruling', 'rum', 'rumor', 'run', 'runaway', 'runner', 'running', 'runway', 'rush', 'rust', 'rutabaga', 'rye', 'sabre', 'sac', 'sack', 'saddle', 'sadness', 'safari', 'safe', 'safeguard', 'safety', 'sage', 'sail', 'sailboat', 'sailing', 'sailor', 'saint', 'sake', 'salad', 'salary', 'sale', 'salesman', 'salmon', 'salon', 'saloon', 'salt', 'salute', 'samovar', 'sampan', 'sample', 'samurai', 'sanction', 'sanctity', 'sanctuary', 'sand', 'sandal', 'sandbar', 'sandwich', 'sanity', 'sardine', 'sari', 'sarong', 'sash', 'satellite', 'satin', 'satire', 'satisfaction', 'sauce', 'saucer', 'sausage', 'savage', 'saving', 'savings', 'savior', 'saviour', 'saw', 'saxophone', 'scaffold', 'scale', 'scallion', 'scalp', 'scam', 'scanner', 'scarecrow', 'scarf', 'scarification', 'scenario', 'scene', 'scenery', 'scent', 'schedule', 'scheduling', 'schema', 'scheme', 'schizophrenic', 'schnitzel', 'scholar', 'scholarship', 'school', 'schoolhouse', 'schooner', 'science', 'scientist', 'scimitar', 'scissors', 'scooter', 'scope', 'score', 'scorn', 'scout', 'scow', 'scrap', 'scraper', 'scratch', 'screamer', 'screen', 'screening', 'screenwriting', 'screw', 'screw-up', 'screwdriver', 'scrim', 'scrip', 'script', 'scripture', 'scrutiny', 'sculpting', 'sculptural', 'sculpture', 'sea', 'seabass', 'seafood', 'seagull', 'seal', 'seaplane', 'search', 'seashore', 'seaside', 'season', 'seat', 'second', 'secrecy', 'secret', 'secretariat', 'secretary', 'secretion', 'section', 'sectional', 'sector', 'security', 'sediment', 'seed', 'seeder', 'seeker', 'seep', 'segment', 'seizure', 'selection', 'self', 'self-confidence', 'self-control', 'self-esteem', 'seller', 'selling', 'semantics', 'semester', 'semicircle', 'semicolon', 'semiconductor', 'seminar', 'senate', 'senator', 'sender', 'senior', 'sense', 'sensibility', 'sensitive', 'sensitivity', 'sensor', 'sentence', 'sentencing', 'sentiment', 'sepal', 'separation', 'septicaemia', 'sequel', 'sequence', 'serial', 'series', 'sermon', 'serum', 'servant', 'server', 'service', 'servitude', 'session', 'set', 'setback', 'setting', 'settlement', 'settler', 'severity', 'sewer', 'shack', 'shackle', 'shade', 'shadow', 'shadowbox', 'shakedown', 'shaker', 'shallot', 'shallows', 'shame', 'shampoo', 'shanty', 'shape', 'share', 'shareholder', 'shark', 'shaw', 'shawl', 'shear', 'shearling', 'sheath', 'shed', 'sheep', 'sheet', 'shelf', 'shell', 'shelter', 'sherry', 'shield', 'shift', 'shin', 'shine', 'shingle', 'ship', 'shipper', 'shipping', 'shipyard', 'shirt', 'shirtdress', 'shoat', 'shock', 'shoe', 'shoe-horn', 'shoehorn', 'shoelace', 'shoemaker', 'shoestring', 'shofar', 'shoot', 'shootdown', 'shop', 'shopper', 'shopping', 'shore', 'shoreline', 'short', 'shortage', 'shorts', 'shortwave', 'shot', 'shoulder', 'shout', 'shovel', 'show', 'show-stopper', 'shower', 'shred', 'shrimp', 'shrine', 'shutdown', 'sibling', 'sick', 'sickness', 'side', 'sideboard', 'sideburns', 'sidecar', 'sidestream', 'sidewalk', 'siding', 'siege', 'sigh', 'sight', 'sightseeing', 'sign', 'signal', 'signature', 'signet', 'significance', 'signify', 'signup', 'silence', 'silica', 'silicon', 'silk', 'silkworm', 'sill', 'silly', 'silo', 'silver', 'similarity', 'simple', 'simplicity', 'simvastatin', 'sin', 'singer', 'singing', 'singular', 'sink', 'sinuosity', 'sip', 'sir', 'sister', 'sister-in-law', 'sitar', 'site', 'situation', 'size', 'skate', 'skating', 'skean', 'skeleton', 'ski', 'skiing', 'skill', 'skin', 'skirt', 'skull', 'skullcap', 'skullduggery', 'skunk', 'sky', 'skylight', 'skyline', 'skyscraper', 'skywalk', 'slang', 'slapstick', 'slash', 'slate', 'slave', 'slavery', 'sled', 'sledge', 'sleep', 'sleepiness', 'sleeping', 'sleet', 'sleuth', 'slice', 'slide', 'slider', 'slime', 'slip', 'slipper', 'slippers', 'slope', 'slot', 'sloth', 'slump', 'smell', 'smelting', 'smile', 'smith', 'smock', 'smog', 'smoke', 'smoking', 'smuggling', 'snack', 'snail', 'snake', 'snakebite', 'snap', 'snarl', 'sneaker', 'sneakers', 'sneeze', 'sniffle', 'snob', 'snorer', 'snow', 'snowboarding', 'snowflake', 'snowman', 'snowmobiling', 'snowplow', 'snowstorm', 'snowsuit', 'snuck', 'snug', 'snuggle', 'soap', 'soccer', 'socialism', 'socialist', 'society', 'sociology', 'sock', 'socks', 'soda', 'sofa', 'softball', 'softdrink', 'softening', 'software', 'soil', 'soldier', 'solicitation', 'solicitor', 'solidarity', 'solidity', 'soliloquy', 'solitaire', 'solution', 'solvency', 'sombrero', 'somebody', 'someone', 'someplace', 'somersault', 'something', 'somewhere', 'son', 'sonar', 'sonata', 'song', 'songbird', 'sonnet', 'soot', 'sophomore', 'soprano', 'sorbet', 'sorrow', 'sort', 'soul', 'soulmate', 'sound', 'soundness', 'soup', 'source', 'sourwood', 'sousaphone', 'south', 'southeast', 'souvenir', 'sovereignty', 'sow', 'soy', 'soybean', 'space', 'spacing', 'spade', 'spaghetti', 'span', 'spandex', 'spank', 'spark', 'sparrow', 'spasm', 'speaker', 'speakerphone', 'speaking', 'spear', 'spec', 'special', 'specialist', 'specialty', 'species', 'specification', 'spectacle', 'spectacles', 'spectrograph', 'spectrum', 'speculation', 'speech', 'speed', 'speedboat', 'spell', 'spelling', 'spelt', 'spending', 'sphere', 'sphynx', 'spice', 'spider', 'spike', 'spill', 'spinach', 'spine', 'spiral', 'spirit', 'spiritual', 'spirituality', 'spit', 'spite', 'spleen', 'splendor', 'split', 'spokesman', 'spokeswoman', 'sponge', 'sponsor', 'sponsorship', 'spool', 'spoon', 'sport', 'sportsman', 'spot', 'spotlight', 'spouse', 'spray', 'spread', 'spreadsheet', 'spree', 'spring', 'sprinter', 'sprout', 'spruce', 'spume', 'spur', 'spy', 'spyglass', 'square', 'squash', 'squatter', 'squeegee', 'squid', 'squirrel', 'stab', 'stability', 'stable', 'stack', 'stacking', 'stadium', 'staff', 'stag', 'stage', 'stain', 'stair', 'staircase', 'stake', 'stalk', 'stall', 'stallion', 'stamen', 'stamina', 'stamp', 'stance', 'stand', 'standard', 'standardisation', 'standardization', 'standing', 'standoff', 'standpoint', 'star', 'starboard', 'start', 'starter', 'state', 'statement', 'statin', 'station', 'station-wagon', 'statistic', 'statistics', 'statue', 'status', 'statute', 'stay', 'steak', 'stealth', 'steam', 'steamroller', 'steel', 'steeple', 'stem', 'stench', 'stencil', 'step', 'stepping-stone', 'stereo', 'stew', 'steward', 'stick', 'sticker', 'stiletto', 'still', 'stimulation', 'stimulus', 'sting', 'stinger', 'stitch', 'stitcher', 'stock', 'stock-in-trade', 'stockings', 'stole', 'stomach', 'stone', 'stonework', 'stool', 'stop', 'stopsign', 'stopwatch', 'storage', 'store', 'storey', 'storm', 'story', 'story-telling', 'storyboard', 'stove', 'strait', 'strand', 'stranger', 'strap', 'strategy', 'straw', 'strawberry', 'strawman', 'stream', 'street', 'streetcar', 'strength', 'stress', 'stretch', 'strife', 'strike', 'string', 'strip', 'stripe', 'strobe', 'stroke', 'structure', 'struggle', 'stucco', 'stud', 'student', 'studio', 'study', 'stuff', 'stumbling', 'stump', 'stupidity', 'sturgeon', 'style', 'styling', 'stylus', 'sub', 'subcomponent', 'subconscious', 'subcontractor', 'subexpression', 'subgroup', 'subject', 'submarine', 'subprime', 'subroutine', 'subscription', 'subsection', 'subset', 'subsidence', 'subsidiary', 'subsidy', 'substance', 'substitution', 'subtitle', 'suburb', 'subway', 'success', 'suck', 'sucker', 'suede', 'suffocation', 'sugar', 'suggestion', 'suicide', 'suit', 'suitcase', 'suite', 'sulfur', 'sultan', 'sum', 'summary', 'summer', 'summit', 'sun', 'sunbeam', 'sunbonnet', 'sunday', 'sundial', 'sunflower', 'sunglasses', 'sunlamp', 'sunlight', 'sunrise', 'sunroom', 'sunset', 'sunshine', 'superiority', 'supermarket', 'supernatural', 'supervision', 'supervisor', 'supplement', 'supplier', 'supply', 'support', 'supporter', 'suppression', 'supreme', 'surface', 'surfboard', 'surge', 'surgeon', 'surgery', 'surname', 'surplus', 'surprise', 'surround', 'surroundings', 'surrounds', 'survey', 'survival', 'survivor', 'sushi', 'suspect', 'suspenders', 'suspension', 'sustainment', 'SUV', 'swallow', 'swamp', 'swan', 'swath', 'sweat', 'sweater', 'sweatshirt', 'sweatshop', 'sweatsuit', 'sweets', 'swell', 'swim', 'swimming', 'swimsuit', 'swing', 'switch', 'switchboard', 'switching', 'swivel', 'sword', 'swordfight', 'swordfish', 'sycamore', 'sydney', 'symbol', 'symmetry', 'sympathy', 'symptom', 'syndicate', 'syndrome', 'synergy', 'synod', 'synonym', 'synthesis', 'syrup', 'system', 't-shirt', 'tab', 'tabby', 'tabernacle', 'table', 'tablecloth', 'tablet', 'tabletop', 'tachometer', 'tackle', 'tactics', 'tactile', 'tadpole', 'tag', 'tail', 'tailbud', 'tailor', 'tailspin', 'takeover', 'tale', 'talent', 'talk', 'talking', 'tambour', 'tambourine', 'tan', 'tandem', 'tangerine', 'tank', 'tank-top', 'tanker', 'tankful', 'tap', 'tape', 'target', 'task', 'tassel', 'taste', 'tatami', 'tattler', 'tattoo', 'tavern', 'tax', 'taxi', 'taxicab', 'taxpayer', 'tea', 'teacher', 'teaching', 'team', 'teammate', 'tear', 'tech', 'technician', 'technique', 'technologist', 'technology', 'tectonics', 'teen', 'teenager', 'teepee', 'telephone', 'telescreen', 'teletype', 'television', 'tell', 'teller', 'temp', 'temper', 'temperature', 'temple', 'tempo', 'temporariness', 'temporary', 'temptation', 'temptress', 'tenant', 'tendency', 'tender', 'tenement', 'tenet', 'tennis', 'tenor', 'tension', 'tensor', 'tent', 'tentacle', 'tenth', 'tepee', 'term', 'terminal', 'termination', 'terminology', 'terrace', 'terracotta', 'terrapin', 'territory', 'terror', 'terrorism', 'terrorist', 'test', 'testament', 'testimonial', 'testimony', 'testing', 'text', 'textbook', 'textual', 'texture', 'thanks', 'thaw', 'theater', 'theft', 'theism', 'theme', 'theology', 'theory', 'therapist', 'therapy', 'thermals', 'thermometer', 'thesis', 'thickness', 'thief', 'thigh', 'thing', 'thinking', 'thirst', 'thistle', 'thong', 'thongs', 'thorn', 'thought', 'thousand', 'thread', 'threat', 'threshold', 'thrift', 'thrill', 'throat', 'thromboxane', 'throne', 'thrush', 'thrust', 'thug', 'thumb', 'thump', 'thunder', 'thunderbolt', 'thunderhead', 'thunderstorm', 'thyme', 'tiara', 'tic', 'ticket', 'tide', 'tie', 'tiger', 'tights', 'tile', 'till', 'tilt', 'timbale', 'timber', 'time', 'timeline', 'timeout', 'timer', 'timetable', 'timing', 'timpani', 'tin', 'tinderbox', 'tinkle', 'tintype', 'tip', 'tire', 'tissue', 'titanium', 'title', 'toad', 'toast', 'tobacco', 'today', 'toe', 'toenail', 'tog', 'toga', 'toilet', 'tolerance', 'tolerant', 'toll', 'tom-tom', 'tomato', 'tomb', 'tomography', 'tomorrow', 'ton', 'tonality', 'tone', 'tongue', 'tonic', 'tonight', 'tool', 'toot', 'tooth', 'toothbrush', 'toothpaste', 'toothpick', 'top', 'top-hat', 'topic', 'topsail', 'toque', 'toreador', 'tornado', 'torso', 'tortellini', 'tortoise', 'tosser', 'total', 'tote', 'touch', 'tough-guy', 'tour', 'tourism', 'tourist', 'tournament', 'tow-truck', 'towel', 'tower', 'town', 'townhouse', 'township', 'toy', 'trace', 'trachoma', 'track', 'tracking', 'tracksuit', 'tract', 'tractor', 'trade', 'trader', 'trading', 'tradition', 'traditionalism', 'traffic', 'trafficker', 'tragedy', 'trail', 'trailer', 'trailpatrol', 'train', 'trainer', 'training', 'trait', 'tram', 'tramp', 'trance', 'transaction', 'transcript', 'transfer', 'transformation', 'transit', 'transition', 'translation', 'transmission', 'transom', 'transparency', 'transplantation', 'transport', 'transportation', 'trap', 'trapdoor', 'trapezium', 'trapezoid', 'trash', 'travel', 'traveler', 'tray', 'treasure', 'treasury', 'treat', 'treatment', 'treaty', 'tree', 'trek', 'trellis', 'tremor', 'trench', 'trend', 'triad', 'trial', 'triangle', 'tribe', 'tributary', 'trick', 'trigger', 'trigonometry', 'trillion', 'trim', 'trinket', 'trip', 'tripod', 'tritone', 'triumph', 'trolley', 'trombone', 'troop', 'trooper', 'trophy', 'trouble', 'trousers', 'trout', 'trove', 'trowel', 'truck', 'trumpet', 'trunk', 'trust', 'trustee', 'truth', 'try', 'tsunami', 'tub', 'tuba', 'tube', 'tug', 'tugboat', 'tuition', 'tulip', 'tummy', 'tuna', 'tune', 'tune-up', 'tunic', 'tunnel', 'turban', 'turf', 'turkey', 'turn', 'turning', 'turnip', 'turnover', 'turnstile', 'turret', 'turtle', 'tusk', 'tussle', 'tutu', 'tuxedo', 'TV', 'tweet', 'twig', 'twilight', 'twine', 'twins', 'twist', 'twister', 'twitter', 'type', 'typeface', 'typewriter', 'typhoon', 'ukulele', 'ultimatum', 'umbrella', 'unblinking', 'uncertainty', 'uncle', 'underclothes', 'underestimate', 'underground', 'underneath', 'underpants', 'underpass', 'undershirt', 'understanding', 'understatement', 'undertaker', 'underwear', 'underweight', 'underwire', 'underwriting', 'unemployment', 'unibody', 'uniform', 'uniformity', 'union', 'unique', 'unit', 'unity', 'universe', 'university', 'update', 'upgrade', 'uplift', 'upper', 'upstairs', 'upward', 'urge', 'urgency', 'urn', 'usage', 'use', 'user', 'usher', 'usual', 'utensil', 'utilisation', 'utility', 'utilization', 'vacation', 'vaccine', 'vacuum', 'vagrant', 'valance', 'valentine', 'validate', 'validity', 'valley', 'valuable', 'value', 'vampire', 'van', 'vanadyl', 'vane', 'vanity', 'variability', 'variable', 'variant', 'variation', 'variety', 'vascular', 'vase', 'vault', 'vaulting', 'veal', 'vector', 'vegetable', 'vegetarian', 'vegetarianism', 'vegetation', 'vehicle', 'veil', 'vein', 'veldt', 'vellum', 'velocity', 'velodrome', 'velvet', 'vendor', 'veneer', 'vengeance', 'venom', 'venti', 'venture', 'venue', 'veranda', 'verb', 'verdict', 'verification', 'vermicelli', 'vernacular', 'verse', 'version', 'vertigo', 'verve', 'vessel', 'vest', 'vestment', 'vet', 'veteran', 'veterinarian', 'veto', 'viability', 'vibe', 'vibraphone', 'vibration', 'vibrissae', 'vice', 'vicinity', 'victim', 'victory', 'video', 'view', 'viewer', 'villa', 'village', 'vine', 'vineyard', 'vintage', 'vintner', 'vinyl', 'viola', 'violation', 'violence', 'violet', 'violin', 'virginal', 'virtue', 'virus', 'visa', 'viscose', 'vise', 'vision', 'visit', 'visitor', 'visor', 'vista', 'visual', 'vitality', 'vitro', 'vivo', 'vixen', 'vodka', 'vogue', 'voice', 'void', 'vol', 'volatility', 'volcano', 'volleyball', 'volume', 'volunteer', 'volunteering', 'vomit', 'vote', 'voter', 'voting', 'voyage', 'vulture', 'wad', 'wafer', 'waffle', 'wage', 'wagon', 'waist', 'waistband', 'wait', 'waiter', 'waiting', 'waitress', 'waiver', 'wake', 'walk', 'walker', 'walking', 'walkway', 'wall', 'wallaby', 'wallet', 'walnut', 'walrus', 'wampum', 'wannabe', 'want', 'war', 'warden', 'wardrobe', 'warfare', 'warlock', 'warlord', 'warm-up', 'warming', 'warmth', 'warning', 'warrant', 'warrior', 'wash', 'washbasin', 'washcloth', 'washer', 'washtub', 'wasp', 'waste', 'wastebasket', 'wasting', 'watch', 'watcher', 'watchmaker', 'water', 'waterbed', 'waterfall', 'waterfront', 'waterskiing', 'waterspout', 'waterwheel', 'wave', 'waveform', 'wax', 'way', 'weakness', 'wealth', 'weapon', 'wear', 'weasel', 'weather', 'web', 'webinar', 'webmail', 'webpage', 'website', 'wedding', 'wedge', 'weed', 'weeder', 'weedkiller', 'week', 'weekend', 'weekender', 'weight', 'weird', 'welcome', 'welfare', 'well', 'well-being', 'west', 'western', 'wet-bar', 'wetland', 'wetsuit', 'whack', 'whale', 'wharf', 'wheat', 'wheel', 'whip', 'whirlpool', 'whirlwind', 'whisker', 'whiskey', 'whisper', 'whistle', 'white', 'whole', 'wholesale', 'wholesaler', 'whorl', 'wick', 'widget', 'widow', 'width', 'wife', 'wifi', 'wilderness', 'wildlife', 'will', 'willingness', 'willow', 'win', 'wind', 'wind-chime', 'windage', 'window', 'windscreen', 'windshield', 'wine', 'winery', 'wing', 'wingman', 'wingtip', 'wink', 'winner', 'winter', 'wire', 'wiretap', 'wiring', 'wisdom', 'wiseguy', 'wish', 'wisteria', 'wit', 'witch', 'witch-hunt', 'withdrawal', 'witness', 'wolf', 'woman', 'wombat', 'wonder', 'wont', 'wood', 'woodland', 'woodshed', 'woodwind', 'wool', 'woolens', 'word', 'wording', 'work', 'workbench', 'worker', 'workforce', 'workhorse', 'working', 'workout', 'workplace', 'workshop', 'world', 'worm', 'worry', 'worth', 'wound', 'wrap', 'wraparound', 'wrapping', 'wreck', 'wrecker', 'wren', 'wrench', 'wrestler', 'wrinkle', 'wrist', 'writer', 'writing', 'wrong', 'xylophone', 'yacht', 'yahoo', 'yak', 'yam', 'yang', 'yard', 'yarn', 'yawl', 'year', 'yeast', 'yellow', 'yesterday', 'yew', 'yin', 'yoga', 'yogurt', 'yoke', 'young', 'youngster', 'yourself', 'youth', 'yoyo', 'yurt', 'zampone', 'zebra', 'zebrafish', 'zen', 'zephyr', 'zero', 'ziggurat', 'zinc', 'zipper', 'zither', 'zombie', 'zone', 'zoo', 'zoologist', 'zoology', 'zoot-suit', 'zucchini']
adverbs = ['abnormally', 'abruptly', 'absently', 'accidentally', 'accusingly', 'actually', 'adventurously', 'adversely', 'almost', 'always', 'amazingly', 'angrily', 'anxiously', 'arrogantly', 'awkwardly', 'aback', 'abandonedly', 'abashedly', 'abeam', 'abhorrently', 'abidingly', 'abloom', 'ably', 'aboard', 'abominably', 'aboriginally', 'about', 'above', 'abroad', 'absentmindedly', 'absolutely', 'absorbedly', 'abstractedly', 'abstractly', 'absurdly', 'abundantly', 'aburst', 'academically', 'accentually', 'accessibly', 'accessorily', 'accordingly', 'alarmedly', 'accountably', 'accurately', 'accusatively', 'acoustically', 'acquisitively', 'accusatorially', 'acrimoniously', 'across', 'acrostically', 'actively', 'acutely', 'adaptly', 'additionally', 'adequately', 'adhesively', 'adjacently', 'adjectively', 'adjunctly', 'admirably', 'admittedly', 'adorably', 'adoringly', 'adverbially', 'advisably', 'affectedly', 'afresh', 'after', 'again', 'agonizingly', 'agreeably', 'aggravatingly', 'all', 'along', 'already', 'also', 'afterward', 'aggressively', 'ago', 'ahead', 'alike', 'allegedly', 'alone', 'aloud', 'alright', 'alternatively', 'altogether', 'annually', 'anyhow', 'anymore', 'anyway', 'anywhere', 'apart', 'apparently', 'appropriately', 'approximately', 'arguably', 'ashore', 'aside', 'astray', 'automatically', 'away', 'awhile', 'amblingly', 'amorously', 'amply', 'analogically', 'analytically', 'anatomically', 'ancestrally', 'anciently', 'angelically', 'angularly', 'animatedly', 'any', 'aptly', 'astonishedly', 'astonishingly', 'astringently', 'asunder', 'atmostphereically', 'atomically', 'attributively', 'audaciously', 'audibly', 'authentically', 'auxiliarly', 'aversely', 'awfully', 'axially', 'badly', 'bashfully', 'beautifully', 'bitterly', 'bleakly', 'blindly', 'blissfully', 'boldly', 'bravely', 'briefly', 'brightly', 'briskly', 'broadly', 'busily', 'babyishly', 'back', 'backstage', 'backward', 'backwardly', 'bacterially', 'baldly', 'balmily', 'bang', 'barbarously', 'bareback', 'barely', 'barometrically', 'basely', 'basically', 'beamingly', 'becomingly', 'befittingly', 'before', 'beforehand', 'behaviorally', 'belatedly', 'boringly', 'botanically', 'beggarly', 'behind', 'being', 'belligerently', 'believably', 'below', 'beneath', 'beneficially', 'benignly', 'besides', 'best', 'better', 'beyond', 'bias', 'biblically', 'biologically', 'biennially', 'bihourly', 'bilaterally', 'billowingly', 'bimonthly', 'bindingly', 'binocularly', 'bitingly', 'biweekly', 'black', 'blamelessly', 'blandly', 'begrudgingly', 'bi-monthly', 'bizarrely', 'landly', 'blankly', 'blatantly', 'blazingly', 'blessedly', 'blindingly', 'blisteringly', 'blithely', 'bluntly', 'brazenly', 'breathlessly', 'breathtakingly', 'brilliantly', 'brutally', 'blasphemously', 'bloody', 'blooming', 'bluely', 'blushingly', 'boastfully', 'boastingly', 'bodily', 'boiling', 'boilingly', 'boisterously', 'bonnily', 'bouncingly', 'boyishly', 'brag', 'braggingly', 'brief', 'bright', 'broadcast', 'brokenly', 'brotherly', 'bulkily', 'burdensomely', 'burning', 'buzzingly', 'by', 'calmly', 'carefully', 'carelessly', 'cautiously', 'certainly', 'cheerfully', 'clearly', 'cleverly', 'closely', 'coaxingly', 'commonly', 'continually', 'coolly', 'correctly', 'courageously', 'crossly', 'cruelly', 'curiously', 'calmingly', 'candidly', 'candescently', 'cankeredly', 'cantankerously', 'cannily', 'capably', 'capitally', 'capaciously', 'captivatingly', 'caringly', 'carnally', 'carousingly', 'cartographically', 'casually', 'catechetically', 'categorically', 'catholicly', 'causally', 'causeless', 'caustically', 'cavalierly', 'celestially', 'centennially', 'centrally', 'cerebrally', 'ceremonially', 'ceremoniously', 'certain', 'chance', 'chanceably', 'changeably', 'chaotically', 'characteristically', 'charitably', 'charmingly', 'chastely', 'cheap', 'cheaply', 'cheerily', 'cheeringly', 'cheerly', 'chemically', 'chiefly', 'childishly', 'childly', 'chirpingly', 'chivalrously', 'choicely', 'chorally', 'christianly', 'chromatically', 'churlishly', 'circularly', 'classically', 'cleanly', 'clinically', 'clockwise', 'coincidentally', 'collectively', 'comfortably', 'comparatively', 'competitively', 'completely', 'comprehensively', 'conceivably', 'conclusively', 'concurrently', 'confidently', 'consciously', 'consecutively', 'consequently', 'conservatively', 'considerably', 'consistently', 'conspicuously', 'constantly', 'continuously', 'conveniently', 'conversely', 'convincingly', 'correspondingly', 'creatively', 'criminally', 'critically', 'crucially', 'currently', 'clammily', 'clancularly', 'clashingly', 'clairvoyantly', 'clemently', 'clatteringly', 'cleanlily', 'clear', 'cloudily', 'clumsily', 'clusteringly', 'coarsely', 'cogently', 'coequally', 'cognizably', 'coherently', 'colorfully', 'coincidently', 'cold', 'coldly', 'collect', 'collectedly', 'comely', 'comically', 'commandingly', 'commercially', 'compactedly', 'comparably', 'compassionately', 'competently', 'complacently', 'compliantly', 'conscientiously', 'considerately', 'craftily', 'crazily', 'credibly', 'credulously', 'creepingly', 'crescendo', 'cretaceously', 'crisply', 'crookedly', 'crudely', 'cryptically', 'culinarily', 'culturally', 'cunningly', 'curtly', 'customarily', 'cynically', 'daily', 'daintily', 'daringly', 'dearly', 'deceivingly', 'deeply', 'deliberately', 'delightfully', 'desperately', 'determinedly', 'diligently', 'doubtfully', 'dreamily', 'dynamically', 'dyingly', 'dutifully', 'duskily', 'durably', 'duly', 'dully', 'dubiously', 'dryly', 'drunkenly', 'drudgingly', 'drowsily', 'droppingly', 'dropigly', 'drearily', 'dreamingly', 'dreadingly', 'dreadfully', 'dramatically', 'downward', 'downstream', 'downstairs', 'downright', 'downhill', 'down', 'doubtless', 'doubly', 'double', 'dorsally', 'domestically', 'dogmatically', 'doctrinally', 'doctorally', 'disrespectfully', 'dishonestly', 'discreetly', 'discourteously', 'discouragingly', 'discontentedly', 'disbelievingly', 'disarmingly', 'disapprovingly', 'disagreeably', 'dirty', 'dirtily', 'directly', 'direct', 'diplomatically', 'dingily', 'dimply', 'digressively', 'differingly', 'differently', 'differentially', 'diatonically', 'diametrically', 'dialectically', 'diagonally', 'detestably', 'destructively', 'despondently', 'despairingly', 'deservedly', 'depressingly', 'deprecatingly', 'dependably', 'demonstratively', 'demissily', 'demandingly', 'deliriously', 'delightedly', 'deliciously', 'delicately', 'delectably', 'delayingly', 'dejectedly', 'degradingly', 'degenerately', 'defly', 'definitively', 'definitely', 'deferentially', 'defensively', 'deep', 'deductively', 'deducibly', 'dedicatedly', 'decussately', 'decretorily', 'decreasingly', 'decorously', 'decoratively', 'declaratively', 'decimally', 'decieiveably', 'decidedly', 'deceitfully', 'debonairly', 'debauchedly', 'debatingly', 'debatefully', 'deaththy', 'dear', 'deafly', 'deadly', 'dead', 'dazzlingly', 'dashingly', 'dartingly', 'darkly', 'dangerously', 'dancingly', 'damply', 'damnably', 'daftly', 'dabbingly', 'eagerly', 'easily', 'elegantly', 'energetically', 'enormously', 'equally', 'especially', 'even', 'eventually', 'exactly', 'excitedly', 'extremely', 'extraordinarily', 'extensively', 'exquisitely', 'expressly', 'expressively', 'explicitly', 'expertly', 'expectantly', 'expansively', 'exclusively', 'excessively', 'exceptionally', 'excellently', 'exceedingly', 'exasperatingly', 'exaggeratedly', 'evidently', 'evidentally', 'everywhere', 'evermore', 'ever', 'evenly', 'evasively', 'euphorically', 'ethically', 'eternally', 'estimably', 'essentially', 'esoterically', 'erroneously', 'erratically', 'erotically', 'ergonomically', 'erectly', 'equivocally', 'equivalently', 'equitably', 'episcopally', 'epidemically', 'epicurely', 'environmentally', 'enviously', 'entirely', 'enticingly', 'enthusiastically', 'enthrallingly', 'entertainingly', 'enterprisingly', 'enquiringly', 'enough', 'enjoyably', 'engagingly', 'engagedly', 'endwise', 'endways', 'enduringly', 'endurably', 'endlessly', 'endearingly', 'endearedly', 'encroachingly', 'encouragingly', 'enchantingly', 'emptily', 'emphatically', 'empathetically', 'emotionlessly', 'emotionally', 'eminently', 'embitteredly', 'embarrassedly', 'elvishly', 'elusively', 'elsewise', 'elsewhere', 'else', 'eloquently', 'elliptically', 'elfishly', 'elementally', 'electronically', 'electrically', 'electively', 'elatedly', 'elastically', 'either', 'eighthly', 'egregiously', 'egotistically', 'eft', 'effortlessly', 'efficiently', 'efficaciously', 'effervescently', 'effectuously', 'effectually', 'effectively', 'eerily', 'educationally', 'editorially', 'edgingly', 'edgewise', 'edgeways', 'ecstatically', 'economically', 'eclectically', 'ecclesiastically', 'eccentrically', 'easy', 'eastwards', 'eastwardly', 'eastward', 'easterly', 'east', 'earthwards', 'earthward', 'earthly', 'earsplittingly', 'earnestly', 'early', 'eachwhere', 'each', 'fairly', 'famously', 'far', 'fast', 'fatally', 'ferociously', 'fervently', 'fiercely', 'fondly', 'foolishly', 'fortunately', 'frankly', 'frantically', 'freely', 'frightfully', 'fully', 'furiously', 'fussily', 'furtively', 'furthest', 'furthermore', 'further', 'fundamentally', 'functionally', 'fumingly', 'fumblingly', 'fulsomely', 'full', 'frustratedly', 'frumpishly', 'frumpily', 'fruitlessly', 'fruitfully', 'frugally', 'frozenly', 'frowningly', 'frothily', 'frostily', 'frontwards', 'frontally', 'frolicsomely', 'frolicly', 'frivolously', 'friskily', 'frigidly', 'frightenedly', 'friendly', 'friday', 'fretful', 'freshly', 'fresh', 'frequently', 'freezingly', 'free', 'freakishly', 'fraudulently', 'fragrantly', 'fragilely', 'fractiously', 'fractionally', 'foxily', 'fourthly', 'fourfold', 'forward', 'fortnightly', 'forthwith', 'forth', 'formidably', 'formerly', 'formally', 'forlornly', 'forgetfully', 'forever', 'forebodigly', 'forcibly', 'forcefully', 'forbiddenly', 'focally', 'foamingly', 'fluidly', 'fluffily', 'fluently', 'florally', 'floatingly', 'flittingly', 'flirtatiously', 'flimsily', 'fleetly', 'fleetingly', 'flawlessly', 'flauntingly', 'flatteringly', 'flatly', 'flat', 'flashingly', 'flashily', 'flaringly', 'flamingly', 'flakily', 'flagrantly', 'fixedly', 'fixatedly', 'fivefold', 'fittingly', 'fitly', 'firstly', 'firsthand', 'first', 'firmly', 'finitely', 'finely', 'fine', 'financially', 'finally', 'figuratively', 'figurately', 'fightingly', 'fifthly', 'fiducially', 'fickly', 'feverously', 'feudally', 'fetisely', 'festally', 'femininely', 'feelingly', 'feebly', 'federally', 'fearfully', 'fawningly', 'favoredly', 'favorably', 'fatly', 'fastly', 'fashionably', 'farthest', 'farther', 'fantastically', 'familiarly', 'falsely', 'fallibly', 'faithfully', 'fair', 'faintly', 'faintheartedly', 'fadedly', 'factually', 'facially', 'fabulously', 'generally', 'generously', 'gently', 'gladly', 'gracefully', 'gratefully', 'greatly', 'greedily', 'gymnastically', 'gushingly', 'gurglingly', 'gullibly', 'guiltlessly', 'guiltily', 'guidinly', 'gruntingly', 'grumpily', 'growlingly', 'grotesquely', 'grossly', 'grimly', 'great', 'gravely', 'gratingly', 'gratifyingly', 'graphically', 'granularly', 'grandly', 'grandiosely', 'grammatically', 'gradually', 'graciously', 'gracelessly', 'goutily', 'gorgeously', 'goofily', 'good', 'goadingly', 'gnashingly', 'gluttonously', 'glumly', 'glowingly', 'gloweringly', 'glossily', 'gloriously', 'gloopily', 'gloomily', 'globally', 'gloatingly', 'glitteringly', 'glisteringly', 'glintingly', 'glidingly', 'gleefully', 'glassily', 'glaringly', 'glancingly', 'glamorously', 'glacially', 'girlishly', 'gingerly', 'gigglingly', 'gigantically', 'giddily', 'ghostly', 'ghastly', 'germanely', 'geometrically', 'geologically', 'geographically', 'geocentrically', 'genuinely', 'genteelly', 'genially', 'genetically', 'generically', 'gelidly', 'gayly', 'gawkishly', 'gaudily', 'gatewise', 'gaspingly', 'garrulously', 'garishly', 'gamely', 'gallantly', 'gainlessly', 'gainfully', 'gaily', 'gaddingly', 'happily', 'hard', 'harshly', 'hastily', 'heartily', 'heavily', 'helpfully', 'helplessly', 'here', 'highly', 'honestly', 'hopelessly', 'hungrily', 'hurriedly', 'hysterically', 'hypothetically', 'hypocritically', 'hypocritely', 'hypnotically', 'hyperbolically', 'hyperactively', 'huskily', 'hushedly', 'hurtfully', 'humorously', 'humiliatingly', 'humbly', 'humanly', 'humanely', 'hugely', 'huffingly', 'howso', 'however', 'hoveringly', 'hourly', 'hotly', 'hostilely', 'hospitably', 'horrifyingly', 'horrifically', 'horridly', 'horribly', 'horizontally', 'hopingly', 'hopefully', 'honorably', 'honest', 'homewards', 'homeward', 'homeopathically', 'homely', 'homelily', 'home', 'holily', 'hoggishly', 'hobbingly', 'hoarsely', 'hitherto', 'historically', 'hissingly', 'hintingly', 'hilariously', 'higher', 'high', 'hieroglyphically', 'hideously', 'hiddenly', 'hesitatingly', 'hermetically', 'hereon', 'hereinto', 'hereinafter', 'herein', 'hereby', 'hereablout', 'henceforth', 'hence', 'hellward', 'hellishly', 'heinously', 'heftily', 'heedlessly', 'heedfully', 'hedonistically', 'hectically', 'heavy', 'heavenly', 'heatedly', 'heartlessly', 'heartedly', 'hearlingly', 'healthily', 'headlong', 'headily', 'hazily', 'hauntingly', 'hauntedly', 'haughtily', 'hatefully', 'harmoniously', 'harmonially', 'harmlessly', 'hardly', 'harder', 'haplessly', 'haphazardly', 'handsomely', 'handily', 'haltingly', 'halfway', 'half', 'haggishly', 'haggardly', 'habitually', 'immediately', 'inadequately', 'increasingly', 'innocently', 'inquisitively', 'instantly', 'intensely', 'interestingly', 'inwardly', 'irritably', 'isolatedly', 'irritatingly', 'irrevocably', 'irreverently', 'irresponsibly', 'irresolutely', 'irregularly', 'irrationally', 'ironically', 'irately', 'inwards', 'inward', 'invariably', 'intuitively', 'introvertedly', 'intrinsically', 'intricately', 'intimately', 'internationally', 'internally', 'intermittently', 'interchangeably', 'intently', 'intentionally', 'intendedly', 'intelligibly', 'intelligently', 'intellectually', 'instinctively', 'instead', 'inspiringly', 'inside', 'insecurely', 'insatiably', 'initially', 'inherently', 'infrequently', 'informally', 'infinitely', 'inexplicably', 'inevitably', 'ineffectively', 'industrially', 'indoors', 'individually', 'indirectly', 'indignantly', 'indifferently', 'indicatively', 'indeterminedly', 'independently', 'indefinitely', 'indeed', 'indecisively', 'indecently', 'indebtedly', 'incurably', 'incrementally', 'incredulously', 'incredibly', 'incorrigibly', 'incorrectly', 'inconveniently', 'inconsolably', 'inconsiderately', 'inconsequently', 'incompletely', 'incompetently', 'incoherently', 'inclusively', 'incitingly', 'incidentally', 'incessantly', 'incautiously', 'incapably', 'inaudibly', 'inattentively', 'inasmuch', 'inarguably', 'inaptly', 'inappropriately', 'inadvertently', 'inactively', 'inaccurately', 'in', 'imputably', 'impurely', 'impulsively', 'imprudently', 'improvisationally', 'improperly', 'improbably', 'impressively', 'impressionably', 'imprecisely', 'impossibly', 'imposingly', 'importunely', 'importantly', 'impolitely', 'implorigly', 'impliedly', 'implicitly', 'implausivly', 'impishly', 'impetuously', 'impersonally', 'imperfectly', 'imperceptibly', 'imperatively', 'impeccably', 'impatiently', 'impartially', 'immovably', 'immorally', 'imminently', 'immensely', 'immeasurably', 'immaturely', 'immaculately', 'imitatively', 'imaginatively', 'illustratively', 'illusively', 'illogically', 'illicitly', 'illegibly', 'illegally', 'ignorantly', 'ignobly', 'idolizingly', 'idly', 'idiotically', 'identically', 'ideally', 'idealistically', 'icily', 'ichily', 'iambically', 'jealously', 'jovially', 'joyfully', 'joyously', 'jubilantly', 'justly', 'justifiedly', 'just', 'juridically', 'jumpily', 'jump', 'jumblingly', 'juicily', 'judiciously', 'judicially', 'judgmentally', 'judaically', 'joylessly', 'journalistically', 'joshingly', 'joltingly', 'jolly', 'jollily', 'jokingly', 'jointly', 'jocularly', 'jinglingly', 'jestingly', 'jerkily', 'jejunely', 'jeeringly', 'jazzily', 'jauntily', 'jarringly', 'jantily', 'janglingly', 'jaggedly', 'jadedly', 'jabberingly', 'keenly', 'kiddingly', 'kindly', 'knavishly', 'knowingly', 'knowledgeably', 'koranically', 'kookily', 'knowably', 'knottily', 'knobbily', 'knitwise', 'knightly', 'kneelingly', 'kittenishly', 'kissably', 'kinkily', 'kingly', 'kinetically', 'kinesthetically', 'kindheartedly', 'kinda', 'kickingly', 'kawaiily', 'karmically', 'kaleidoscopically', 'lazily', 'less', 'lightly', 'likely', 'lively', 'loftily', 'longingly', 'loosely', 'loudly', 'lovingly', 'loyally', 'lyrically', 'lyingly', 'luxuriously', 'lustrelessly', 'lustily', 'lustfully', 'lushly', 'lusciously', 'luminously', 'lumberingly', 'lullingly', 'lukewarmly', 'ludicrously', 'luckily', 'luciferously', 'lucidly', 'lowly', 'lowlily', 'loweringly', 'lower', 'low', 'louder', 'loud', 'lots', 'lot', 'lostly', 'losingly', 'lopsidedly', 'longwise', 'longly', 'longest', 'long', 'lonesomely', 'logically', 'locally', 'loathingly', 'livingly', 'lividly', 'livelily', 'live', 'little', 'lithely', 'literally', 'listlessly', 'lispingly', 'lispily', 'liquidly', 'linguistically', 'lingually', 'lingeringly', 'linearly', 'lineally', 'limply', 'limpingly', 'limpidly', 'limitedly', 'likewise', 'like', 'lightheartedly', 'lightheadedly', 'lightfootedly', 'lifeless', 'licitly', 'licentiously', 'libelously', 'lexically', 'lewdly', 'levelly', 'lethargically', 'lethally', 'lerringly', 'leniently', 'lengthwise', 'lengthily', 'leisurely', 'leisurably', 'legibly', 'legally', 'legalistically', 'leftwardly', 'leftward', 'left', 'leeward', 'leastwise', 'leastways', 'leapingly', 'leanly', 'leadingly', 'laxly', 'lawlessly', 'lawfully', 'lavishly', 'laughingly', 'laughably', 'lauditorialy', 'laudably', 'latterly', 'laterally', 'later', 'latently', 'lately', 'late', 'lastly', 'lastingly', 'last', 'lasciviousluy', 'largely', 'large', 'lankly', 'languishingly', 'languidly', 'landwards', 'landward', 'lamentingly', 'lamentably', 'laically', 'lagly', 'laggingly', 'ladylike', 'lacteally', 'laconically', 'lacklustrely', 'lackadaisically', 'labouredly', 'laboriously', 'labially', 'madly', 'majestically', 'meaningfully', 'mechanically', 'merrily', 'miserably', 'mockingly', 'more', 'mortally', 'mysteriously', 'mutually', 'musically', 'mostly', 'most', 'moreover', 'morbidly', 'morally', 'monstrously', 'monstrous', 'monitorially', 'monastically', 'momentarily', 'molecularly', 'modestly', 'modernly', 'moderately', 'modally', 'mixtly', 'mistrustingly', 'mistily', 'mistakingly', 'mistakenly', 'miraculously', 'ministerially', 'minionly', 'minimally', 'mingledly', 'mindlessly', 'mincingly', 'mimically', 'milkily', 'militarily', 'mildly', 'mighty', 'mightily', 'midweek', 'midway', 'midst', 'midships', 'microscopically', 'metrically', 'meticulously', 'methodically', 'metaphysically', 'metaphorically', 'metamerically', 'mesally', 'meritedly', 'meridionally', 'merely', 'mercilessly', 'mercifully', 'mentally', 'menacingly', 'memorably', 'mellowly', 'melancholily', 'meet', 'meekly', 'medicinally', 'medically', 'meddlingly', 'measly', 'meanwhile', 'meantime', 'meanly', 'meagerly', 'maybe', 'maximally', 'maturely', 'matrimonially', 'mathematically', 'maternally', 'materially', 'masterly', 'masterfully', 'massively', 'marvelously', 'martially', 'markedly', 'marginally', 'manywise', 'manually', 'mannerly', 'manifoldly', 'manifestly', 'mangily', 'manfully', 'malignantly', 'maliciously', 'malevolently', 'majorly', 'mainly', 'maidenly', 'magnificently', 'magnetizing', 'magnetically', 'magnanimously', 'magistrally', 'magisterially', 'magically', 'naturally', 'nearly', 'nervously', 'never', 'nicely', 'noisily', 'nutritively', 'nutritiously', 'nutritionally', 'nutly', 'numinously', 'numerously', 'numerically', 'numerally', 'numerably', 'numberlessly', 'noxiously', 'noway', 'now', 'novelly', 'nourishingly', 'nounally', 'noumenally', 'notoriously', 'notionally', 'noticeably', 'noteworthily', 'notedly', 'notarially', 'notably', 'nosily', 'nosely', 'northwestwards', 'northwestwardly', 'northwestward', 'northwards', 'northwardly', 'northward', 'northly', 'northernly', 'northerly', 'northeastwards', 'northeastwardly', 'northeastward', 'northeasterly', 'normatively', 'normally', 'noonly', 'nonzonally', 'nonvertically', 'nonverbally', 'nontrivially', 'nonsocially', 'nonnormally', 'nonfinitely', 'nonchalantly', 'noncausally', 'nominatively', 'nominally', 'noisomely', 'noiselessly', 'nohow', 'noetically', 'nodosely', 'nodally', 'nocturnally', 'nobly', 'nobbily', 'nittily', 'nitpickingly', 'nippingly', 'ninthly', 'nimbly', 'nilpotently', 'nightwards', 'nighttime', 'nightmarishly', 'nightly', 'niftily', 'nibblingly', 'newly', 'newfangly', 'neutrally', 'neurotically', 'neurally', 'nettlingly', 'netherward', 'nepotically', 'neoterically', 'neonatally', 'neologically', 'neolithically', 'neocortically', 'nematically', 'neighborly', 'negotiably', 'negligently', 'neglectingly', 'neglectfully', 'negatively', 'needsly', 'needly', 'needily', 'neatly', 'navigably', 'navally', 'nautically', 'nauseously', 'naughtily', 'naturedly', 'nattily', 'natively', 'nationally', 'natantly', 'nastily', 'nasally', 'narrowly', 'narrowingly', 'narratively', 'narcotically', 'namely', 'namelessly', 'nakedly', 'naively', 'naggingly', 'obediently', 'oddly', 'offensively', 'officially', 'only', 'openly', 'optimistically', 'obeyingly', 'obituarily', 'objectively', 'obligatorily', 'obliquely', 'oblongly', 'obscurely', 'obsequiously', 'observantly', 'obsoletely', 'obtusely', 'obversely', 'obviously', 'occasionally', 'occultly', 'ocularly', 'omnipotently', 'oafishly', 'obiter', 'obnoxiously', 'observingly', 'obstinately', 'odorously', 'offendedly', 'ofttimes', 'onto', 'onwards', 'operosely', 'opportunistically', 'oppositely', 'optically', 'optionally', 'ordinarily', 'ornamentally', 'orthodoxly', 'ostentatiously', 'others', 'outcept', 'outlandishly', 'outrightly', 'outward', 'ovally', 'overbearingly', 'overhighly', 'overly', 'overprotectively', 'oversoon', 'owlishly', 'oathfully', 'obeisantly', 'obligedly', 'obliviously', 'obscenely', 'observably', 'obsessively', 'obstreperously', 'officiously', 'oftentimes', 'oilily', 'onerously', 'online', 'onward', 'opaquely', 'opinionatedly', 'oppressively', 'optimally', 'opulently', 'orally', 'ordinately', 'ornately', 'oscitantly', 'other', 'otherways', 'otherwise', 'outdoors', 'outragedly', 'outside', 'outwardly', 'over', 'overboard', 'overmore', 'overseas', 'overtime', 'overwhelmingly', 'oxymoronically', 'obdurately', 'obligingly', 'obtrusively', 'odiously', 'offhandedly', 'often', 'ominously', 'once', 'ones', 'openhandedly', 'opportunely', 'opposite', 'optatively', 'oracularly', 'organizationally', 'originally', 'ornerily', 'ostensibly', 'othergates', 'otherwhere', 'outerly', 'outrageously', 'outspokenly', 'outwards', 'overall', 'overconfidently', 'overhead', 'overleaf', 'overmuch', 'overside', 'overtly', 'painfully', 'patiently', 'perfectly', 'physically', 'playfully', 'politely', 'poorly', 'potentially', 'powerfully', 'promptly', 'properly', 'proudly', 'punctually', 'partially', 'particularly', 'partly', 'passionately', 'peacefully', 'perhaps', 'periodically', 'permanently', 'personally', 'plainly', 'pleasantly', 'please', 'politically', 'positively', 'possibly', 'practically', 'precisely', 'predictably', 'predominantly', 'preferably', 'prematurely', 'presently', 'presumably', 'pretty', 'previously', 'primarily', 'principally', 'privately', 'proactively', 'probably', 'professionally', 'profoundly', 'progressively', 'prominently', 'psychologically', 'publicly', 'purely', 'purposefully', 'purposely', 'paganly', 'palatably', 'pallidly', 'palmately', 'palterly', 'paltrily', 'papally', 'parabolically', 'paradoxically', 'parallelly', 'paramountly', 'pardonably', 'parentally', 'parenthetically', 'parfitly', 'parliamentarily', 'parochially', 'participantly', 'participially', 'partitively', 'passably', 'passingly', 'past', 'patently', 'patly', 'peculiarly', 'pellmell', 'penally', 'pensively', 'perceptibly', 'permeably', 'perseveringly', 'perspicaciously', 'pettishly', 'philanthropically', 'pickaback', 'piercingly', 'piningly', 'piquantly', 'pithily', 'pitilessly', 'placidly', 'plausibly', 'pleasurably', 'ploddingly', 'plumply', 'poetically', 'politicly', 'porously', 'praisably', 'preparedly', 'pressingly', 'primely', 'princely', 'prissily', 'privily', 'prodigally', 'profanely', 'profitably', 'prophetically', 'prosingly', 'protectively', 'providently', 'proximally', 'pruriently', 'publically', 'puckishly', 'puissantly', 'pungently', 'punitively', 'purposedly', 'pursuantly', 'palely', 'pastorally', 'paternally', 'pausingly', 'peccantly', 'pendently', 'perceptively', 'perishably', 'permissively', 'persistently', 'perspicuously', 'petulantly', 'philosophically', 'piggishly', 'pinnately', 'pitiably', 'pityingly', 'plaguily', 'plenarily', 'pluckily', 'plurally', 'poignantly', 'polewards', 'pompously', 'popishly', 'posingly', 'potently', 'praiseworthily', 'prayerfully', 'prepensely', 'pressly', 'presumedly', 'prevalently', 'priggishly', 'primevally', 'pristinely', 'prodigiously', 'prolifically', 'promisingly', 'propitiously', 'prosperously', 'provisionally', 'prudently', 'pryingly', 'puerilely', 'pulingly', 'punily', 'punitorily', 'puzzlingly', 'painlessly', 'palpably', 'passively', 'patchily', 'peaceably', 'pectorally', 'peevishly', 'pellucidly', 'penitently', 'perilously', 'perkily', 'perpetually', 'persuasively', 'pettily', 'phenomenally', 'picturesquely', 'pinchingly', 'piously', 'piteously', 'pitifully', 'pleadingly', 'pleasingly', 'pointedly', 'popularly', 'poutingly', 'pragmatically', 'pratingly', 'prayingly', 'pregnantly', 'prestigiously', 'prettily', 'primly', 'priorly', 'productively', 'proficiently', 'profusely', 'prolixly', 'pronely', 'prosily', 'proteanly', 'provably', 'prudishly', 'psychically', 'puffingly', 'punishingly', 'quaintly', 'questionably', 'quickly', 'quietly', 'quirkily', 'quizzically', 'quackingly', 'quadrantally', 'quadriennially', 'quadripartitely', 'quaffably', 'quakily', 'qualifiably', 'qualitatively', 'qualmlessly', 'quantifiably', 'quantitively', 'quantumly', 'quarterly', 'quasilinearly', 'quasistatically', 'quaveringly', 'queenly', 'quenchlessly', 'queryingly', 'questioningly', 'questward', 'quinarily', 'quintically', 'quippingly', 'quiveringly', 'quizzingly', 'quotably', 'quackishly', 'quadratically', 'quadrupedally', 'quailingly', 'quakingly', 'qualifiedly', 'quantificationally', 'quaquaversally', 'quartically', 'quasilocally', 'queasily', 'quellingly', 'querimoniously', 'questingly', 'quickeningly', 'quickwittedly', 'quincuncially', 'quinquennially', 'quixotically', 'quotationally', 'quotidianly', 'quadrangularly', 'quadrennially', 'quadruply', 'qualmishly', 'quantically', 'quantitatively', 'quarrelsomely', 'quasiconformally', 'quasiperiodically', 'quaternarily', 'queenlily', 'quenchingly', 'querulously', 'questionlessly', 'quibblingly', 'quincunxially', 'quintessentially', 'quintuply', 'quotatively', 'quranically', 'rapidly', 'rarely', 'ravenously', 'readily', 'really', 'reassuringly', 'recklessly', 'regularly', 'reluctantly', 'repeatedly', 'restfully', 'righteously', 'rightfully', 'roughly', 'rudely', 'racially', 'randomly', 'rationally', 'realistically', 'reasonably', 'recently', 'refreshingly', 'regardless', 'regionally', 'regretfully', 'regrettably', 'relatively', 'relentlessly', 'reliably', 'religiously', 'remarkably', 'remotely', 'repetitively', 'reportedly', 'reputedly', 'resolutely', 'respectfully', 'respectively', 'responsibly', 'retroactively', 'reverently', 'rhetorically', 'rhythmically', 'richly', 'ridiculously', 'rightly', 'rigorously', 'robustly', 'romantically', 'routinely', 'royally', 'ruthlessly', 'rabidly', 'radially', 'radically', 'raggedly', 'rancidly', 'rantingly', 'rashly', 'ravishingly', 'realizingly', 'rearward', 'rectlinearly', 'reflectively', 'refreshfully', 'relaxingly', 'remissly', 'reparably', 'repellingly', 'repiningly', 'reprehensively', 'reprovingly', 'residentially', 'resinously', 'resonantly', 'respectably', 'resplendently', 'restoratively', 'retentively', 'retrospectively', 'reversedly', 'revokingly', 'rhapsodically', 'right', 'riotously', 'risibly', 'roaringly', 'rollickingly', 'romeward', 'ropily', 'rotundly', 'rowdily', 'ruinously', 'ruminantly', 'rushingly', 'radiantly', 'radioactively', 'railingly', 'ramblingly', 'rapaciously', 'rapturously', 'raspingly', 'rawly', 'rearwards', 'rebelliously', 'receptively', 'reclusely', 'recurrently', 'reflexively', 'regimentally', 'remedially', 'remorsefully', 'renewedly', 'repentantly', 'reproachfully', 'repulsively', 'resentfully', 'resignedly', 'resoundingly', 'restively', 'restrictively', 'reticently', 'reunitedly', 'reverentially', 'reversely', 'revoltingly', 'rightward', 'rimosely', 'ripely', 'riskily', 'rompingly', 'rosily', 'roundly', 'routously', 'ruefully', 'rulingly', 'runningly', 'rusticly', 'racily', 'radiately', 'raffishly', 'rakishly', 'rampantly', 'rankly', 'raucously', 'ravingly', 'readably', 'rebukingly', 'reciprocally', 'recognizably', 'redly', 'reflexly', 'regally', 'relativistically', 'relevantly', 'reminiscently', 'remorselessly', 'renownedly', 'repellently', 'reprehensibly', 'reputably', 'reservedly', 'resiliently', 'resourcefully', 'responsively', 'restlessly', 'revengefully', 'reversibly', 'rewardingly', 'ridgingly', 'rigidly', 'ringingly', 'ripplingly', 'ritually', 'roguishly', 'romanticly', 'roomily', 'rottenly', 'rousingly', 'rovingly', 'ruddily', 'ruggedly', 'rumblingly', 'rurally', 'rustily', 'sadly', 'safely', 'scarcely', 'searchingly', 'seemingly', 'seldom', 'selfishly', 'seriously', 'shakily', 'sharply', 'sheepishly', 'shrilly', 'shyly', 'silently', 'sleepily', 'slowly', 'smoothly', 'softly', 'solemnly', 'sometimes', 'soon', 'speedily', 'stealthily', 'sternly', 'strictly', 'stubbornly', 'stupidly', 'suddenly', 'supposedly', 'surprisingly', 'suspiciously', 'sweetly', 'swiftly', 'sympathetically', 'seamlessly', 'secondly', 'secretly', 'securely', 'separately', 'severely', 'shortly', 'significantly', 'similarly', 'simply', 'simultaneously', 'sincerely', 'slightly', 'socially', 'solely', 'someday', 'specially', 'specifically', 'steadily', 'still', 'strategically', 'strongly', 'subsequently', 'substantially', 'successfully', 'sufficiently', 'summarily', 'superficially', 'surely', 'sabbathly', 'sacramentally', 'sacrilegiously', 'saddleback', 'sagely', 'saltly', 'salutatorily', 'same', 'sanctimoniously', 'sanely', 'sappily', 'sardonically', 'sartorially', 'satirically', 'saturatedly', 'savagely', 'savourly', 'scalably', 'scamperingly', 'scantily', 'scarifyingly', 'schemingly', 'schmaltzily', 'schoolward', 'scintillatingly', 'scoffingly', 'scornfully', 'scraggily', 'screakily', 'scripturally', 'scrumptiously', 'sculpturally', 'seasonably', 'seawards', 'secularly', 'seedily', 'seethingly', 'segregatively', 'selectionally', 'selfconsciously', 'selflessly', 'semblably', 'semiannually', 'semidiurnally', 'semioccasionally', 'semiotically', 'semiseriously', 'semisystematically', 'sensationally', 'sensitively', 'sensorily', 'sentimentally', 'septentrionally', 'sequentially', 'serenely', 'seriocomically', 'serologically', 'seventhly', 'shadily', 'shakenly', 'shallowly', 'shamefacedly', 'shamingly', 'shiftily', 'shimmeringly', 'shipward', 'shitfully', 'shoddily', 'shortsightedly', 'showily', 'shriekingly', 'shudderingly', 'sibilantly', 'sikerly', 'silkenly', 'silly', 'sinfully', 'singularly', 'sinkward', 'sinusoidally', 'sixthly', 'sizably', 'sizzlingly', 'skewly', 'skillfully', 'skinnily', 'skulkingly', 'slackly', 'slammingly', 'slantly', 'slashingly', 'slaughterously', 'sleeplessly', 'slickly', 'slidingly', 'slily', 'slipperily', 'slipshodly', 'sloppily', 'slothfully', 'slumberously', 'smokelessly', 'spiritually', 'spitishly', 'stilly', 'suspectly', 'tensely', 'terribly', 'thankfully', 'thoroughly', 'thoughtfully', 'tightly', 'tomorrow', 'tonight', 'too', 'tremendously', 'truly', 'truthfully', 'typically', 'twittingly', 'twitchingly', 'twitchily', 'twistedly', 'twirlingly', 'twinklingly', 'twice', 'twangily', 'tutorially', 'turgidly', 'turbulently', 'turbidly', 'tunelessly', 'tunefully', 'tumultuously', 'tumidly', 'tuggingly', 'trustworthily', 'trustingly', 'trustily', 'trustfully', 'truculently', 'truantly', 'troubledly', 'tropically', 'trivially', 'triumphantly', 'tritely', 'trippingly', 'trimly', 'trillingly', 'trickily', 'triangularly', 'trepidly', 'trenchantly', 'tremulously', 'tremblingly', 'trebly', 'treatably', 'treasonously', 'treasonably', 'treacherously', 'traumatically', 'trashily', 'transparently', 'translucently', 'transcendentally', 'tranquilly', 'traitorously', 'trailingly', 'tragically', 'traditionally', 'toyingly', 'toxically', 'townwards', 'townward', 'toweringly', 'towards', 'toward', 'toughly', 'touchingly', 'touchily', 'touchedly', 'totally', 'tossily', 'torturously', 'tortuously', 'tortiously', 'torridly', 'torpidly', 'tornly', 'tormentingly', 'tormentedly', 'toppingly', 'topically', 'toothlessly', 'toothily', 'tonelessly', 'tomboyishly', 'tolerantly', 'tolerably', 'together', 'tofore', 'today', 'titularly', 'tiringly', 'tiresomely', 'tirelessly', 'tiredly', 'tipsily', 'tippily', 'tinklingly', 'tinglingly', 'timorously', 'timidly', 'timeously', 'timelessly', 'tidily', 'ticklishly', 'thwartly', 'thunderously', 'thunderingly', 'thumpingly', 'thuggishly', 'through', 'throatily', 'thrivingly', 'thrillingly', 'thriftily', 'threateningly', 'thoughtlessly', 'though', 'thornily', 'thirstily', 'thirdly', 'thinly', 'thievishly', 'thickly', 'thickheadedly', 'thermally', 'thereby', 'there', 'therapeutically', 'theoretically', 'thenadays', 'then', 'theatrically', 'thanklessly', 'textually', 'tetchily', 'testingly', 'testily', 'tersely', 'territorially', 'terrifyingly', 'terrifically', 'terminally', 'tepidly', 'tenuously', 'tenthly', 'tentatively', 'tenderly', 'tenaciously', 'temptingly', 'temptedly', 'temporarily', 'temporally', 'tempestuously', 'temperately', 'temperamentally', 'temerariously', 'tellingly', 'teetotally', 'tediously', 'technically', 'techily', 'teasingly', 'tearingly', 'tearily', 'tearfully', 'tawdrily', 'tautly', 'tauntingly', 'tattily', 'tastily', 'tastelessly', 'tastefully', 'tartly', 'tardily', 'tantivy', 'tantalizingly', 'tantalisingly', 'tanglingly', 'tangibly', 'tangentially', 'tandem', 'tamely', 'talkily', 'talkatively', 'talentedly', 'tactually', 'tactlessly', 'tactilely', 'tactically', 'tactfully', 'taciturnly', 'tacitly']

#def generate_word(index=2):
def generate_word(index=int):
    generated_word = ''
    #print("gen word index: " + str(index))

    if index >= 4:
        index = index - 3

    if index == 1:
        generated_word = generate_adv()
    elif index == 2:
        generated_word = generate_noun()
    elif index == 3:
        generated_word = generate_adj()
    return generated_word

def generate_adj():
    global adjectives
    adjective = random.choice(adjectives)
    adjectives.remove(adjective)
    return adjective

def generate_noun():
    global nouns
    noun = random.choice(nouns)
    nouns.remove(noun)
    return noun

def generate_adv():
    global adverbs
    adverb = random.choice(adverbs)
    adverbs.remove(adverb)
    return adverb

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

def obfuscate_subdomain(subdomain, mapping, index):
    if subdomain not in mapping:
        # TODO implement seeding randomness
        # TODO FIX THIS
        return generate_word(index)
    else:
        print('subdomain found: ' + str(subdomain))
        return mapping[subdomain]

def obfuscate_hostname(hostname, mapping):
    #print("hostname we're splitting: " + str(hostname))
    subdomains = hostname.split('.')
    obfuscated_subdomains = [obfuscate_subdomain(sub, mapping, subdomains.index(sub)+1) for sub in subdomains]
    obfuscated_hostname = '.'.join(obfuscated_subdomains)
    #print("new masked hostname: " + str(obfuscated_hostname))

    mapping[hostname] = obfuscated_hostname
    return obfuscated_hostname

def obfuscate_host(hostname, mapping):
    obfuscated_hostname = obfuscate_subdomain(hostname, mapping, 2)
    mapping[hostname] = obfuscated_hostname
    return obfuscated_hostname

def obfuscate_ip_address(ip_address, ip_mapping):
    octets = ip_address.split('.')
    obfuscated_octets = []
    if ip_address not in ip_mapping:
        #obfuscated_octets = [octets[0]] + [generate_word(octets.index(_)) for _ in octets[1:]]
        obfuscated_octets.append(octets[0])
        counter = 0
        #fixme
        for _ in octets[1:]:
            obfuscated_octets.append(generate_word(counter+1))
            counter += 1
            if counter == 3:
                counter = 0

            #reset counter
            #if counter == 3:
            #    counter = 0
        #print(f"obfuscated_octets: " + str(obfuscated_octets))
        ip_mapping[ip_address] = '.'.join(obfuscated_octets)
    return ip_mapping[ip_address]

def obfuscate_text(text, hostname_mapping, ip_mapping):
    hostnames = extract_hostnames(text)
    ip_addresses = extract_ip_addresses(text)
    short_hostname = socket.gethostname()
    skip_list = ["lib.*so", "io.*containerd", "systemd-*", "net.ipv*", "kernel*", ".*cattle.io.*", ".*tar.gz", ".*service", ".*log", ".*k8s.io"]

    for hostname in hostnames:
        # leverage skip list
        skip_check = ''
        skip_regex_matches = list(map(lambda regex: re.search(regex, hostname), skip_list))
        for match in skip_regex_matches:
            if match is not None:
                skip_check = 'found'

        if skip_check != "":
            continue

        if hostname not in hostname_mapping:
            obfuscated_name = obfuscate_hostname(hostname, hostname_mapping)
        else:
            obfuscated_name = hostname_mapping[hostname]
        text = text.replace(hostname, obfuscated_name)

    for ip_address in ip_addresses:
        if ip_address not in ip_mapping:
            obfuscated_ip = obfuscate_ip_address(ip_address, ip_mapping)
        else:
            obfuscated_ip = ip_mapping[ip_address]
        text = text.replace(ip_address, obfuscated_ip)

    #search for hostname not fqdn
    if short_hostname not in hostname_mapping:
        obfuscated_name = obfuscate_host(short_hostname, hostname_mapping)
    else:
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
if [ ! ${API_SERVER_OFFLINE} ]
  then
    provisioning-crds
  else
    techo "[!] Kube-apiserver is offline, skipping provisioning CRDs"
fi
archive
cleanup
echo "$(timestamp): Finished"
