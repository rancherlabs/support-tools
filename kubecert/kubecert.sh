#!/bin/bash
if hash tput 2>/dev/null; then
    red=$(tput setaf 1)
    green=$(tput setaf 2)
    reset=$(tput sgr0)
fi
function grecho() {
    echo "${green}$1${reset}"
}
function recho() {
    echo "${red}$1${reset}"
}
TMPDIR=$(mktemp -d)
SAVE_KUBECONFIG="save"
export PATH=${PATH}:${TMPDIR}

function helpmenu() {
    echo "Usage: ./kubecert.sh [-y]
-y  When specified kubecert.sh will automatically install kubectl and jq
"
    exit 1
}
while getopts "hy" opt; do
    case ${opt} in
    h) # process option h
        helpmenu
        ;;
    y) # process option y
        INSTALL_MISSING_DEPENDENCIES=yes
        ;;
    \?)
        helpmenu
        exit 1
        ;;
    esac
done

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root"
    exit 1
fi
function checkpipecmd() {
    RC=("${PIPESTATUS[@]}")
    if [[ "$2" != "" ]]; then
        PIPEINDEX=$2
    else
        PIPEINDEX=0
    fi
    if [ "${RC[${PIPEINDEX}]}" != "0" ]; then
        echo "${green}$1${reset}"
        exit 1
    fi
}
function download() {
    if [[ "${DOWNLOADCMD}" == "wget" ]]; then
        wget $*
    else
        curl -LO $*
    fi
}

function curlcmd() {
    if [[ "${CURLCMD}" == "curl" ]]; then
        curl "$@"
    else
        docker run --rm -ti patrick0057/curl "$@" | tr -d '\r'
    fi
}
if ! hash curl 2>/dev/null && [[ "${INSTALL_MISSING_DEPENDENCIES}" == "yes" ]]; then
    if [[ -f /etc/redhat-release ]]; then
        OS=redhat
        grecho "You are using Red Hat based linux, installing curl with yum since you passed -y"
        yum install -y curl
        export CURLCMD='curl'
    elif [[ -f /etc/lsb_release ]]; then
        OS=ubuntu
        grecho "You are using Debian/Ubuntu based linux, installing curl with apt since you passed -y"
        apt update && apt install -y curl
        export CURLCMD='curl'
    elif hash docker 2>/dev/null && [[ ! -f /etc/lsb_release ]] && [[ ! -f /etc/lsb_release ]]; then
        grecho "No curl executable found but we can run curl from a docker container instead and use wget for downloads."
        export CURLCMD='docker run --rm -ti patrick0057/curl'
        export DOWNLOADCMD='wget'
    fi
else
    export CURLCMD='curl'
fi
if ! hash curl 2>/dev/null; then
    if hash docker 2>/dev/null; then
        grecho "No curl executable found but we can run curl from a docker container instead and use wget for downloads."
        export CURLCMD='docker run --rm -ti patrick0057/curl'
        export DOWNLOADCMD='wget'
    else
        grecho '!!!curl was not found!!!'
        grecho 'Please install curl if you want to automatically install missing dependencies'
        exit 1
    fi
fi

if ! hash wget 2>/dev/null && [[ "${DOWNLOADCMD}" == "wget" ]]; then
    grecho '!!!wget was not found!!!'
    grecho 'Sorry no auto install for this one, please use your package manager.'
    exit 1
fi
if ! hash jq 2>/dev/null; then
    if [ "${INSTALL_MISSING_DEPENDENCIES}" == "yes" ] && [ "${OSTYPE}" == "linux-gnu" ]; then
        curl -L -O https://github.com/patrick0057/kubecert/raw/master/jq-linux64
        chmod +x jq-linux64
        mv jq-linux64 /bin/jq
    else
        echo '!!!jq was not found!!!'
        echo "!!!download and install with:"
        echo "Linux users (Run script with option -y to install automatically):"
        echo "curl -L -O https://github.com/patrick0057/kubecert/raw/master/jq-linux64"
        echo "chmod +x jq-linux64"
        echo "mv jq-linux64 /bin/jq"
        exit 1
    fi
fi
#Install kubectl if we're applying the cluster yaml and if we have passed -y to automatically install dependencies
if ! hash kubectl 2>/dev/null; then
    if [ "${INSTALL_MISSING_DEPENDENCIES}" == "yes" ]; then
        if [ "${OSTYPE}" == "linux-gnu" ] || [ "${OSTYPE}" == "linux" ]; then
            recho "Installing kubectl..."
            download "https://storage.googleapis.com/kubernetes-release/release/$(curlcmd -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl"
            if [ "${LOCALBINARY}" != "yes" ]; then
                install -o root -g root -m 755 kubectl /bin/kubectl
            else
                install -o root -g root -m 755 kubectl ${TMPDIR}/kubectl
                echo to use kubectl from tmp, you need to export ${TMPDIR} into your path as shown below.
                echo "export PATH=\${PATH}:${TMPDIR}"
            fi
        else
            grecho "!!!kubectl was not found!!!"
            grecho "!!!download and install with:"
            grecho "Linux users (Run script with option -y to install automatically):"
            grecho "curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl"
            grecho "chmod +x ./kubectl"
            grecho "mv ./kubectl /bin/kubectl"
            exit 1
        fi
    fi
fi

if ! hash sed 2>/dev/null; then
    echo '!!!sed was not found!!!'
    echo 'Sorry no auto install for this one, please use your package manager.'
    exit 1
fi
if ! hash base64 2>/dev/null; then
    if [ "${INSTALL_MISSING_DEPENDENCIES}" == "yes" ]; then
        echo '!!!base64 was not found!!!'
        download https://github.com/patrick0057/kubecert/raw/master/base64
        mv base64 $TMPDIR
    else
        echo '!!!base64 was not found!!!'
        echo 'You can download it from https://github.com/patrick0057/kubecert/raw/master/base64 manually and put it in your path or pass -y to auto install.'
        exit 1
    fi
fi

SSLDIRPREFIX=$(docker inspect kubelet --format '{{ range .Mounts }}{{ if eq .Destination "/etc/kubernetes" }}{{ .Source }}{{ end }}{{ end }}')
if [ "$?" != "0" ]; then
    echo "${green}Failed to get SSL directory prefix, aborting script!${reset}"
    exit 1
fi
function setusupthekubeconfig() {
    recho "Generating kube config for the local cluster"
    if [[ "${MANUALSSLPREFIX}" == "" ]]; then
        SSLDIRPREFIX=$(docker inspect kubelet --format '{{ range .Mounts }}{{ if eq .Destination "/etc/kubernetes" }}{{ .Source }}{{ end }}{{ end }}')
        if [ "$?" != "0" ]; then
            grecho "Failed to get SSL directory prefix in order to generate the KUBECONFIG, aborting script!  If you know what the prefix is you can manually pass it with -z.  This is usually /etc/kubernetes/."
            exit 1
        fi
    else
        SSLDIRPREFIX=${MANUALSSLPREFIX}
    fi
    cp -arfv ${SSLDIRPREFIX}/ssl/kubecfg-kube-node.yaml ${TMPDIR}/kubecfg-kube-node.yaml
    if [ -d "/opt/rke/etc/kubernetes/" ]; then
        sed -r -i 's,/etc/kubernetes,/opt/rke/etc/kubernetes/,g' ${TMPDIR}/kubecfg-kube-node.yaml
    fi
    K_RESULT=$(kubectl --insecure-skip-tls-verify --kubeconfig ${TMPDIR}/kubecfg-kube-node.yaml get configmap -n kube-system full-cluster-state -o json 2>&1)
    if [ "$?" == "0" ]; then
        grecho "Deployed with RKE 0.2.x and newer, grabbing kubeconfig"
        kubectl --insecure-skip-tls-verify --kubeconfig ${TMPDIR}/kubecfg-kube-node.yaml get configmap -n kube-system full-cluster-state -o json | jq -r .data.\"full-cluster-state\" | jq -r .currentState.certificatesBundle.\"kube-admin\".config | sed -e "/^[[:space:]]*server:/ s_:.*_: \"https://127.0.0.1:6443\"_" | sed -e "/^[[:space:]]*server:/ s_:.*_: \"https://127.0.0.1:6443\"_" >${TMPDIR}/kubeconfig
    else
        K_ERROR1=${K_RESULT}
    fi
    K_RESULT=$(kubectl --insecure-skip-tls-verify --kubeconfig ${TMPDIR}/kubecfg-kube-node.yaml get secret -n kube-system kube-admin -o jsonpath={.data.Config} 2>&1)
    if [ "$?" == "0" ]; then
        grecho "Deployed with RKE 0.1.x and older, grabbing kubeconfig"
        kubectl --insecure-skip-tls-verify --kubeconfig ${TMPDIR}/kubecfg-kube-node.yaml get secret -n kube-system kube-admin -o jsonpath={.data.Config} | base64 -d | sed 's/[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}/127.0.0.1/g' >${TMPDIR}/kubeconfig
    else
        K_ERROR2=${K_RESULT}
    fi
    if [[ "${K_ERROR1}" != "" ]] && [[ "${K_ERROR2}" != "" ]]; then
        grecho "kubectl command used to generate new kubectl command failed.  Your cluster certs might be expired.  Printing error below."
        grecho "One will be an error for an attempt against the wrong RKE version and the other will be your actual reason for failure."
        echo
        grecho "Error #1"
        echo ${K_ERROR1}
        echo
        grecho "Error #2"
        echo ${K_ERROR2}
        exit 1
    fi
    if [ ! -f ${TMPDIR}/kubeconfig ]; then
        recho "${TMPDIR}/kubeconfig does not exist, script aborting due to kubeconfig generation failure."
        exit 1
    fi
    export KUBECONFIG=${TMPDIR}/kubeconfig
    grecho "Demonstrating kubectl works..."
    kubectl --kubeconfig ${KUBECONFIG} get node
    checkpipecmd "kubectl demonstration failed, aborting script!"
    if [[ "${SAVE_KUBECONFIG}" == "save" ]]; then
        mkdir -p ~/.kube/
        KUBEBACKUP="~/.kube/config-$(date +%Y-%m-%d--%H%M%S)"
        FILE="~/.kube/config"
        #expand full path
        eval FILE=${FILE}
        eval KUBEBACKUP=${KUBEBACKUP}

        if [[ -f "${FILE}" ]]; then
            recho "Backing up ${FILE} to ${KUBEBACKUP}"
            mv ${FILE} ${KUBEBACKUP}
        fi

        recho "Copying generated kube config in place"
        cp -afv ${TMPDIR}/kubeconfig ${FILE}

    fi

}

echo "${red}Generating kube config for the local cluster${reset}"
setusupthekubeconfig

echo "${green}Demonstrating kubectl works...${reset}"
kubectl get node
echo
echo "${green}Script has completed, kubectl should now be working for the local cluster on this node.${reset}"
