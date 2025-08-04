#!/usr/bin/env bash
#
# This script runs on all nodes of the cluster. Used to run commands
# that collect info at a per-node level.
#

SONOBUOY_RESULTS_DIR=${SONOBUOY_RESULTS_DIR:-"/tmp/results"}
ERROR_LOG_FILE="${SONOBUOY_RESULTS_DIR}/error.log"
SONOBUOY_DONE_FIE="${SONOBUOY_RESULTS_DIR}/done"
HOST_FS_PREFIX="${HOST_FS_PREFIX:-"/host"}"

OUTPUT_DIR="${SONOBUOY_RESULTS_DIR}/output"
LOG_DIR="${OUTPUT_DIR}/logs"
TAR_OUTPUT_FILE="${SONOBUOY_RESULTS_DIR}/nodeinfo.tar.gz"

# This is set from outside, otherwise assuming rke
CLUSTER_PROVIDER=${CLUSTER_PROVIDER:-"rke"}

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

get_symlink_destination() {
  LS_RESULT=$(ls -l $1)
  if [[ $LS_RESULT == *"->"* ]]; then
    IFS=' ' read -ra ADDR <<< "$LS_RESULT"
    LINK_DESTINATION=${ADDR[-1]}
    if [[ $LINK_DESTINATION == /* ]]; then
      echo "${HOST_FS_PREFIX}$LINK_DESTINATION"
      return
    fi
  fi
  echo $1
}

collect_systeminfo() {
  if [ -d ${HOST_FS_PREFIX} ]; then
    ls -l ${HOST_FS_PREFIX} > ls-l-host.log
  fi

  cp -p ${HOST_FS_PREFIX}/etc/hosts systeminfo/etchosts 2>&1
  ETC_RESOLVE_CONF_PATH="$(get_symlink_destination ${HOST_FS_PREFIX}/etc/resolv.conf)"
  cp -p ${ETC_RESOLVE_CONF_PATH} systeminfo/etcresolvconf 2>&1
  if [ -e ${HOST_FS_PREFIX}/run/systemd/resolve/resolv.conf ];then
    cp -p ${HOST_FS_PREFIX}/run/systemd/resolve/resolv.conf systeminfo/systemd-resolved 2>&1
  fi

  cp -p ${HOST_FS_PREFIX}/proc/cpuinfo systeminfo/cpuinfo 2>&1
  cp -p ${HOST_FS_PREFIX}/proc/meminfo systeminfo/meminfo 2>&1
  cp -p ${HOST_FS_PREFIX}/proc/sys/fs/file-nr systeminfo/file-nr 2>&1
  cp -p ${HOST_FS_PREFIX}/proc/sys/fs/file-max systeminfo/file-max 2>&1
  cp -p ${HOST_FS_PREFIX}/etc/security/limits.conf systeminfo/limits.conf 2>&1
  # Every system that we officially support has /etc/os-release
  cat ${HOST_FS_PREFIX}/etc/os-release > systeminfo/os-release 2>&1
  cat ${HOST_FS_PREFIX}/etc/centos-release > systeminfo/centos-release 2>&1

  ps auxfww > systeminfo/ps 2>&1
  free -m > systeminfo/freem 2>&1
  df -i ${HOST_FS_PREFIX}/var > systeminfo/dfivar 2>&1
  df ${HOST_FS_PREFIX}/var > systeminfo/dfvar 2>&1

  # TODO: Check if the sysctl settings are same on the host/inside the container
  if $(command -v sysctl >/dev/null 2>&1); then
    sysctl -a > systeminfo/sysctla 2>/dev/null
  fi

  kubectl version -o json > systeminfo/kubectl-version.json 2>/dev/null
  kubectl get settings.management.cattle.io server-version -o json > systeminfo/server-version.json 2>/dev/null
  if [ ! -s systeminfo/server-version.json ]; then
    rm systeminfo/server-version.json
  fi
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
  nft list ruleset > networking/nft_ruleset 2>&1
  cat ${HOST_FS_PREFIX}/proc/sys/net/netfilter/nf_conntrack_max > networking/nf_conntrack_max
  cat ${HOST_FS_PREFIX}/proc/sys/net/netfilter/nf_conntrack_count > networking/nf_conntrack_count

  for _NAMESERVER in $(awk '/^nameserver/ {print $2}' systeminfo/etcresolvconf)
    do
      echo "--- Nameserver: ${_NAMESERVER}" >> networking/dns-external 2>&1
      dig google.com @${_NAMESERVER} >> networking/dns-external 2>&1
  done

  if kubectl get svc -n kube-system kube-dns > /dev/null 2>&1
    then
      _COREDNS_SVC=kube-dns
    else
      _COREDNS_SVC=rke2-coredns-rke2-coredns
  fi

  _COREDNS_SVC_IP=$(kubectl get services -n kube-system ${_COREDNS_SVC} -o=jsonpath='{.spec.clusterIP}')
  dig kubernetes.default.svc.cluster.local @${_COREDNS_SVC_IP} >> networking/dns-internal 2>&1

  _COREDNS_ENDPOINTS=$(kubectl get endpoints -n kube-system ${_COREDNS_SVC} -o=jsonpath='{.subsets[*].addresses[*].ip}')
  for _ENDPOINT in ${_COREDNS_ENDPOINTS}
    do
      echo "--- CoreDNS endpoint: ${_ENDPOINT}" >> networking/dns-internal-all-endpoints 2>&1
      dig kubernetes.default.svc.cluster.local @${_ENDPOINT} >> networking/dns-internal-all-endpoints 2>&1
  done
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

collect_websock_info() {
  # echo "SGVsbG8sIHdvcmxkIQ==" | base64 -d
  RANCHER_HOST=$(echo ${RANCHER_URL} | sed -E 's/^http(s)?:\/\///')
  echo ${RANCHER_URL} > networking/rancher_url 2>&1
  echo ${RANCHER_HOST%/} > networking/rancher_host 2>&1
  echo ${HOSTED_RANCHER_HOSTNAME_SUFFIX} > networking/hosted_rancher_hostname_suffix 2>&1
  curl -s --include --no-buffer \
  --header "Connection: Upgrade" \
  --header "Upgrade: websocket" \
  --header "Host: "${RANCHER_HOST%/} \
  --header "Origin: "${RANCHER_URL} \
  --header "Sec-WebSocket-Key: SGVsbG8sIHdvcmxkIQ==" \
  --header "Sec-WebSocket-Version: 13" ${RANCHER_URL}/healthz \
  -o networking/rancher_websocket_check
}

collect_networking_info() {
  collect_networking_info_ip4
  collect_networking_info_ip6
  collect_websock_info

  cp -r -p ${HOST_FS_PREFIX}/etc/cni/net.d/* networking/cni 2>&1
}

collect_rke_node_info() {
  mkdir -p "${OUTPUT_DIR}/rke"
  mkdir -p "${OUTPUT_DIR}/docker"
  curl -s --unix-socket ${HOST_FS_PREFIX}/run/docker.sock http://localhost/info > ${OUTPUT_DIR}/docker/docker_info.json 2>&1
  cp ${HOST_FS_PREFIX}/etc/docker/daemon.json ${OUTPUT_DIR}/docker/docker_daemon.json 2>&1
  collect_rke_certs
}

collect_rke2_node_info() {
  mkdir -p "${OUTPUT_DIR}/rke2"
  RKE2_BINARY=$( pgrep -a rke2 | cut -d' ' -f2 )

  #Get RKE2 Configuration file(s), redacting secrets
  if [ -f "${HOST_FS_PREFIX}/etc/rancher/rke2/config.yaml" ]; then
    cat ${HOST_FS_PREFIX}/etc/rancher/rke2/config.yaml | sed -E 's/("|\x27)?(agent-token|token|etcd-s3-access-key|etcd-s3-secret-key|datastore-endpoint)("|\x27)?:\s*("|\x27)?.*("|\x27)?/\1\2\3: <REDACTED>/' > ${OUTPUT_DIR}/rke2/config.yaml
  else
    touch ${OUTPUT_DIR}/rke2/config.yaml
  fi
  if [ -d "${HOST_FS_PREFIX}/etc/rancher/rke2/config.yaml.d" ]; then
    mkdir -p "${OUTPUT_DIR}/rke2/config.yaml.d"
    for yaml in ${HOST_FS_PREFIX}/etc/rancher/rke2/config.yaml.d/*.yaml; do
      cat ${yaml} | sed -E 's/("|\x27)?(agent-token|token|etcd-s3-access-key|etcd-s3-secret-key|datastore-endpoint)("|\x27)?:\s*("|\x27)?.*("|\x27)?/\1\2\3: <REDACTED>/' > ${OUTPUT_DIR}/rke2/config.yaml.d/$(basename ${yaml})
    done
  fi
  sherlock-rke2-data-dir
  collect_rke2_certs
}

collect_k3s_node_info() {
  mkdir -p "${OUTPUT_DIR}/k3s"
  K3S_BINARY=$( pgrep -a k3s | cut -d' ' -f2 )

  #Get k3s Configuration file(s), redacting secrets
  if [ -f "${HOST_FS_PREFIX}/etc/rancher/k3s/config.yaml" ]; then
    cat ${HOST_FS_PREFIX}/etc/rancher/k3s/config.yaml | sed -E 's/("|\x27)?(agent-token|token|etcd-s3-access-key|etcd-s3-secret-key|datastore-endpoint)("|\x27)?:\s*("|\x27)?.*("|\x27)?/\1\2\3: <REDACTED>/' > ${OUTPUT_DIR}/k3s/config.yaml
  else
    touch ${OUTPUT_DIR}/k3s/config.yaml
  fi
  if [ -d "${HOST_FS_PREFIX}/etc/rancher/k3s/config.yaml.d" ]; then
    mkdir -p "${OUTPUT_DIR}/k3s/config.yaml.d"
    for yaml in ${HOST_FS_PREFIX}/etc/rancher/k3s/config.yaml.d/*.yaml; do
      cat ${yaml} | sed -E 's/("|\x27)?(agent-token|token|etcd-s3-access-key|etcd-s3-secret-key|datastore-endpoint)("|\x27)?:\s*("|\x27)?.*("|\x27)?/\1\2\3: <REDACTED>/' > ${OUTPUT_DIR}/k3s/config.yaml.d/$(basename ${yaml})
    done
  fi
  collect_k3s_certs
}

collect_node_info() {
  collect_systeminfo
  collect_networking_info

  if [ "${IS_UPSTREAM_CLUSTER}" == "true" ]; then
    collect_upstream_cluster_specific_info
  else
    collect_downstream_cluster_specific_info
  fi

  case $CLUSTER_PROVIDER in
    "rke")
      collect_rke_node_info
    ;;
    "rke2")
      collect_rke2_node_info
    ;;
    "k3s")
      collect_k3s_node_info
    ;;
    *)
      echo "error: CLUSTER_PROVIDER is not set"
    ;;
  esac
}

collect_upstream_cluster_specific_info() {
  echo "upstream: no specific commands to be run on node"
}

collect_downstream_cluster_specific_info() {
  echo "downstream: no specific commands to be run on node"
}

collect_rke_certs() {
  mkdir -p ${OUTPUT_DIR}/rke/certs
  if [ -d ${HOST_FS_PREFIX}/opt/rke/etc/kubernetes/ssl ]; then
    CERTS=$(find ${HOST_FS_PREFIX}/opt/rke/etc/kubernetes/ssl -type f -name *.pem | grep -v "\-key\.pem$")
    for CERT in $CERTS; do
      openssl x509 -in $CERT -text -noout > ${OUTPUT_DIR}/rke/certs/$(basename $CERT) 2>&1
    done
  elif [ -d ${HOST_FS_PREFIX}/etc/kubernetes/ssl ]; then
    CERTS=$(find ${HOST_FS_PREFIX}/etc/kubernetes/ssl -type f -name *.pem | grep -v "\-key\.pem$")
    for CERT in $CERTS; do
      openssl x509 -in $CERT -text -noout > ${OUTPUT_DIR}/rke/certs/$(basename $CERT) 2>&1
    done
  fi
}

collect_k3s_certs() {
  if [ -d ${HOST_FS_PREFIX}/var/lib/rancher/k3s ]; then
    mkdir -p ${OUTPUT_DIR}/k3s/certs/agent
    AGENT_CERTS=$(find ${HOST_FS_PREFIX}/var/lib/rancher/k3s/agent -maxdepth 1 -type f -name "*.crt" | grep -v "\-ca.crt$")
    for CERT in $AGENT_CERTS; do
      openssl x509 -in $CERT -text -noout > ${OUTPUT_DIR}/k3s/certs/agent/$(basename $CERT) 2>&1
    done
    if [ -d ${HOST_FS_PREFIX}/var/lib/rancher/k3s/server/tls ]; then
      mkdir -p ${OUTPUT_DIR}/k3s/certs/server
      SERVER_CERTS=$(find ${HOST_FS_PREFIX}/var/lib/rancher/k3s/server/tls -maxdepth 1 -type f -name "*.crt" | grep -v "\-ca.crt$")
      for CERT in $SERVER_CERTS; do
        openssl x509 -in $CERT -text -noout > ${OUTPUT_DIR}/k3s/certs/server/$(basename $CERT) 2>&1
      done
    fi
  fi
}

collect_rke2_certs() {
  if [ -d ${RKE2_DIR} ]; then
    mkdir -p ${OUTPUT_DIR}/rke2/certs/agent
    AGENT_CERTS=$(find ${RKE2_DIR}/agent -maxdepth 1 -type f -name "*.crt" | grep -v "\-ca.crt$")
    for CERT in $AGENT_CERTS; do
      openssl x509 -in $CERT -text -noout > ${OUTPUT_DIR}/rke2/certs/agent/$(basename $CERT) 2>&1
    done
    if [ -d ${RKE2_DIR}/server/tls ]; then
      techo "Collecting rke2 server certificates"
      mkdir -p ${OUTPUT_DIR}/rke2/certs/server
      SERVER_CERTS=$(find ${RKE2_DIR}/server/tls -maxdepth 1 -type f -name "*.crt" | grep -v "\-ca.crt$")
      for CERT in $SERVER_CERTS; do
        openssl x509 -in $CERT -text -noout > ${OUTPUT_DIR}/rke2/certs/server/$(basename $CERT) 2>&1
      done
    fi
  fi
}

sherlock-rke2-data-dir() {

  if [ -f ${HOST_FS_PREFIX}/etc/rancher/rke2/config.yaml ]; then
      CUSTOM_DIR=$(awk '$1 ~ /data-dir:/ {print $2}' ${HOST_FS_PREFIX}/etc/rancher/rke2/config.yaml)
  fi
  if [[ -z "${CUSTOM_DIR}" ]]; then
    RKE2_DIR="${HOST_FS_PREFIX}/var/lib/rancher/rke2"
  else
    RKE2_DIR="${HOST_FS_PREFIX}/${CUSTOM_DIR}"
  fi

}

delete_sensitive_info() {
  rm -f networking/cni/*kubeconfig
}

move_ip_map() {
  if [ "${OBFUSCATE}" == "true" ]; then
    echo "moving map"
    mv ip_map.json ${SONOBUOY_RESULTS_DIR}/
  else
    echo "nothing to move"
  fi
}

main() {
  echo "start"
  date "+%Y-%m-%d %H:%M:%S"

  prereqs

  # Note:
  #       Don't prefix any of the output files. The following line needs to be
  #       adjusted accordingly.
  cd "${OUTPUT_DIR}"

  collect_node_info

  #Handle Obfuscate env var
  if [ "${OBFUSCATE}" == "true" ]; then
    echo "obfuscation enabled"
    echo "true" > "obfuscate_data"

    json_list=("docker/docker_info.json")
    text_list=("systeminfo/ps" "networking/ipaddrshow" "networking/iproute" "networking/ipneighbour" "networking/ssanp" "networking/ssitan" "networking/ssuapn" "networking/ss4apn" "networking/sstunlp4" "networking/nft_ruleset" "networking/dns-external" "networking/dns-internal" "networking/dns-internal-all-endpoints" "networking/ss6apn"
)

    for file in ${json_list[@]}; do
      newfile=$(sed 's/\//\/obf_/' <<< $file)
      obfuscate_json.py $file $newfile
      rm $file
      echo "moving $newfile to $file"
      mv $newfile $file
    done

    for file in ${text_list[@]}; do
      newfile=$(sed 's/\//\/obf_/' <<< $file)
      obfuscate_text.py $file $newfile
      rm $file
      echo "moving ${newfile} to ${file}"
      mv $newfile $file
    done
  fi

  delete_sensitive_info
  move_ip_map

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
