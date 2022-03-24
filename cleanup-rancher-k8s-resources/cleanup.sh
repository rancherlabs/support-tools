#!/bin/sh
# Warning
echo "==================== WARNING ===================="
echo "THIS WILL DELETE ALL RESOURCES CREATED BY RANCHER"
echo "MAKE SURE YOU HAVE CREATED AND TESTED YOUR BACKUPS"
echo "THIS IS A NON REVERSIBLE ACTION"
echo "==================== WARNING ===================="

# Linux only for now
if [ "$(uname -s)" != "Linux" ]; then
  echo "Must be run on Linux"
  exit 1
fi

# Check kubectl existence
if ! which kubectl >/dev/null 2>&1; then
  echo "kubectl not found in PATH, make sure kubectl is available"
  exit 1
fi

# Test connectivity
if ! kubectl get nodes >/dev/null 2>&1; then
  echo "'kubectl get nodes' exited non-zero, make sure environment variable KUBECONFIG is set to a working kubeconfig file"
  exit 1
fi

echo "=> Printing cluster info for confirmation"
kubectl cluster-info
kubectl get nodes -o wide

echo -n "Do you want to continue (y/n)?"
read answer

if [ "$answer" != "y" ]; then
    exit 1
fi

kcd()
{
  kubectl delete --ignore-not-found=true --grace-period=30 "$@"
}

kcpf()
{
  kubectl patch -p '{"metadata":{"finalizers":null}}' --type=merge "$@"
}

kcdns()
{
  if kubectl get namespace $1; then
    kubectl get namespace "$1" -o json | tr -d "\n" | sed "s/\"finalizers\": \[[^]]\+\]/\"finalizers\": []/"   | kubectl replace --raw /api/v1/namespaces/$1/finalize -f -
    kubectl delete --ignore-not-found=true --grace-period=30 namespace $1
  fi
}

printapiversion()
{
if echo $1 | grep -q '/'; then
  echo $1 | cut -d'/' -f1
else
  echo ""
fi
}

set -x
# Namespaces with resources that probably have finalizers/dependencies (needs manual traverse to patch and delete else it will hang)
CATTLE_NAMESPACES="local cattle-system cattle-impersonation-system"
TOOLS_NAMESPACES="istio-system cattle-resources-system cis-operator-system cattle-dashboards cattle-gatekeeper-system cattle-alerting cattle-logging cattle-pipeline cattle-prometheus rancher-operator-system cattle-monitoring-system cattle-logging-system"
FLEET_NAMESPACES="cattle-fleet-clusters-system cattle-fleet-local-system cattle-fleet-system fleet-default fleet-local fleet-system"
# System namespaces
SYSTEM_NAMESPACES="kube-system ingress-nginx"
# Namespaces that just store data resources (and resources can be automatically deleted if namespace is deleted)
CATTLE_DATA_NAMESPACES="cattle-global-data cattle-global-nt"

# Delete rancher install to not have anything running that (re)creates resources
kcd -n cattle-system deploy,ds --all
# Delete the only resource not in cattle namespaces
kcd -n kube-system configmap cattle-controllers

# Delete any blocking webhooks from preventing requests
kcd $(kubectl get mutatingwebhookconfigurations -o name | grep cattle\.io)
kcd $(kubectl get validatingwebhookconfigurations -o name | grep cattle\.io)

# Delete any monitoring webhooks
kcd $(kubectl get mutatingwebhookconfigurations -o name | grep rancher-monitoring)
kcd $(kubectl get validatingwebhookconfigurations -o name | grep rancher-monitoring)

# Delete any gatekeeper webhooks
kcd $(kubectl get validatingwebhookconfigurations -o name | grep gatekeeper)

# Delete any istio webhooks
kcd $(kubectl get mutatingwebhookconfigurations -o name | grep istio)
kcd $(kubectl get validatingwebhookconfigurations -o name | grep istio)

# Cluster api
kcd validatingwebhookconfiguration.admissionregistration.k8s.io/validating-webhook-configuration
kcd mutatingwebhookconfiguration.admissionregistration.k8s.io/mutating-webhook-configuration

# Delete generic k8s resources either labeled with norman or resource name starting with "cattle|rancher|fleet"
# ClusterRole/ClusterRoleBinding
kubectl get clusterrolebinding -l cattle.io/creator=norman --no-headers -o custom-columns=NAME:.metadata.name | while read CRB; do
  kcpf clusterrolebindings $CRB
  kcd clusterrolebindings $CRB
done

kubectl get clusterrolebinding --no-headers -o custom-columns=NAME:.metadata.name | grep ^cattle- | while read CRB; do
  kcpf clusterrolebindings $CRB
  kcd clusterrolebindings $CRB
done

kubectl get clusterrolebinding --no-headers -o custom-columns=NAME:.metadata.name | grep rancher | while read CRB; do
  kcpf clusterrolebindings $CRB
  kcd clusterrolebindings $CRB
done

kubectl get clusterrolebinding --no-headers -o custom-columns=NAME:.metadata.name | grep ^fleet- | while read CRB; do
  kcpf clusterrolebindings $CRB
  kcd clusterrolebindings $CRB
done

kubectl get clusterrolebinding --no-headers -o custom-columns=NAME:.metadata.name | grep ^gitjob | while read CRB; do
  kcpf clusterrolebindings $CRB
  kcd clusterrolebindings $CRB
done

kubectl get clusterrolebinding --no-headers -o custom-columns=NAME:.metadata.name | grep ^pod-impersonation-helm- | while read CRB; do
  kcpf clusterrolebindings $CRB
  kcd clusterrolebindings $CRB
done

kubectl get clusterrolebinding --no-headers -o custom-columns=NAME:.metadata.name | grep ^gatekeeper | while read CRB; do
  kcpf clusterrolebindings $CRB
  kcd clusterrolebindings $CRB
done

kubectl get clusterrolebinding --no-headers -o custom-columns=NAME:.metadata.name | grep ^cis | while read CRB; do
  kcpf clusterrolebindings $CRB
  kcd clusterrolebindings $CRB
done

kubectl get clusterrolebinding --no-headers -o custom-columns=NAME:.metadata.name | grep ^istio | while read CRB; do
  kcpf clusterrolebindings $CRB
  kcd clusterrolebindings $CRB
done

kubectl  get clusterroles -l cattle.io/creator=norman --no-headers -o custom-columns=NAME:.metadata.name | while read CR; do
  kcpf clusterroles $CR
  kcd clusterroles $CR
done

kubectl get clusterroles --no-headers -o custom-columns=NAME:.metadata.name | grep ^cattle- | while read CR; do
  kcpf clusterroles $CR
  kcd clusterroles $CR
done

kubectl get clusterroles --no-headers -o custom-columns=NAME:.metadata.name | grep rancher | while read CR; do
  kcpf clusterroles $CR
  kcd clusterroles $CR
done

kubectl get clusterroles --no-headers -o custom-columns=NAME:.metadata.name | grep ^fleet | while read CR; do
  kcpf clusterroles $CR
  kcd clusterroles $CR
done

kubectl get clusterroles --no-headers -o custom-columns=NAME:.metadata.name | grep ^gitjob | while read CR; do
  kcpf clusterroles $CR
  kcd clusterroles $CR
done

kubectl get clusterroles --no-headers -o custom-columns=NAME:.metadata.name | grep ^pod-impersonation-helm | while read CR; do
  kcpf clusterroles $CR
  kcd clusterroles $CR
done

kubectl get clusterroles --no-headers -o custom-columns=NAME:.metadata.name | grep ^logging- | while read CR; do
  kcpf clusterroles $CR
  kcd clusterroles $CR
done

kubectl get clusterroles --no-headers -o custom-columns=NAME:.metadata.name | grep ^monitoring- | while read CR; do
  kcpf clusterroles $CR
  kcd clusterroles $CR
done

kubectl get clusterroles --no-headers -o custom-columns=NAME:.metadata.name | grep ^gatekeeper | while read CR; do
  kcpf clusterroles $CR
  kcd clusterroles $CR
done

kubectl get clusterroles --no-headers -o custom-columns=NAME:.metadata.name | grep ^cis | while read CR; do
  kcpf clusterroles $CR
  kcd clusterroles $CR
done

kubectl get clusterroles --no-headers -o custom-columns=NAME:.metadata.name | grep ^istio | while read CR; do
  kcpf clusterroles $CR
  kcd clusterroles $CR
done

# Delete namespaces that only contain data so all resources in the namespace get deleted automatically
# Saves time in the loop below where we patch/delete individual resources
for DNS in $CATTLE_DATA_NAMESPACES; do
  kcdns $DNS
done

# Bulk delete data CRDs
# Saves time in the loop below where we patch/delete individual resources
DATACRDS="settings.management.cattle.io authconfigs.management.cattle.io features.management.cattle.io"
for CRD in $DATACRDS; do
  kcd crd $CRD
done

# Delete apiservice
for apiservice in $(kubectl  get apiservice -o name | grep cattle | grep -v k3s\.cattle\.io | grep -v helm\.cattle\.io) $(kubectl  get apiservice -o name | grep gatekeeper\.sh) $(kubectl  get apiservice -o name | grep istio\.io) apiservice\.apiregistration\.k8s\.io\/v1beta1\.custom\.metrics\.k8s\.io; do
  kcd $apiservice
done

# Pod security policies
# Rancher logging
for psp in $(kubectl get podsecuritypolicy -o name -l app.kubernetes.io/name=rancher-logging) podsecuritypolicy.policy/rancher-logging-rke-aggregator; do
  kcd $psp
done

# Rancher monitoring
for psp in $(kubectl  get podsecuritypolicy -o name -l release=rancher-monitoring) $(kubectl get podsecuritypolicy -o name -l app=rancher-monitoring-crd-manager) $(kubectl get podsecuritypolicy -o name -l app=rancher-monitoring-patch-sa) $(kubectl get podsecuritypolicy -o name -l app.kubernetes.io/instance=rancher-monitoring); do
  kcd $psp
done

# Rancher OPA
for psp in $(kubectl  get podsecuritypolicy -o name -l release=rancher-gatekeeper) $(kubectl get podsecuritypolicy -o name -l app=rancher-gatekeeper-crd-manager); do
  kcd $psp
done

# Backup restore operator
for psp in $(kubectl get podsecuritypolicy -o name -l app.kubernetes.io/name=rancher-backup); do
  kcd $psp
done

# Istio
for psp in istio-installer istio-psp kiali-psp psp-istio-cni; do
  kcd podsecuritypolicy $psp
done

# Get all namespaced resources and delete in loop
# Exclude helm.cattle.io and k3s.cattle.io to not break K3S/RKE2 addons
kubectl get $(kubectl api-resources --namespaced=true --verbs=delete -o name| grep cattle\.io | grep -v helm\.cattle\.io | grep -v k3s\.cattle\.io | tr "\n" "," | sed -e 's/,$//') -A --no-headers -o custom-columns=NAME:.metadata.name,NAMESPACE:.metadata.namespace,KIND:.kind,APIVERSION:.apiVersion | while read NAME NAMESPACE KIND APIVERSION; do
  kcpf -n $NAMESPACE "${KIND}.$(printapiversion $APIVERSION)" $NAME
  kcd -n $NAMESPACE "${KIND}.$(printapiversion $APIVERSION)" $NAME
done

# Logging
kubectl get $(kubectl api-resources --namespaced=true --verbs=delete -o name| grep logging\.banzaicloud\.io | tr "\n" "," | sed -e 's/,$//') -A --no-headers -o custom-columns=NAME:.metadata.name,NAMESPACE:.metadata.namespace,KIND:.kind,APIVERSION:.apiVersion | while read NAME NAMESPACE KIND APIVERSION; do
  kcpf -n $NAMESPACE "${KIND}.$(printapiversion $APIVERSION)" $NAME
  kcd -n $NAMESPACE "${KIND}.$(printapiversion $APIVERSION)" $NAME
done

kubectl get $(kubectl api-resources --namespaced=true --verbs=delete -o name | grep -v events\.events\.k8s\.io | grep -v ^events$ | tr "\n" "," | sed -e 's/,$//') -A --no-headers -o custom-columns=NAME:.metadata.name,NAMESPACE:.metadata.namespace,KIND:.kind,APIVERSION:.apiVersion | grep rancher-monitoring | while read NAME NAMESPACE KIND APIVERSION; do
  kcpf -n $NAMESPACE "${KIND}.$(printapiversion $APIVERSION)" $NAME
  kcd -n $NAMESPACE "${KIND}.$(printapiversion $APIVERSION)" $NAME
done

# Monitoring
kubectl get $(kubectl api-resources --namespaced=true --verbs=delete -o name| grep monitoring\.coreos\.com | tr "\n" "," | sed -e 's/,$//') -A --no-headers -o custom-columns=NAME:.metadata.name,NAMESPACE:.metadata.namespace,KIND:.kind,APIVERSION:.apiVersion | while read NAME NAMESPACE KIND APIVERSION; do
  kcpf -n $NAMESPACE "${KIND}.$(printapiversion $APIVERSION)" $NAME
  kcd -n $NAMESPACE "${KIND}.$(printapiversion $APIVERSION)" $NAME
done

# Gatekeeper
kubectl get $(kubectl api-resources --namespaced=true --verbs=delete -o name| grep gatekeeper\.sh | tr "\n" "," | sed -e 's/,$//') -A --no-headers -o custom-columns=NAME:.metadata.name,NAMESPACE:.metadata.namespace,KIND:.kind,APIVERSION:.apiVersion | while read NAME NAMESPACE KIND APIVERSION; do
  kcpf -n $NAMESPACE "${KIND}.$(printapiversion $APIVERSION)" $NAME
  kcd -n $NAMESPACE "${KIND}.$(printapiversion $APIVERSION)" $NAME
done

# Cluster-api
kubectl get $(kubectl api-resources --namespaced=true --verbs=delete -o name| grep cluster\.x-k8s\.io | tr "\n" "," | sed -e 's/,$//') -A --no-headers -o custom-columns=NAME:.metadata.name,NAMESPACE:.metadata.namespace,KIND:.kind,APIVERSION:.apiVersion | while read NAME NAMESPACE KIND APIVERSION; do
  kcpf -n $NAMESPACE "${KIND}.$(printapiversion $APIVERSION)" $NAME
  kcd -n $NAMESPACE "${KIND}.$(printapiversion $APIVERSION)" $NAME
done

# Get all non-namespaced resources and delete in loop
kubectl get $(kubectl api-resources --namespaced=false --verbs=delete -o name| grep cattle\.io | tr "\n" "," | sed -e 's/,$//') -A --no-headers -o name | while read NAME; do
  kcpf $NAME
  kcd $NAME
done

# Logging
kubectl get $(kubectl api-resources --namespaced=false --verbs=delete -o name| grep logging\.banzaicloud\.io | tr "\n" "," | sed -e 's/,$//') -A --no-headers -o name | while read NAME; do
  kcpf $NAME
  kcd $NAME
done

# Gatekeeper
kubectl get $(kubectl api-resources --namespaced=false --verbs=delete -o name| grep gatekeeper\.sh | tr "\n" "," | sed -e 's/,$//') -A --no-headers -o name | while read NAME; do
  kcpf $NAME
  kcd $NAME
done

# Delete istio certs
for NS in $(kubectl  get ns --no-headers -o custom-columns=NAME:.metadata.name); do
  kcd -n $NS configmap istio-ca-root-cert
done

# Delete all cattle namespaces, including project namespaces (p-),cluster (c-),cluster-fleet and user (user-) namespaces
for NS in $TOOLS_NAMESPACES $FLEET_NAMESPACES $CATTLE_NAMESPACES; do
  kubectl get $(kubectl api-resources --namespaced=true --verbs=delete -o name| tr "\n" "," | sed -e 's/,$//') -n $NS --no-headers -o custom-columns=NAME:.metadata.name,NAMESPACE:.metadata.namespace,KIND:.kind,APIVERSION:.apiVersion | while read NAME NAMESPACE KIND APIVERSION; do
    kcpf -n $NAMESPACE "${KIND}.$(printapiversion $APIVERSION)" $NAME
    kcd -n $NAMESPACE "${KIND}.$(printapiversion $APIVERSION)" $NAME
  done

  kcdns $NS
done

for NS in $(kubectl get namespace --no-headers -o custom-columns=NAME:.metadata.name | grep "^cluster-fleet"); do
  kubectl get $(kubectl api-resources --namespaced=true --verbs=delete -o name| grep -v events\.events\.k8s\.io | grep -v ^events$ | tr "\n" "," | sed -e 's/,$//') -n $NS --no-headers -o custom-columns=NAME:.metadata.name,NAMESPACE:.metadata.namespace,KIND:.kind,APIVERSION:.apiVersion | while read NAME NAMESPACE KIND APIVERSION; do
    kcpf -n $NAMESPACE "${KIND}.$(printapiversion $APIVERSION)" $NAME
    kcd -n $NAMESPACE "${KIND}.$(printapiversion $APIVERSION)" $NAME
  done

  kcdns $NS
done

for NS in $(kubectl get namespace --no-headers -o custom-columns=NAME:.metadata.name | grep "^p-"); do
  kubectl get $(kubectl api-resources --namespaced=true --verbs=delete -o name| grep -v events\.events\.k8s\.io | grep -v ^events$ | tr "\n" "," | sed -e 's/,$//') -n $NS --no-headers -o custom-columns=NAME:.metadata.name,NAMESPACE:.metadata.namespace,KIND:.kind,APIVERSION:.apiVersion | while read NAME NAMESPACE KIND APIVERSION; do
    kcpf -n $NAMESPACE "${KIND}.$(printapiversion $APIVERSION)" $NAME
    kcd -n $NAMESPACE "${KIND}.$(printapiversion $APIVERSION)" $NAME
  done

  kcdns $NS
done

for NS in $(kubectl get namespace --no-headers -o custom-columns=NAME:.metadata.name | grep "^c-"); do
  kubectl get $(kubectl api-resources --namespaced=true --verbs=delete -o name| grep -v events\.events\.k8s\.io | grep -v ^events$ | tr "\n" "," | sed -e 's/,$//') -n $NS --no-headers -o custom-columns=NAME:.metadata.name,NAMESPACE:.metadata.namespace,KIND:.kind,APIVERSION:.apiVersion | while read NAME NAMESPACE KIND APIVERSION; do
    kcpf -n $NAMESPACE "${KIND}.$(printapiversion $APIVERSION)" $NAME
    kcd -n $NAMESPACE "${KIND}.$(printapiversion $APIVERSION)" $NAME
  done

  kcdns $NS
done

for NS in $(kubectl get namespace --no-headers -o custom-columns=NAME:.metadata.name | grep "^user-"); do
  kubectl get $(kubectl api-resources --namespaced=true --verbs=delete -o name| grep -v events\.events\.k8s\.io | grep -v ^events$ | tr "\n" "," | sed -e 's/,$//') -n $NS --no-headers -o custom-columns=NAME:.metadata.name,NAMESPACE:.metadata.namespace,KIND:.kind,APIVERSION:.apiVersion | while read NAME NAMESPACE KIND APIVERSION; do
    kcpf -n $NAMESPACE "${KIND}.$(printapiversion $APIVERSION)" $NAME
    kcd -n $NAMESPACE "${KIND}.$(printapiversion $APIVERSION)" $NAME
  done

  kcdns $NS
done

for NS in $(kubectl get namespace --no-headers -o custom-columns=NAME:.metadata.name | grep "^u-"); do
  kubectl get $(kubectl api-resources --namespaced=true --verbs=delete -o name| grep -v events\.events\.k8s\.io | grep -v ^events$ | tr "\n" "," | sed -e 's/,$//') -n $NS --no-headers -o custom-columns=NAME:.metadata.name,NAMESPACE:.metadata.namespace,KIND:.kind,APIVERSION:.apiVersion | while read NAME NAMESPACE KIND APIVERSION; do
    kcpf -n $NAMESPACE "${KIND}.$(printapiversion $APIVERSION)" $NAME
    kcd -n $NAMESPACE "${KIND}.$(printapiversion $APIVERSION)" $NAME
  done

  kcdns $NS
done

# Delete logging CRDs
for CRD in $(kubectl get crd -o name | grep logging\.banzaicloud\.io); do
  kcd $CRD
done

# Delete monitoring CRDs
for CRD in $(kubectl get crd -o name | grep monitoring\.coreos\.com); do
  kcd $CRD
done

# Delete OPA CRDs
for CRD in $(kubectl get crd -o name | grep gatekeeper\.sh); do
  kcd $CRD
done

# Delete Istio CRDs
for CRD in $(kubectl get crd -o name | grep istio\.io); do
  kcd $CRD
done

# Delete cluster-api CRDs
for CRD in $(kubectl get crd -o name | grep cluster\.x-k8s\.io); do
  kcd $CRD
done

# Delete all cattle CRDs
# Exclude helm.cattle.io and addons.k3s.cattle.io to not break RKE2 addons
for CRD in $(kubectl get crd -o name | grep cattle\.io | grep -v helm\.cattle\.io | grep -v k3s\.cattle\.io); do
  kcd $CRD
done
