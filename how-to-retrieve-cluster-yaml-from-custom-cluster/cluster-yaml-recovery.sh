
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
 IFS=''
 while read line
 do
  word=$(echo "$line" |awk -F ":" '{print $1}')
  new_word=$(echo "$line" |awk -F ":" '{print $1}' | perl -pe 's/([a-z0-9])([A-Z])/$1_\L$2/g')
  echo "$line"| sed "s/$word/$new_word/g" >>cluster.yml
 done< <(${KUBECTL_CMD} -n kube-system get configmap full-cluster-state -o json | jq -r .data.\"full-cluster-state\" | jq -r .desiredState.rkeConfig | yq r -P -)

 echo "Building cluster.rkestate..."
 ${KUBECTL_CMD} -n kube-system get configmap full-cluster-state -o json | jq -r .data.\"full-cluster-state\" | jq -r . > cluster.rkestate
}


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
