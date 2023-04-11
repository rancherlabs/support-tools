#!/usr/bin/env bash
#
# This script runs on all nodes of the cluster. Used to run commands
# that collect info at a per-node level.
#

CONFIG_DIR="${CONFIG_DIR:-/etc/kube-bench/cfg}"
SONOBUOY_RESULTS_DIR=${SONOBUOY_RESULTS_DIR:-"/tmp/results"}
ERROR_LOG_FILE="${SONOBUOY_RESULTS_DIR}/error.log"
SONOBUOY_DONE_FIE="${SONOBUOY_RESULTS_DIR}/done"
HOST_FS_PREFIX="${HOST_FS_PREFIX:-"/host"}"

OUTPUT_DIR="${SONOBUOY_RESULTS_DIR}/output"
LOG_DIR="${OUTPUT_DIR}/logs"
TAR_OUTPUT_FILE="${SONOBUOY_RESULTS_DIR}/nodeinfo.tar.gz"

handle_error() {
  if [ "${DEBUG}" == "true" ]  || [ "${DEV}" == "true" ]; then
    sleep infinity
  fi
  echo -n "${ERROR_LOG_FILE}" > "${SONOBUOY_DONE_FIE}"
}

trap 'handle_error' ERR

set -x

prereqs() {
  mkdir -p "${OUTPUT_DIR}"
  mkdir -p "${OUTPUT_DIR}/networking"
  mkdir -p "${OUTPUT_DIR}/networking/cni"
  mkdir -p "${OUTPUT_DIR}/systeminfo"
  mkdir -p "${LOG_DIR}"
}

collect_systeminfo() {
  if [ -d ${HOST_FS_PREFIX} ]; then
    ls -l ${HOST_FS_PREFIX} > ls-l-host.log
  fi

  cp -p ${HOST_FS_PREFIX}/etc/hosts systeminfo/etchosts 2>&1
  cp -p ${HOST_FS_PREFIX}/etc/resolv.conf systeminfo/etcresolvconf 2>&1
  if [ -e ${HOST_FS_PREFIX}/run/systemd/resolve/resolv.conf ];then
    cp -p ${HOST_FS_PREFIX}/run/systemd/resolve/resolv.conf systeminfo/systemd-resolved 2>&1
  fi

  cp -p ${HOST_FS_PREFIX}/proc/cpuinfo systeminfo/cpuinfo 2>&1
  cp -p ${HOST_FS_PREFIX}/proc/sys/fs/file-nr systeminfo/file-nr 2>&1
  cp -p ${HOST_FS_PREFIX}/proc/sys/fs/file-max systeminfo/file-max 2>&1
  cp -p ${HOST_FS_PREFIX}/etc/security/limits.conf systeminfo/limits.conf 2>&1
  cat ${HOST_FS_PREFIX}/etc/*release > systeminfo/osrelease 2>&1

  ps auxfww > systeminfo/ps 2>&1

  # TODO: Check if the sysctl settings are same on the host/inside the container
  sysctl -a > systeminfo/sysctla 2>/dev/null
}

collect_networking_info_ip4() {
  iptables-save > networking/iptablessave

  IPTABLES_FLAGS="--wait 1"
  iptables $IPTABLES_FLAGS --numeric --verbose --list --table mangle > networking/iptablesmangle 2>&1
  iptables $IPTABLES_FLAGS --numeric --verbose --list --table nat > networking/iptablesnat 2>&1
  iptables $IPTABLES_FLAGS --numeric --verbose --list > networking/iptables 2>&1

  ip addr show > networking/ipaddrshow 2>&1
  ip route show table all > networking/iproute 2>&1
  ip neighbour > networking/ipneighbour 2>&1
  ip rule show > networking/iprule 2>&1
  ip -s link show > networking/iplinkshow 2>&1

  # netstat is obsolete in sles, use ss
  ss -anp > networking/ssanp 2>&1
  ss -itan > networking/ssitan 2>&1
  ss -uapn > networking/ssuapn 2>&1
  ss -wapn > networking/sswapn 2>&1
  ss -xapn > networking/ssxapn 2>&1
  ss -4apn > networking/ss4apn 2>&1
  ss -tunlp4 > networking/sstunlp4 2>&1

  conntrack -S > networking/conntrack.out
  nft list ruleset  > networking/nft_ruleset 2>&1
}

collect_networking_info_ip6() {
  ip6tables-save > networking/ip6tablessave 2>&1

  IPTABLES_FLAGS="--wait 1"
  ip6tables $IPTABLES_FLAGS --numeric --verbose --list --table mangle > networking/ip6tablesmangle 2>&1
  ip6tables $IPTABLES_FLAGS --numeric --verbose --list --table nat > networking/ip6tablesnat 2>&1
  ip6tables $IPTABLES_FLAGS --numeric --verbose --list > networking/ip6tables 2>&1

  ip -6 neighbour > networking/ipv6neighbour 2>&1
  ip -6 rule show > networking/ipv6rule 2>&1
  ip -6 route show > networking/ipv6route 2>&1
  ip -6 addr show > networking/ipv6addrshow 2>&1

  ss -6apn > networking/ss6apn 2>&1
  ss -tunlp6 > networking/sstunlp6 2>&1
}

collect_networking_info() {
  collect_networking_info_ip4
  collect_networking_info_ip6

  cp -r -p ${HOST_FS_PREFIX}/etc/cni/net.d/* networking/cni 2>&1
}

collect_upstream_cluster_specific_info() {
  echo "upstream: no specific commands to be run on node"
}

collect_downstream_cluster_specific_info() {
  echo "downstream: no specific commands to be run on node"
}

delete_sensitive_info() {
  rm -f networking/cni/*kubeconfig
}

main() {
  echo "start"
  date "+%Y-%m-%d %H:%M:%S"

  prereqs

  # Note:
  #       Don't prefix any of the output files. The following line needs to be
  #       adjusted accordingly.
  cd "${OUTPUT_DIR}"

  collect_systeminfo
  collect_networking_info

  if [ "${IS_UPSTREAM_CLUSTER}" == "true" ]; then
    collect_upstream_cluster_specific_info
  else
    collect_downstream_cluster_specific_info
  fi

  delete_sensitive_info

  if [ "${DEBUG}" != "true" ]; then
    tar czvf "${TAR_OUTPUT_FILE}" -C "${OUTPUT_DIR}" .
    echo -n "${TAR_OUTPUT_FILE}" > "${SONOBUOY_DONE_FIE}"
  else
    echo "Running in DEBUG mode, plugin will NOT exit [cleanup by deleting namespace]."
  fi

  echo "end"
  date "+%Y-%m-%d %H:%M:%S"

  # Wait
  sleep infinity
}

main
