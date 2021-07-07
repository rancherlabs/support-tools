#!/bin/bash

verify-access() {

  techo "Verifying cluster access"
  if [[ ! -z $OVERRIDE_KUBECONFIG ]];
  then
    ## Just use the kubeconfig that was set by the user
    KUBECTL_CMD="kubectl --kubeconfig $OVERRIDE_KUBECONFIG"
  elif [[ ! -z $KUBECONFIG ]];
  then
    KUBECTL_CMD="kubectl"
  elif [[ ! -z $KUBERNETES_PORT ]];
  then
    ## We are inside the k8s cluster or we're using the local kubeconfig
    RANCHER_POD=$(kubectl -n cattle-system get pods -l app=rancher --no-headers -o custom-columns=id:metadata.name | head -n1)
    KUBECTL_CMD="kubectl -n cattle-system exec -c rancher ${RANCHER_POD} -- kubectl"
  elif $(command -v k3s >/dev/null 2>&1)
  then
    ## We are on k3s node
    KUBECTL_CMD="k3s kubectl"
  elif $(command -v docker >/dev/null 2>&1)
  then
    DOCKER_ID=$(docker ps | grep "k8s_rancher_rancher" | cut -d' ' -f1 | head -1)
    KUBECTL_CMD="docker exec ${DOCKER_ID} kubectl"
  else
    ## Giving up
    techo "Could not find a kubeconfig"
  fi
  if ! ${KUBECTL_CMD} cluster-info >/dev/null 2>&1
  then
    techo "Can not access cluster"
    exit 1
  else
    techo "Cluster access has been verified"
  fi
}

checks() {
  if [[ -f cluster.yml ]]
  then
    echo "cluster.yml exists, please move or rename this file."
    exit 1
  fi
  echo "Checking that kubectl is installed"
  if [ ! -x "$(which kubectl)" ]
  then
    echo "Please download kubectl and install it and make sure the command is available in $PATH"
    echo 'curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"'
    exit 1
  fi
  echo "Checking that jq is installed"
  if [ ! -x "$(which jq)" ]
  then
    echo "Please download jq from https://github.com/stedolan/jq/releases/tag/jq-1.6 and install it and make sure the command is available in $PATH"
    exit 1
  fi
  echo "Checking that yq v3.x is installed"
  if [  -z  "`yq -V |grep "yq version 3"`" ]
  then
    echo "Please download yq v3.x from https://github.com/mikefarah/yq/releases/tag/3.4.1 and install it and make sure the command is available in $PATH"
    exit 1
 fi
}

build() {
echo "Building cluster.yml..."
${KUBECTL_CMD} -n kube-system get configmap full-cluster-state -o json | jq -r .data.\"full-cluster-state\" | jq -r .desiredState.rkeConfig | yq r -P - | sed 's/^/  /' | \
sed -e 's/internalAddress/internal_address/g' | \
sed -e 's/hostnameOverride/hostname_override/g' | \
sed -e 's/dockerSocket/docker_socket/g' | \
sed -e 's/sshAgentAuth/ssh_agent_auth/g' | \
sed -e 's/sshKey/ssh_key/g' | \
sed -e 's/sshKeyPath/ssh_key_path/g' | \
sed -e 's/sshCert/ssh_cert/g' | \
sed -e 's/sshCertPath/ssh_cert_path/g' | \
sed -e 's/kubeApi/kube-api/g' | \
sed -e 's/kubeController/kube-controller/g' | \
sed -e 's/externalUrls/external_urls/g' | \
sed -e 's/caCert/ca_cert/g' | \
sed -e 's/backupConfig/backup_config/g' | \
sed -e 's/serviceClusterIpRange/service_cluster_ip_range/g' | \
sed -e 's/serviceNodePortRange/service_node_port_range/g' | \
sed -e 's/podSecurityPolicy/pod_security_policy/g' | \
sed -e 's/alwaysPullImages/always_pull_images/g' | \
sed -e 's/SecretsEncryptionConfig /secrets_encryption_config/g' | \
sed -e 's/auditLog/ssh_key_path/g' | \
sed -e 's/auditLog/audit_log/g' | \
sed -e 's/admissionConfiguration/admission_configuration/g' | \
sed -e 's/eventRateLimit/event_rate_limit/g' | \
sed -e 's/maxAge/max_age/g' | \
sed -e 's/maxBackup/max_backup/g' | \
sed -e 's/maxSize/max_size/g' | \
sed -e 's/clusterCidr/cluster_cidr/g' | \
sed -e 's/serviceClusterIpRange/service_cluster_ip_range/g' | \
sed -e 's/clusterDomain/cluster_domain/g' | \
sed -e 's/infraContainerImage/infra_container_image/g' | \
sed -e 's/clusterDnsServer/cluster_dns_server/g' | \
sed -e 's/failSwapOn/fail_swap_on/g' | \
sed -e 's/generate_serving_certificate/generateServingCertificate/g' | \
sed -e 's/extraArgs/extra_args/g' | \
sed -e 's/extraBinds/extra_binds/g' | \
sed -e 's/extraEnv/extraEnv/g' | \
sed -e 's/winExtraArgs/win_extra_args/g' | \
sed -e 's/winExtraBinds/win_extra_binds/g' | \
sed -e 's/winExtraEnv/win_extra_env/g' | \
sed -e 's/calicoNetworkProvider/calico_network_provider/g' | \
sed -e 's/canalNetworkProvider/canal_network_provider/g' | \
sed -e 's/flannelNetworkProvider/flannel_network_provider/g' | \
sed -e 's/weaveNetworkProvider/weave_network_provider/g' | \
sed -e 's/aciNetworkProvider/aci_network_provider/g' | \
sed -e 's/nodeSelector/node_selector/g' | \
sed -e 's/updateStrategy/update_strategy/g' | \
sed -e 's/configFile/config_file/g' | \
sed -e 's/cacheTimeout/cache_timeout/g' | \
sed -e 's/nodeSelector/node_selector/g' | \
sed -e 's/dns_policy/dnsPolicy/g' | \
sed -e 's/extraVolumes/extra_volumes/g' | \
sed -e 's/extraVolumeMounts/extra_volume_mounts/g' | \
sed -e 's/httpPort/http_port/g' | \
sed -e 's/httpsPort/https_port/g' | \
sed -e 's/networkMode/network_mode/g' | \
sed -e 's/defaultBackend/default_backend/g' | \
sed -e 's/defaultHttpBackendPriorityClassName/default_http_backend_priority_class_name/g' | \
sed -e 's/nginx_ingress_controller_priority_class_name/nginxIngressControllerPriorityClassName/g' | \
sed -e 's/systemId/system_id/g' | \
sed -e 's/apicHosts/apic_hosts/g' | \
sed -e 's/apicUserName/apic_user_name/g' | \
sed -e 's/apicUserKey/apic_user_key/g' | \
sed -e 's/apicUserCrt/apic_user_crt/g' | \
sed -e 's/apicRefreshTime/apic_refresh_time/g' | \
sed -e 's/vmmDomain/vmm_domain/g' | \
sed -e 's/vmmController/vmm_controller/g' | \
sed -e 's/encapType/encap_type/g' | \
sed -e 's/nodeSubnet/node_subnet/g' | \
sed -e 's/mcastRangeStart/mcast_range_start/g' | \
sed -e 's/mcastRangeEnd/mcast_range_end/g' | \
sed -e 's/vrfName/vrf_name/g' | \
sed -e 's/vrfTenant/vrf_tenant/g' | \
sed -e 's/l3outExternalNetworks/l3out_external_networks/g' | \
sed -e 's/externDynamic/extern_dynamic/g' | \
sed -e 's/externStatic/extern_static/g' | \
sed -e 's/nodeSvcSubnet/node_svc_subnet/g' | \
sed -e 's/kubeApiVlan/kube_api_vlan/g' | \
sed -e 's/serviceVlan/service_vlan/g' | \
sed -e 's/infraVlan/infra_vlan/g' | \
sed -e 's/ovsMemoryLimit/ovs_memory_limit/g' | \
sed -e 's/imagePullPolicy/image_pull_policy/g' | \
sed -e 's/imagePullSecret/image_pull_secret/g' | \
sed -e 's/serviceMonitorInterval/service_monitor_interval/g' | \
sed -e 's/pbrTrackingNonSnat/pbr_tracking_non_snat/g' | \
sed -e 's/installIstio/install_istio/g' | \
sed -e 's/istioProfile/istio_profile/g' | \
sed -e 's/dropLogEnable/drop_log_enable/g' | \
sed -e 's/controllerLogLevel/controller_log_level/g' | \
sed -e 's/hostAgentLogLevel/host_agent_log_level/g' | \
sed -e 's/opflexLogLevel/opflex_log_level/g' | \
sed -e 's/useAciCniPriorityClass/use_aci_cni_priority_class/g' | \
sed -e 's/noPriorityClass/no_priority_class/g' | \
sed -e 's/maxNodesSvcGraph/max_nodes_svc_graph/g' | \
sed -e 's/snatContractScope/snat_contract_scope/g' | \
sed -e 's/podSubnetChunkSize/pod_subnet_chunk_size/g' | \
sed -e 's/enableEndpointSlice/enable_endpoint_slice/g' | \
sed -e 's/snatNamespace/snat_namespace/g' | \
sed -e 's/epRegistry/ep_registry/g' | \
sed -e 's/opflexMode/opflex_mode/g' | \
sed -e 's/snatPortRangeStart/snat_port_range_start/g' | \
sed -e 's/snatPortRangeEnd/snat_port_range_end/g' | \
sed -e 's/snatPortsPerNode/snat_ports_per_node/g' | \
sed -e 's/opflexClientSsl/opflex_client_ssl/g' | \
sed -e 's/usePrivilegedContainer/use_privileged_container/g' | \
sed -e 's/useHostNetnsVolume/use_host_netns_volume/g' | \
sed -e 's/useOpflexServerVolume/use_opflex_server_volume/g' | \
sed -e 's/subnetDomainName/subnet_domain_name/g' | \
sed -e 's/kafkaBrokers/kafka_brokers/g' | \
sed -e 's/kafkaClientCrt/kafka_client_crt/g' | \
sed -e 's/kafkaClientKey/kafka_client_key/g' | \
sed -e 's/useAciAnywhereCrd/use_aci_anywhere_crd/g' | \
sed -e 's/overlayVrfName/overlay_vrf_name/g' | \
sed -e 's/gbpPodSubnet/gbp_pod_subnet/g' | \
sed -e 's/runGbpContainer/run_gbp_container/g' | \
sed -e 's/runOpflexServerContainer/run_opflex_server_container/g' | \
sed -e 's/opflexServerPort/opflex_server_port/g' | \
sed -e 's/virtualCenter/virtual_center/g' | \
sed -e 's/loadBalancer/load_balancer/g' | \
sed -e 's/blockStorage/block_storage/g' | \
sed -e 's/serviceOverride/service_override/g' | \
sed -e 's/metricsServerPriorityClassName/metrics_server_priority_class_name/g' | \
sed -e 's/snapshotName/snapshot_name/g' | \
sed -e 's/linearAutoscalerParams/linear_autoscaler_params/g' | \
sed -e 's/ipAddress/ip_address/g' | \
sed -e 's/nodeLocalDnsPriorityClassName/node_local_dns_priority_class_name/g' | \
sed -e 's/coresPerReplica/cores_per_replica/g' | \
sed -e 's/nodesPerReplica/nodes_per_replica/g' | \
sed -e 's/preventSinglePointFailure/prevent_single_point_failure/g' | \
sed -e 's/customConfig/custom_config/g' | \
sed -e 's/ignoreDaemonSets/ignore_daemonsets/g' | \
sed -e 's/deleteLocalData/delete_local_data/g' | \
sed -e 's/gracePeriod/grace_period/g' > cluster.yml
echo "" >> cluster.yml

echo "Building cluster.rkestate..."
${KUBECTL_CMD} -n kube-system get configmap full-cluster-state -o json | jq -r .data.\"full-cluster-state\" | jq -r . > cluster.rkestate
}

rke_up() {
read -n1 -rsp $'Press any key to continue run an rke up or Ctrl+C to exit...\n'
echo "Running rke up..."
rke up --config cluster.yml
}

help() {

  echo "Rancher Pod Collector
  Usage: cluster-yaml-recovery.sh [-k KUBECONFIG -f ]
  All flags are optional
  -k    Override the kubeconfig (ex: ~/.kube/custom)
  -f    Overwrite cluster.yml and cluster.rkestate files"

}

while getopts ":k:fh" opt; do
  case $opt in
    k)
      OVERRIDE_KUBECONFIG="${OPTARG}"
      ;;
    f)
      FORCE=1
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

verify-access
if [ -z "${FORCE}" ]
then
  checks
fi
build
rke_up
