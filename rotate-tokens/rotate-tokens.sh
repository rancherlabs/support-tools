#!/bin/bash -e

if [ -n "$DEBUG" ]
then
    set -x
fi

usage() {
    echo 'TOKEN=<token> KUBECONFIG=</path/to/local/kubeconfig> RANCHER_SERVER=<https://rancher.server> ./rotate-tokens.sh'
    exit 0
}

if [ "$1" == "help" ]
then
    usage
fi

if [ "$TOKEN" == "" ]
then
    echo 'Create an API token in the Rancher UI and set the environment variable TOKEN before running this script.'
    exit 1
fi

if [ "$RANCHER_SERVER" == "" ]
then
    echo 'Set $RANCHER_SERVER to point to the Rancher URL.'
    exit 1
fi

if curl --insecure -s -u $TOKEN "${RANCHER_SERVER}/v3" | grep Unauthorized >/dev/null
then
    echo "Not authorized for Rancher server $RANCHER_SERVER."
    exit 1
fi

if ! which kubectl >/dev/null
then
    echo 'kubectl and jq must be installed.'
    exit 1
fi

if ! which jq >/dev/null
then
    echo 'kubectl and jq must be installed.'
    exit 1
fi

if ! kubectl get namespace cattle-global-data >/dev/null 2>&1
then
    echo 'Set $KUBECONFIG to point to the Rancher local cluster.'
    exit 1
fi

cleanup() {
    kubectl --namespace cattle-system patch deployment cattle-cluster-agent --patch '{"spec": {"template": {"spec": {"serviceAccount": "cattle", "serviceAccountName": "cattle"}}}}'
    kubectl --namespace cattle-system rollout status deployment cattle-cluster-agent
    kubectl --namespace cattle-system delete serviceaccount cattle-tmp >/dev/null 2>&1 || true
    kubectl --namespace cattle-system delete secret cattle-tmp-token >/dev/null 2>&1 || true
    kubectl delete clusterrolebinding cattle-admin-binding-tmp >/dev/null 2>&1 || true
    rm -f .error
}

create_token_secret() {
    name=$1
    uid=$2
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Secret
metadata:
  name: $name-token
  namespace: cattle-system
  annotations:
    kubernetes.io/service-account.name: $name
    kubernetes.io/service-account.uid: $uid
type: kubernetes.io/service-account-token
EOF
}

create_cluster_secret() {
    cluster=$1
    uid=$2
    token=$3
    secret=$(cat <<EOF | kubectl create --output jsonpath='{.metadata.name}' -f -
apiVersion: v1
kind: Secret
metadata:
  generateName: cluster-serviceaccounttoken-
  namespace: cattle-global-data
  ownerReferences:
  - apiVersion: management.cattle.io/v3
    kind: Cluster
    name: $cluster
    uid: $uid
data:
  credential: $token
type: opaque
EOF
    )
    echo $secret
}

clusters=$(kubectl get clusters.management --output jsonpath='{.items[?(.metadata.name != "local")].metadata.name}')

mkdir -p kubeconfigs

MAIN_KUBECONFIG=$KUBECONFIG # may be empty, then default kubeconfig is used

for c in $clusters
do
    echo "Rotating service account for cluster $c..."
    kubeconfig=$(curl --insecure -s -u $TOKEN \
        -X POST \
        -H 'Accept: application/json' \
        -H 'Content-Type: application/json' \
        -d '{}' \
        "$RANCHER_SERVER/v3/clusters/${c}?action=generateKubeconfig" | jq -r .config)
    echo "$kubeconfig" > kubeconfigs/${c}.config
    KUBECONFIG=kubeconfigs/${c}.config

    # create temporary admin account
    tmpuid=$(kubectl --namespace cattle-system create serviceaccount cattle-tmp --output jsonpath='{.metadata.uid}' 2>.error || true)
    if [ -s .error ]
    then
        if grep 'already exists' .error >/dev/null
        then
            tmpuid=$(kubectl --namespace cattle-system get serviceaccount cattle-tmp --output jsonpath='{.metadata.uid}')
        else
            cat .error
            rm .error
            exit 1
        fi
        rm .error
    fi
    create_token_secret cattle-tmp $tmpuid
    kubectl create clusterrolebinding --clusterrole cattle-admin --serviceaccount cattle-system:cattle-tmp cattle-admin-binding-tmp 2>.error || true
    if [ -s .error ]
    then
        if ! grep 'already exists' .error >/dev/null
        then
            cat .error
            rm .error
            exit 1
        fi
        rm .error
    fi
    token=$(kubectl --namespace cattle-system get secret cattle-tmp-token --output jsonpath='{.data.token}')
    kubectl --namespace cattle-system patch deployment cattle-cluster-agent --patch '{"spec": {"template": {"spec": {"serviceAccount": "cattle-tmp", "serviceAccountName": "cattle-tmp"}}}}'
    kubectl --namespace cattle-system rollout status deployment cattle-cluster-agent

    # set cluster to use temporary account
    KUBECONFIG=$MAIN_KUBECONFIG
    old_secret=$(kubectl get clusters.management $c --output jsonpath='{.status.serviceAccountTokenSecret}')
    cluster_uid=$(kubectl get clusters.management $c --output jsonpath='{.metadata.uid}')
    secret=$(create_cluster_secret $c $cluster_uid $token)
    kubectl patch clusters.management $c --patch '{"status": {"serviceAccountTokenSecret": "'$secret'"}}' --type=merge
    kubectl --namespace cattle-global-data delete secret $old_secret

    # regenerate service account and secret
    KUBECONFIG=kubeconfigs/${c}.config
    if kubectl --namespace cattle-system get serviceaccount kontainer-engine >/dev/null 2>&1
    then
        serviceaccount=kontainer-engine
    elif kubectl --namespace cattle-system get serviceaccount cattle >/dev/null 2>&1
    then
        serviceaccount=cattle
    else
        echo "could not find admin service account to rotate on cluster $c"
        exit 1
    fi
    # 2.6 creates its own token
    if kubectl --namespace cattle-system get secret $serviceaccount-token >/dev/null 2>&1
    then
        kubectl --namespace cattle-system delete serviceaccount $serviceaccount
        uid=$(kubectl --namespace cattle-system create serviceaccount $serviceaccount --output jsonpath='{.metadata.uid}')
        create_token_secret $serviceaccount $uid
        tokensecret=$serviceaccount-token
    # 2.5 uses the k8s-generated token
    else
        kubectl --namespace cattle-system delete serviceaccount $serviceaccount
        kubectl --namespace cattle-system create serviceaccount $serviceaccount
        tokensecret=$(kubectl --namespace cattle-system get serviceaccount $serviceaccount --output jsonpath='{.secrets[0].name}')
    fi
    # restore back to old account
    token=$(kubectl --namespace cattle-system get secret $tokensecret --output jsonpath='{.data.token}')
    KUBECONFIG=$MAIN_KUBECONFIG
    secret=$(create_cluster_secret $c $cluster_uid $token)
    kubectl patch clusters.management $c --patch '{"status": {"serviceAccountTokenSecret": "'$secret'"}}' --type=merge

    # cleanup temporary artifacts
    KUBECONFIG=kubeconfigs/${c}.config
    cleanup
done
