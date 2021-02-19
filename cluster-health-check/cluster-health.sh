#!/bin/bash
# Minimum space needed to run the script (MB)
SPACE=2048

setup() {

  TMPDIR=$(mktemp -d $MKTEMP_BASEDIR)
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
    exit 2
  fi
  if ! ${KUBECTL_CMD} cluster-info >/dev/null 2>&1
  then
    techo "Can not access cluster"
    exit 1
  else
    techo "Cluster access has been verified"
  fi
  if [[ ! -z $DEBUG ]]
  then
    KUBECTL_CMD="${KUBECTL_CMD} --v=6"
  fi
}

cluster-info() {

  techo "Collecting information about the cluster..."
  mkdir -p $TMPDIR/clusterinfo
  decho "cluster-info"
  ${KUBECTL_CMD} cluster-info > $TMPDIR/clusterinfo/cluster-info 2>&1
  ${KUBECTL_CMD} cluster-info dump > $TMPDIR/clusterinfo/cluster-info-dump 2>&1
  decho "get nodes"
  ${KUBECTL_CMD} get nodes -o wide > $TMPDIR/clusterinfo/get-node.wide 2>&1
  ${KUBECTL_CMD} get nodes -o yaml > $TMPDIR/clusterinfo/get-node-yaml 2>&1
}

nodes() {
  techo "Collecting information about the nodes..."
  mkdir -p $TMPDIR/nodes/
  ${KUBECTL_CMD} get nodes -o wide > $TMPDIR/nodes/get-nodes.wide
  ${KUBECTL_CMD} get nodes -o yaml > $TMPDIR/nodes/get-nodes-yaml
  ${KUBECTL_CMD} top nodes > $TMPDIR/nodes/top-node
  decho "Describing nodes..."
  mkdir -p $TMPDIR/nodes/describe
  for NODE in `${KUBECTL_CMD} get node -o NAME | awk -F '/' '{print $2}'`
  do
    ${KUBECTL_CMD} describe node $NODE > $TMPDIR/nodes/describe/$NODE
  done
  techo "Gathering node counts..."
  decho "All nodes..."
  NumberOfNodes=`${KUBECTL_CMD} get nodes --no-headers | wc -l`
  decho "master"
  ${KUBECTL_CMD} get nodes --selector='node-role.kubernetes.io/master' -o wide > $TMPDIR/nodes/get-nodes-master.wide 2>&1
  NumberOfMasterNodes=`${KUBECTL_CMD} get nodes --selector='node-role.kubernetes.io/master' --no-headers 2>/dev/null | wc -l`
  decho "etcd"
  ${KUBECTL_CMD} get nodes --selector='node-role.kubernetes.io/etcd' -o wide > $TMPDIR/nodes/get-nodes-etcd.wide 2>&1
  NumberOfEtcdNodes=`${KUBECTL_CMD} get nodes --selector='node-role.kubernetes.io/etcd' --no-headers 2>/dev/null | wc -l`
  decho "controlplane"
  ${KUBECTL_CMD} get nodes --selector='node-role.kubernetes.io/controlplane' -o wide > $TMPDIR/nodes/get-nodes-controlplane.wide 2>&1
  NumberOfControlplaneNodes=`${KUBECTL_CMD} get nodes --selector='node-role.kubernetes.io/controlplane' --no-headers 2>/dev/null | wc -l`
  decho "worker"
  ${KUBECTL_CMD} get nodes --selector='node-role.kubernetes.io/worker' -o wide > $TMPDIR/nodes/get-nodes-worker.wide 2>&1
  NumberOfWorkerNodes=`${KUBECTL_CMD} get nodes --selector='node-role.kubernetes.io/worker' --no-headers 2>/dev/null | wc -l`
  techo "Node Summary Report"
  techo "All nodes:"                   $NumberOfNodes | tee -a $TMPDIR/nodes/summary
  techo "etcd:"                        $NumberOfEtcdNodes | tee -a $TMPDIR/nodes/summary
  techo "controlplane:"                $NumberOfControlplaneNodes | tee -a $TMPDIR/nodes/summary
  techo "worker:"                      $NumberOfWorkerNodes | tee -a $TMPDIR/nodes/summary
  techo "master:"                      $NumberOfMasterNodes | tee -a $TMPDIR/nodes/summary
  techo "Pods Per Node"
  for NODE in `${KUBECTL_CMD} get node -o NAME | awk -F '/' '{print $2}'`
  do
    NumberOfPodsPerNode=`${KUBECTL_CMD} get pods --all-namespaces --field-selector spec.nodeName=$NODE -o wide | wc -l`
    techo $NODE" "$NumberOfPodsPerNode | tee -a $TMPDIR/nodes/pods-per-node
  done
}

get-hyperkube-image() {
  HyperKubeImage=`${KUBECTL_CMD} -n kube-system get pod -l job-name=rke-network-plugin-deploy-job -o jsonpath={..image} | tr -s '[[:space:]]' '\n' | sort | uniq`
  if [[ -z $HyperKubeImage ]]
  then
    HyperKubeImage="rancher/hyperkube:v1.19.7-rancher1"
  fi
  echo $HyperKubeImage
}

overlay-test() {
  mkdir -p $TMPDIR/overlaytest/
  techo "Deploying overlay test containers"
  get-hyperkube-image HyperKubeImage > /dev/null 2>&1
  decho "HyperKubeImage: $HyperKubeImage"
  cat <<EOF | sed -e "s/HyperKubeImage/${HyperKubeImage//\//\\/}/g" | tee $TMPDIR/overlaytest/overlay-test.yaml | ${KUBECTL_CMD} -n kube-system apply -f -
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: overlaytest
spec:
  selector:
      matchLabels:
        name: overlaytest
  template:
    metadata:
      labels:
        name: overlaytest
    spec:
      tolerations:
      - operator: Exists
      containers:
      - image: HyperKubeImage
        imagePullPolicy: Always
        name: overlaytest
        command: ["sh", "-c", "tail -f /dev/null"]
        terminationMessagePath: /dev/termination-log
EOF
  techo "Waiting for rollout to complete..."
  ${KUBECTL_CMD} -n kube-system rollout status ds/overlaytest -w
  techo "Starting network overlay test" | tee -a $TMPDIR/overlaytest/overlay.log
  ${KUBECTL_CMD} -n kube-system get pods -l name=overlaytest -o jsonpath='{range .items[*]}{@.metadata.name}{" "}{@.spec.nodeName}{"\n"}{end}' |
  while read sourcepod sourehost
  do
    decho "sourcepod: $sourcepod"
    decho "sourehost: $sourehost"
    ${KUBECTL_CMD} -n kube-system get pods -l name=overlaytest -o jsonpath='{range .items[*]}{@.status.podIP}{" "}{@.spec.nodeName}{"\n"}{end}' |
    while read targetip targethost
    do
      decho "targetip: $targetip"
      decho "targethost: $targethost"
      ${KUBECTL_CMD} -n kube-system --request-timeout='10s' exec $sourcepod -c overlaytest -- /bin/sh -c "ping -c2 $targetip > /dev/null 2>&1"
      RC=$?
      if [ $RC -ne 0 ]
      then
        techo "Failure: $sourcepod on $sourehost cannot reach pod IP $targetip on $targethost" | tee -a $TMPDIR/overlaytest/overlay.log
      else
        techo "Success: $sourcepod on $sourehost can reach pod IP $targetip on $targethost" | tee -a $TMPDIR/overlaytest/overlay.log
      fi
    done
  done
  techo "Finished network overlay test" | tee -a $TMPDIR/overlaytest/overlay.log
  techo "Cleaning up network overlay test"
  ${KUBECTL_CMD} -n kube-system delete ds/overlaytest
}

dns-test() {
  mkdir -p $TMPDIR/dnstest/
  techo "Deploying DNS test containers"
  get-hyperkube-image HyperKubeImage > /dev/null 2>&1
  decho "HyperKubeImage: $HyperKubeImage"
  cat <<EOF | sed -e "s/HyperKubeImage/${HyperKubeImage//\//\\/}/g" | tee $TMPDIR/dnstest/dns-test.yaml | ${KUBECTL_CMD} -n kube-system apply -f -
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: dnstest
spec:
  selector:
      matchLabels:
        name: dnstest
  template:
    metadata:
      labels:
        name: dnstest
    spec:
      tolerations:
      - operator: Exists
      containers:
      - image: HyperKubeImage
        imagePullPolicy: Always
        name: dnstest
        command: ["sh", "-c", "tail -f /dev/null"]
        terminationMessagePath: /dev/termination-log
EOF
  techo "Waiting for rollout to complete..."
  ${KUBECTL_CMD} -n kube-system rollout status ds/dnstest -w
  techo "Starting cluster DNS test" | tee -a $TMPDIR/dnstest/dnstest.log
  ${KUBECTL_CMD} -n kube-system get pods -l name=dnstest -o jsonpath='{range .items[*]}{@.metadata.name}{" "}{@.spec.nodeName}{"\n"}{end}' |
  while read pod host
  do
    ${KUBECTL_CMD} -n kube-system --request-timeout='10s' exec $pod -c dnstest -- /bin/sh -c 'TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token); curl --cacert /var/run/secrets/kubernetes.io/serviceaccount/ca.crt -H "Authorization: Bearer $TOKEN" https://kubernetes.default/api/v1/ > /dev/null 2>&1'
    RC=$?
    if [ $RC -ne 0 ]
    then
      techo "Failure: DNS is not working correctly for $pod on $host" | tee -a $TMPDIR/dnstest/dnstest.log
    else
      techo "Success: DNS is working correctly for $pod on $host" | tee -a $TMPDIR/dnstest/dnstest.log
    fi
  done
  techo "Finished DNS dns test" | tee -a $TMPDIR/dnstest/dnstest.log
  techo "Cleaning up DNS dns test"
  ${KUBECTL_CMD} -n kube-system delete ds/dnstest
}

pods() {
  techo "Collecting information about the pods..."
  mkdir -p $TMPDIR/pods/
  ${KUBECTL_CMD} get pods -A -o wide > $TMPDIR/pods/get-pods.wide
  ${KUBECTL_CMD} get pods -A -o yaml > $TMPDIR/pods/get-pods-yaml
  NumberOfPods=`${KUBECTL_CMD} get pods -A --no-headers | wc -l`
  decho "Running"
  ${KUBECTL_CMD} get pods -A --field-selector=status.phase=Running > $TMPDIR/pods/pods-Running 2>&1
  NumberOfRunningPods=`${KUBECTL_CMD} get pods -A --no-headers --field-selector=status.phase=Running 2>/dev/null | wc -l`
  decho "Pending"
  ${KUBECTL_CMD} get pods -A --field-selector=status.phase=Pending > $TMPDIR/pods/pods-Pending 2>&1
  NumberOfPendingPods=`${KUBECTL_CMD} get pods -A --no-headers --field-selector=status.phase=Pending 2>/dev/null | wc -l`
  decho "Failed"
  ${KUBECTL_CMD} get pods -A --field-selector=status.phase=Failed > $TMPDIR/pods/pods-Failed 2>&1
  NumberOfFailedPods=`${KUBECTL_CMD} get pods -A --no-headers --field-selector=status.phase=Failed 2>/dev/null | wc -l`
  decho "Unknown"
  ${KUBECTL_CMD} get pods -A --field-selector=status.phase=Unknown > $TMPDIR/pods/pods-Unknown 2>&1
  NumberOfUnknownPods=`${KUBECTL_CMD} get pods -A --no-headers --field-selector=status.phase=Unknown 2>/dev/null | wc -l`
  decho "Completed"
  ${KUBECTL_CMD} get pods -A --field-selector=status.phase=Succeeded > $TMPDIR/pods/pods-Completed 2>&1
  NumberOfCompletedPods=`${KUBECTL_CMD} get pods -A --no-headers --field-selector=status.phase=Succeeded 2>/dev/null | wc -l`
  decho "CrashLoopBackOff"
  ${KUBECTL_CMD} get pods -A --field-selector=status.phase=Running > $TMPDIR/pods/pods-CrashLoopBackOff 2>&1
  NumberOfCrashLoopBackOffPods=`${KUBECTL_CMD} get pods -A --no-headers --field-selector=status.phase=CrashLoopBackOff 2>/dev/null | wc -l`
  decho "NodeAffinity"
  ${KUBECTL_CMD} get pods -A --field-selector=status.phase=NodeAffinity > $TMPDIR/pods/pods-NodeAffinity 2>&1
  NumberOfNodeAffinityPods=`${KUBECTL_CMD} get pods -A --no-headers --field-selector=status.phase=CrashLoopBackOff 2>/dev/null | wc -l`
  decho "ImagePullBackOff"
  ${KUBECTL_CMD} get pods -A --field-selector=status.phase=NodeAffinity > $TMPDIR/pods/pods-ImagePullBackOff 2>&1
  NumberOfImagePullBackOffPods=`${KUBECTL_CMD} get pods -A --no-headers --field-selector=status.phase=ImagePullBackOff 2>/dev/null | wc -l`
  techo "Pod Summary Report"
  techo "Pods:"                        $NumberOfPods | tee -a $TMPDIR/pods/summary
  techo "Running:"                     $NumberOfRunningPods | tee -a $TMPDIR/pods/summary
  techo "Pending:"                     $NumberOfPendingPods | tee -a $TMPDIR/pods/summary
  techo "Failed:"                      $NumberOfFailedPods | tee -a $TMPDIR/pods/summary
  techo "Unknown:"                     $NumberOfUnknownPods | tee -a $TMPDIR/pods/summary
  techo "Completed:"                   $NumberOfCompletedPods | tee -a $TMPDIR/pods/summary
  techo "CrashLoopBackOff:"            $NumberOfCrashLoopBackOffPods | tee -a $TMPDIR/pods/summary
  techo "NodeAffinity:"                $NumberOfNodeAffinityPods | tee -a $TMPDIR/pods/summary
  techo "ImagePullBackOff:"            $NumberOfImagePullBackOffPods | tee -a $TMPDIR/pods/summary
  techo "NodeAffinity:"                $NumberOfNodeAffinityPods | tee -a $TMPDIR/pods/summary
  decho "top pod"
  ${KUBECTL_CMD} top pod -A > $TMPDIR/pods/top-pod
  ${KUBECTL_CMD} top pod -A --sort-by=cpu > $TMPDIR/pods/top-pod-by-cpu
  ${KUBECTL_CMD} top pod -A --sort-by=memory > $TMPDIR/pods/top-pod-by-memory
}

get-namespace-all() {
  NAMESPACE=$1
  techo "Collecting information about $NAMESPACE"
  mkdir -p $TMPDIR/$NAMESPACE/
  ${KUBECTL_CMD} -n $NAMESPACE get pods -o wide  > $TMPDIR/$NAMESPACE/get-pods.wide 2>&1
  ${KUBECTL_CMD} -n $NAMESPACE get pods -o yaml  > $TMPDIR/$NAMESPACE/get-pods.yaml 2>&1
  ${KUBECTL_CMD} -n $NAMESPACE get service -o wide  > $TMPDIR/$NAMESPACE/get-service.wide 2>&1
  ${KUBECTL_CMD} -n $NAMESPACE get service -o yaml  > $TMPDIR/$NAMESPACE/get-service.yaml 2>&1
  ${KUBECTL_CMD} -n $NAMESPACE get endpoints -o wide  > $TMPDIR/$NAMESPACE/get-endpoints.wide 2>&1
  ${KUBECTL_CMD} -n $NAMESPACE get endpoints -o yaml  > $TMPDIR/$NAMESPACE/get-endpoints.yaml 2>&1
  ${KUBECTL_CMD} -n $NAMESPACE get daemonset -o wide  > $TMPDIR/$NAMESPACE/get-daemonset.wide 2>&1
  ${KUBECTL_CMD} -n $NAMESPACE get daemonset -o yaml  > $TMPDIR/$NAMESPACE/get-daemonset.yaml 2>&1
  ${KUBECTL_CMD} -n $NAMESPACE get deployment -o wide  > $TMPDIR/$NAMESPACE/get-deployment.wide 2>&1
  ${KUBECTL_CMD} -n $NAMESPACE get deployment -o yaml  > $TMPDIR/$NAMESPACE/get-deployment.yaml 2>&1
  ${KUBECTL_CMD} -n $NAMESPACE get replicaset -o wide  > $TMPDIR/$NAMESPACE/get-replicaset.wide 2>&1
  ${KUBECTL_CMD} -n $NAMESPACE get replicaset -o yaml  > $TMPDIR/$NAMESPACE/get-replicaset.yaml 2>&1
  ${KUBECTL_CMD} -n $NAMESPACE get job -o wide  > $TMPDIR/$NAMESPACE/get-job.wide 2>&1
  ${KUBECTL_CMD} -n $NAMESPACE get job -o yaml  > $TMPDIR/$NAMESPACE/get-job.yaml 2>&1
  ${KUBECTL_CMD} -n $NAMESPACE get cronjob -o wide  > $TMPDIR/$NAMESPACE/get-cronjob.wide 2>&1
  ${KUBECTL_CMD} -n $NAMESPACE get cronjob -o yaml  > $TMPDIR/$NAMESPACE/get-cronjob.yaml 2>&1
  ${KUBECTL_CMD} -n $NAMESPACE get configmap  > $TMPDIR/$NAMESPACE/get-configmap 2>&1
  ${KUBECTL_CMD} -n $NAMESPACE get configmap -o yaml  > $TMPDIR/$NAMESPACE/get-configmap.yaml 2>&1
  ${KUBECTL_CMD} -n $NAMESPACE get secret  > $TMPDIR/$NAMESPACE/get-secret 2>&1
  ${KUBECTL_CMD} -n $NAMESPACE get pvc -o wide > $TMPDIR/$NAMESPACE/get-pvc.wide 2>&1
  ${KUBECTL_CMD} -n $NAMESPACE get pvc -o yaml  > $TMPDIR/$NAMESPACE/get-pvc.yaml 2>&1
}

storage() {
  techo "Collecting information about storage..."
  mkdir -p $TMPDIR/storage/
  ${KUBECTL_CMD} get storageclass > $TMPDIR/storage/get-storageclass
  ${KUBECTL_CMD} get storageclass -o yaml > $TMPDIR/storage/get-storageclass.yaml
  mkdir -p $TMPDIR/storage/pv/
  ${KUBECTL_CMD} get pv -o wide > $TMPDIR/storage/get-pv.wide
  ${KUBECTL_CMD} get pv -o yaml > $TMPDIR/storage/get-pv.yaml
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

  echo "Cluster Health Check
  Usage: cluster-health.sh [ -d <directory> -k ~/.kube/config -f -D ]

  All flags are optional
  -d    Output directory for temporary storage and .tar.gz archive (ex: -d /var/tmp)
  -k    Override the kubeconfig (ex: ~/.kube/custom)
  -f    Force collection if the minimum space isn't available
  -D    Enable debug logging"

}

timestamp() {

  date "+%Y-%m-%d %H:%M:%S"

}

techo() {
  echo "$(timestamp): $*"
}

decho() {
  if [[ ! -z $DEBUG ]]
  then
    techo "$*"
  fi
}

while getopts ":d:s:r:fhD" opt; do
  case $opt in
    d)
      MKTEMP_BASEDIR="-p ${OPTARG}"
      ;;
    s)
      START=$(date -d "-${OPTARG} days" '+%Y-%m-%d')
      SINCE_FLAG="--since ${START}"
      ;;
    r)
      RUNTIME_FLAG="${OPTARG}"
      ;;
    f)
      FORCE=1
      ;;
    D)
      DEBUG=1
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

verify-access
cluster-info
nodes
pods
storage
Namespaces='cattle-dashboards cattle-logging-system cattle-monitoring-system cattle-system cis-operator-system fleet-system ingress-nginx kube-node-lease kube-public kube-system local-path-storage longhorn-system'
for Namespace in $Namespaces
do
  get-namespace-all $Namespace
done
overlay-test
dns-test
archive
cleanup
