#!/bin/bash
if hash tput 2>/dev/null; then
    red=$(tput setaf 1)
    green=$(tput setaf 2)
    reset=$(tput sgr0)
fi
TMPDIR=$(mktemp -d)
export PATH=${PATH}:${TMPDIR}
#UNAME=${uname-r}
function grecho() {
    echo "${green}$1${reset}"
}
function recho() {
    echo "${red}$1${reset}"
}

#START_TIME=$(date +%Y-%m-%d--%H%M%S)
SCRIPT_NAME="cluster-agent-tool.sh"
# Login token good for 1 minute
TOKEN_TTL=60000

function helpmenu() {
    grecho "This script will help you retrieve redeployment commands for rancher agents as well as docker run commands to start new agent containers.  Depending on the options specified below you can also have the script automatically run these commands for you.


Usage: bash ${SCRIPT_NAME}
    -h              Shows this help menu

    -y              Automatically installs dependencies for you.   (Recommended)

    -f              Automatically says yes to any questions asked by the script.  (Optional)

    -l              Local binaries for kubectl and jq (installs to /tmp/). (Optional)

    -a ['save']     Automatically applies cluster YAML for you.  This will also generate a kube config for your local cluster.  If you want to use the config file after the script has completed pass 'save' as shown below to save the kube config to ~/.kube/config.  (Optional)
            Example: -a'save'

    -r <roles>      Automatically runs rancher agent for you.  (Optional)
            Use one or more of the following roles: --etcd --controlplane --worker
            Example: -r'--etcd --controlplane --worker'

    -u <username>   Set username to log into rancher cluster with.  If -u is not passed then we will use \"admin\" by default.  (Optional)
            Example: -u'bob'

    -p <password>   Set password on command line to log into rancher cluster with.  If -p is not passed then we will prompt you with a password prompt to obscure your password.  (Optional)
            Example: -p'qwerty'

    -t <token>      Set bearer token which can be received from the web interface.  (Recommended)
            Example: -t'token-s62xz:9m86wn8tzx8xvxdvm79jgmhp9x57cbc5btsm8hv3qjjtxrlfz4vh22'

    -s <cattleURL>  Set Rancher url used to access your installation.  If -s is not passed then we will try to automatically detect the URL for you based on the local cluster installed on this node.  (Optional)
            Example -s'https://rancher.company.com'

    -c <clusterID>  Manually set cluster ID for this cluster.  If -c is not passed then we will automatically detect the cluster ID for you based on the local cluster installed on this node.  If you are running this on an rke deployed local rancher cluster you need to pass this option as -c'local'.  (Optional)
            Example: -c'c-xkxh6'

    -k <kubecfg>    Manually set the full path to your kube config instead of generating one for you.  (Optional)
            Example: -k'/home/bob/.kube/config'
    
    -z <sslprefix>  Set this if kube config generation fails because it can't lookup your sslprefix.  This is usually /etc/kubernetes/.
            Example: -z'/etc/kubernetes/'
"
    exit 1
}
while getopts "hlyfz:k:a:u:t:p:s:c:r:" opt; do
    case ${opt} in
    h) # process option h
        helpmenu
        ;;
    y) # process option y: auto install dependencies
        INSTALL_MISSING_DEPENDENCIES=yes
        if [[ "${EUID}" -ne 0 ]]; then
            grecho "In order to automatically install dependencies please run this script as root."
            exit 1
        fi
        ;;
    a) # process option a: automatically apply yaml
        APPLY_YAML="yes"
        SAVE_KUBECONFIG="${OPTARG}"
        if [[ ! ${SAVE_KUBECONFIG} == "save" ]]; then
            grecho "You specified -a without 'save', please pass -a'save' instead."
            echo
            helpmenu
        fi
        ;;
    f) # process option f: automatically answer yes to all questions
        AUTOYES="yes"
        ;;
    l) # process option l: local binary
        LOCALBINARY="yes"
        ;;
    r) # process option r: run agent command on node
        RUN_AGENT="yes"
        AGENT_OPTIONS="${OPTARG}"
        if [[ "${AGENT_OPTIONS}" == "" ]]; then
            grecho "You specified -r but did not provide any roles to be run with.  Please add some of or all of the following roles surrounded by double quotes.
            --etcd --controlplane --worker
            Example: -a \"--etcd --controlplane\""
            helpmenu
        fi
        RUN_ARRAY=("${AGENT_OPTIONS}")
        for ((i = 0; i < ${#RUN_ARRAY[@]}; i++)); do
            if [[ "${RUN_ARRAY[$i]}" != "--etcd" ]] && [[ "${RUN_ARRAY[$i]}" != "--controlplane" ]] && [[ "${RUN_ARRAY[$i]}" != "--worker" ]]; then
                grecho "You passed an invalid node role.  Listing what you specified below."
                echo "${AGENT_OPTIONS}"
                echo
                grecho "Valid options are: --etcd --controlplane --worker"
                exit 1
            fi
        done
        ;;
    u) # process option u: set username
        RANCHER_USERNAME=${OPTARG}
        if [[ "${RANCHER_USERNAME}" == "" ]]; then
            grecho "You specified -u but did not supply a username."
            echo
            helpmenu
        fi
        ;;
    p) # process option p: set password
        PASSWORD=${OPTARG}
        ;;
    t) # process option t: set password
        LOGINTOKEN=${OPTARG}
        if [[ "${LOGINTOKEN}" == "" ]]; then
            grecho "You specified -t but did not supply a bearer token."
            echo
            helpmenu
        fi
        ;;
    s) # process option s: set CATTLE_SERVER
        CATTLE_SERVER_INPUT=${OPTARG}
        DOMAIN_REGEX='^(http[s]?:\/\/)?([a-zA-Z0-9\._-]+)(\/?).*$'
        if [[ "${CATTLE_SERVER_INPUT}" == "" ]]; then
            grecho "You specified -s but did not supply a rancher server URL."
            echo
            helpmenu
        elif [[ "${CATTLE_SERVER_INPUT}" =~ ${DOMAIN_REGEX} ]]; then
            URL_PROTOCOL="${BASH_REMATCH[1]}"
            URL_HOSTNAME="${BASH_REMATCH[2]}"
            #echo here is your regex match 0
            #echo "${BASH_REMATCH[0]}"
            #echo here is your regex match 1
            #echo "${BASH_REMATCH[1]}"
            #echo here is your regex match 2
            #echo "${BASH_REMATCH[2]}"
            if [[ -z "${URL_PROTOCOL}" ]]; then
                recho "Setting your URL protocol to https:// since it was not specified in option -s."
                URL_PROTOCOL="http://"
            fi
            CATTLE_SERVER="${URL_PROTOCOL}${URL_HOSTNAME}"
            echo "Your URL has been set to ${CATTLE_SERVER}"
            else
                grecho "Could not determine URL based on information provided in option -s"
                exit 1
        fi
        ;;
    c) # process option c: set CLUSTERID
        CLUSTERID=${OPTARG}
        if [[ "${CLUSTERID}" == "" ]]; then
            grecho "You specified -c but did not supply a cluster ID."
            echo
            helpmenu
        fi
        ;;
    k) # process option k: set KUBECONFIG
        export KUBECONFIG=${OPTARG}
        MANUAL_KUBECONFIG=yes
        if [[ "${KUBECONFIG}" == "" ]]; then
            grecho "You specified -k but did not supply a kube config path."
            echo
            helpmenu
        fi
        ;;
    z) # process option z: set SSLPREFIX path
        MANUALSSLPREFIX=${OPTARG}
        if [[ "${MANUALSSLPREFIX}" == "" ]]; then
            grecho "You specified -z but did not supply an ssl prefix path.  This is usually /etc/kubernetes/."
            echo
            helpmenu
        fi
        ;;
    \?)
        helpmenu
        exit 1
        ;;
    esac
done
function yesno() {
    shopt -s nocasematch
    response=''
    i=0
    if [[ $AUTOYES == "yes" ]]; then
        response='y'
    fi
    while [[ "${response}" != 'y' ]] && [[ "${response}" != 'n' ]]; do
        i=$((i + 1))
        if [ $i -gt 10 ]; then
            grecho "Script is destined to loop forever, aborting!  Make sure your docker run command has -ti then try again."
            exit 1
        fi
        printf '(y/n): '
        read -r -n1 response
        echo
    done
    shopt -u nocasematch
}
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
function checknullvar() {
    if [[ -z "$1" ]] || [[ "$1" == "null" ]]; then
        echo "${green}$2${reset}"
        #quit script if command is asked to on failure
        if [[ "$3" == "exit1" ]]; then
            exit 1
        fi
    fi
}
function checkcurlreturn() {
    REGEX='{"type":"error","status":"401","message":"must authenticate"}'
    if [[ "$1" == "${REGEX}" ]]; then
        grecho "Authentication failed, did you use the correct Bearer Token or username and password?"
        exit 1
    fi
    REGEX="default backend - 404"
    if [[ "$1" == "${REGEX}" ]]; then
        grecho "The Rancher server-url is returning default backend.  Check your server-url and try again."
        exit 1
    fi
}
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
    cp -arfv "${SSLDIRPREFIX}"/ssl/kubecfg-kube-node.yaml "${TMPDIR}"/kubecfg-kube-node.yaml
    if [ -d "/opt/rke/etc/kubernetes/" ]; then
        sed -r -i 's,/etc/kubernetes,/opt/rke/etc/kubernetes/,g' "${TMPDIR}"/kubecfg-kube-node.yaml
    fi
    K_RESULT=$(kubectl --insecure-skip-tls-verify --kubeconfig "${TMPDIR}"/kubecfg-kube-node.yaml get configmap -n kube-system full-cluster-state -o json 2>&1)
    if [ "$?" == "0" ]; then
        grecho "Deployed with RKE 0.2.x and newer, grabbing kubeconfig"
        kubectl --insecure-skip-tls-verify --kubeconfig "${TMPDIR}"/kubecfg-kube-node.yaml get configmap -n kube-system full-cluster-state -o json | jq -r .data.\"full-cluster-state\" | jq -r .currentState.certificatesBundle.\"kube-admin\".config | sed -e "/^[[:space:]]*server:/ s_:.*_: \"https://127.0.0.1:6443\"_" | sed -e "/^[[:space:]]*server:/ s_:.*_: \"https://127.0.0.1:6443\"_" >${TMPDIR}/kubeconfig
    else
        K_ERROR1="${K_RESULT}"
    fi
    K_RESULT=$(kubectl --insecure-skip-tls-verify --kubeconfig "${TMPDIR}"/kubecfg-kube-node.yaml get secret -n kube-system kube-admin -o jsonpath='{.data.Config}' 2>&1)
    if [ "$?" == "0" ]; then
        grecho "Deployed with RKE 0.1.x and older, grabbing kubeconfig"
        kubectl --insecure-skip-tls-verify --kubeconfig "${TMPDIR}"/kubecfg-kube-node.yaml get secret -n kube-system kube-admin -o jsonpath='{.data.Config}' | base64 -d | sed 's/[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}/127.0.0.1/g' >${TMPDIR}/kubeconfig
    else
        K_ERROR2=${K_RESULT}
    fi
    if [[ "${K_ERROR1}" != "" ]] && [[ "${K_ERROR2}" != "" ]]; then
        grecho "kubectl command used to generate new kubectl command failed.  Your cluster certs might be expired.  Printing error below."
        grecho "One will be an error for an attempt against the wrong RKE version and the other will be your actual reason for failure."
        echo
        grecho "Error #1"
        echo "${K_ERROR1}"
        echo
        grecho "Error #2"
        echo "${K_ERROR2}"
        exit 1
    fi
    if [ ! -f "${TMPDIR}"/kubeconfig ]; then
        recho "${TMPDIR}/kubeconfig does not exist, script aborting due to kubeconfig generation failure."
        exit 1
    fi
    export KUBECONFIG="${TMPDIR}/kubeconfig"
    grecho "Demonstrating kubectl works..."
    kubectl --kubeconfig "${KUBECONFIG}" get node
    checkpipecmd "kubectl demonstration failed, aborting script!"
    if [[ "${SAVE_KUBECONFIG}" == "save" ]]; then
        mkdir -p ~/.kube/
        KUBEBACKUP="${HOME}/.kube/config-$(date +%Y-%m-%d--%H%M%S)"
        FILE="${HOME}/.kube/config"

        if [[ -f "${FILE}" ]]; then
            recho "Backing up ${FILE} to ${KUBEBACKUP}"
            mv "${FILE}" "${KUBEBACKUP}"
        fi

        recho "Copying generated kube config in place"
        cp -afv "${TMPDIR}/kubeconfig" "${FILE}"

    fi

}
function download() {
    if [[ "${DOWNLOADCMD}" == "wget" ]]; then
        wget "$*"
    else
        curl -LO "$*"
    fi
}

function curlcmd() {
    if [[ "${CURLCMD}" == "curl" ]]; then
        curl "$@"
    else
        docker run --rm -ti patrick0057/curl "$@" | tr -d '\r'
    fi
}
if [[ "${PASSWORD}" == "" ]] && [[ -z "${LOGINTOKEN}" ]]; then
    grecho "You did not specify a password and option -t was not used to supply a Bearer Token."
    echo
    helpmenu
fi


if ! hash curl 2>/dev/null && [[ "${INSTALL_MISSING_DEPENDENCIES}" == "yes" ]]; then
    if [[ -f /etc/redhat-release ]]; then
        export OS=redhat
        grecho "You are using Red Hat based linux, installing curl with yum since you passed -y"
        yum install -y curl
        export CURLCMD='curl'
    elif [[ -f /etc/lsb_release ]]; then
        export OS=ubuntu
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
#Install kubectl if we're applying the cluster yaml and if we have passed -y to automatically install dependencies
if ! hash kubectl 2>/dev/null && [[ "${APPLY_YAML}" == "yes" ]]; then
    if [ "${INSTALL_MISSING_DEPENDENCIES}" == "yes" ] && [ "${OSTYPE}" == "linux-gnu" ]; then
        recho "Installing kubectl..."
        download "https://storage.googleapis.com/kubernetes-release/release/$(curlcmd -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl"
        if [ "${LOCALBINARY}" != "yes" ]; then
            install -o root -g root -m 755 kubectl /bin/kubectl
        else
            install -o root -g root -m 755 kubectl ${TMPDIR}/kubectl
            grecho to use kubectl from tmp, you need to export ${TMPDIR} into your path as shown below.
            grecho "export PATH=\${PATH}:${TMPDIR}"
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

if ! hash jq 2>/dev/null; then
    if [ "${INSTALL_MISSING_DEPENDENCIES}" == "yes" ] && [ "${OSTYPE}" == "linux-gnu" ]; then
        recho "Installing jq..."
        download https://github.com/patrick0057/jq/releases/download/jq-1.6/jq-linux64
        if [ "${LOCALBINARY}" != "yes" ]; then
            install -o root -g root -m 755 jq-linux64 /bin/jq
        else
            install -o root -g root -m 755 jq-linux64 ${TMPDIR}/jq
            grecho to use jq from tmp, you need to export ${TMPDIR} into your path as shown below.
            grecho "export PATH=\${PATH}:${TMPDIR}"
        fi

    else
        grecho '!!!jq was not found!!!'
        grecho "!!!download and install with:"
        grecho "Linux users (Run script with option -y to install automatically):"
        grecho "curl -L -O https://github.com/patrick0057/jq/releases/download/jq-1.6/jq-linux64"
        grecho "chmod +x jq-linux64"
        grecho "mv jq-linux64 /bin/jq"
        exit 1
    fi
fi
if ! hash base64 2>/dev/null; then
    if [ "${INSTALL_MISSING_DEPENDENCIES}" == "yes" ]; then
        echo '!!!base64 was not found!!!'
        download https://github.com/patrick0057/kubecert/raw/master/base64
        chmod +x base64
        mv base64 "$TMPDIR"
    else
        echo '!!!base64 was not found!!!'
        echo 'You can download it from https://github.com/patrick0057/kubecert/raw/master/base64 manually and put it in your path or pass -y to auto install.'
        exit 1
    fi
fi
DEPENDENCIES="sed grep ip tr date cut"
for CMD in ${DEPENDENCIES}; do
    hash "${CMD}" 2>/dev/null
    if [[ "$?" == "1" ]]; then
        grecho "${CMD} was not found, please install with your package manager"
        EXIT="exit 1"
    fi
    #Quit script if any other above matched, but let it finish reporting before doing so.
    ${EXIT}
done

#Auto set RANCHER_USERNAME if none was specified
if [[ "${RANCHER_USERNAME}" == "" ]]; then
    RANCHER_USERNAME='admin'
fi

#Prompt for PASSWORD if none was specified
if [[ "${PASSWORD}" == "" ]] && [[ ${LOGINTOKEN// /} == "" ]]; then
    echo -n "${green}Password: ${reset}"
    read -r -s PASSWORD
    echo
fi

#get default route interface
DEFAULT_ROUTE_IFACE=$(ip route | grep default | cut -d' ' -f5)
#Get local IP for determining cluster ID
DEFAULT_IP="$(ip a show ${DEFAULT_ROUTE_IFACE} | grep inet | grep -v inet6 | awk '{print $2}' | cut -f1 -d'/')"

if [[ "${CATTLE_SERVER}" == "" ]]; then
    #get cattle node agent ID for docker inspect
    CATTLE_NODE_AGENT_ID=$(docker ps | grep -i k8s_agent_cattle-node-agent | cut -d' ' -f1)
    #get CATTLE_SERVER
    eval "$(docker inspect ${CATTLE_NODE_AGENT_ID} --format '{{range $index, $value := .Config.Env}}{{println $value}}{{end}}' | grep CATTLE_SERVER=)"
    checkpipecmd "Unable to determine CATTLE_SERVER on my own, please specify CATTLE_SERVER manually with -s."
    checknullvar "${CATTLE_SERVER}" "Unable to determine CATTLE_SERVER on my own, please specify CATTLE_SERVER manually with -s." "exit1"
fi

#remove spaces
CATTLE_SERVER="${CATTLE_SERVER// /}"
#remove trailing //
CATTLE_SERVER=$(sed 's:/*$::' <<<$CATTLE_SERVER)

#Get a temporary login token
if [[ ${LOGINTOKEN// /} == "" ]]; then
    LOGINTOKEN=$(curlcmd -k -s ''${CATTLE_SERVER}'/v3-public/localProviders/local?action=login' -H 'content-type: application/json' --data-binary '{"username":'\"${RANCHER_USERNAME}\"',"password":'\"${PASSWORD}\"',"ttl":'${TOKEN_TTL}'}' | jq -r .token)
    checkpipecmd "Unable to get LOGINTOKEN, did you use the correct username and password?"
    checkcurlreturn "${LOGINTOKEN}"
    checknullvar "${LOGINTOKEN}" "Unable to get LOGINTOKEN, did you use the correct username and password?" "exit1"
fi

if [[ "${CLUSTERID}" == "" ]]; then
    #store /v3/clusters output
    CLUSTERS=$(curlcmd -k -s "${CATTLE_SERVER}/v3/clusters" -H "content-type: application/json" -H "Authorization: Bearer ${LOGINTOKEN}")
    checkpipecmd "Unable to load ${CATTLE_SERVER}/v3/clusters on my own."
    checkcurlreturn "${CLUSTERS}"
    #Store nodeId
    NODEID=$(jq -r '.data[]?.appliedSpec.rancherKubernetesEngineConfig.nodes[]? | select(.address == '\"${DEFAULT_IP}\"') | .nodeId' <<<${CLUSTERS})
    if [[ ${NODEID// /} == "" ]]; then
        NODEID=$(jq -r '.data[]?.appliedSpec.rancherKubernetesEngineConfig.nodes[]? | select(.internalAddress == '\"${DEFAULT_IP}\"') | .nodeId' <<<${CLUSTERS})
    fi
    #Start checking local cluster for the IP
    #internal ip check
    if [[ ${NODEID// /} == "" ]]; then
        LOCAL_CLUSTER=$(curlcmd -k -s "${CATTLE_SERVER}/v3/clusters/local/nodes" -H "content-type: application/json" -H "Authorization: Bearer ${LOGINTOKEN}")
        NODEID=$(echo $LOCAL_CLUSTER | jq -r '.data[]?.ipAddress' | grep -i "${DEFAULT_IP}")
        if [[ ${NODEID// /} == "${DEFAULT_IP}" ]]; then
            grecho "Rancher local cluster detected, setting CLUSTERID to local."
            CLUSTERID="local"
        fi
    fi
    #external ip check
    if [[ ${NODEID// /} == "" ]]; then
        LOCAL_CLUSTER=$(curlcmd -k -s "${CATTLE_SERVER}/v3/clusters/local/nodes" -H "content-type: application/json" -H "Authorization: Bearer ${LOGINTOKEN}")
        NODEID=$(echo $LOCAL_CLUSTER | jq -r '.data[]?.externalIpAddress' | grep -i "${DEFAULT_IP}")
        if [[ ${NODEID// /} == "${DEFAULT_IP}" ]]; then
            grecho "Rancher local cluster detected, setting CLUSTERID to local."
            CLUSTERID="local"
        fi
    fi
    checknullvar "${NODEID}" "Unable to get NODEID on my own"
    #Store CLUSTERID
    if [[ ! "${CLUSTERID}" == "local" ]]; then
        CLUSTERID=$(cut -d':' -f1 <<<${NODEID})
        checknullvar "${CLUSTERID}" 'Unable to get CLUSTERID on my own, please set CLUSTERID manually with -c.  Cluster ID for local rancher cluster deployed with RKE is "local".' "exit1"
    fi
fi

#Store /v3/clusterregistration output
CLUSTERREGISTRATION=$(curlcmd -k -s ''${CATTLE_SERVER}'/v3/clusterregistrationtoken?clusterId='${CLUSTERID}'' -H 'content-type: application/json' -H "Authorization: Bearer ${LOGINTOKEN}")
checkpipecmd "Unable to store CLUSTERREGISTRATION, not sure what happened either.  Re-run script using bash -x for more information."
checknullvar "${CLUSTERREGISTRATION}" "Unable to store CLUSTERREGISTRATION, not sure what happened either.  Re-run script using bash -x for more information." "exit1"

#Store InsecureCommand
INSECURECOMMAND=$(jq -r '.data[0].insecureCommand' <<<${CLUSTERREGISTRATION})
checkpipecmd "Unable to get INSECURECOMMAND, jq portion failed but I'm not sure what happened.  Re-run script using bash -x for more information."

#Store nodeAgent
NODEAGENT=$(jq -r '.data[0].nodeCommand' <<<${CLUSTERREGISTRATION})
checkpipecmd "Unable to get NODEAGENT, jq portion failed but I'm not sure what happened.  Re-run script using bash -x for more information."

#Set AGENTCMD
AGENTCMD="${NODEAGENT} ${AGENT_OPTIONS}"

#Automatically set RUN_AGENT to no if NODEAGENT is null
if [[ "${NODEAGENT}" == "null" ]] && [[ "${RUN_AGENT}" == "yes" ]]; then
    recho "Your node agent command came back as null for some reason.  Unsetting run agent -r flag."
    echo
    RUN_AGENT="no"
fi

#Automatically set APPLY_YAML to no if INSECURECOMMAND is null
if [[ "${INSECURECOMMAND}" == "null" ]] && [[ "${APPLY_YAML}" == "yes" ]]; then
    recho "Your node agent command came back as null for some reason.  Unsetting run agent -r flag."
    echo
    APPLY_YAML="no"
fi

#Just display commands section
if [[ "${APPLY_YAML}" != "yes" ]] || [[ "${RUN_AGENT}" != "yes" ]]; then
    if [[ "${APPLY_YAML}" != "yes" ]]; then
        grecho "Below is your cluster yaml command to redploy agents."
        echo ${INSECURECOMMAND}
        echo
    fi
    if [[ "${RUN_AGENT}" != "yes" ]]; then
        grecho "Below is your cluster's agent command.  If you didn't specify any roles with -r then you should not run the command below until you've added roles to it."
        grecho "Do not run this command on a node with roles different from the roles already assigned to it, in most situations you won't need to run this command at all."
        echo ${AGENTCMD}
        echo
    fi
    if [[ "${APPLY_YAML}" != "yes" ]] && [[ "${RUN_AGENT}" != "yes" ]]; then
        grecho "Script has finished without error."
        exit 0
    fi
fi

#apply commands section
if [[ "${APPLY_YAML}" == "yes" ]] || [[ "${RUN_AGENT}" == "yes" ]]; then
    if [[ "${APPLY_YAML}" == "yes" ]]; then
        grecho "Below is your cluster yaml command to redploy agents."
        echo "${INSECURECOMMAND}"
        echo
        grecho "Should I proceed with applying the above curl|kubectl command?"
        yesno
        if [[ "${response}" == 'y' ]]; then
            if [[ "${MANUAL_KUBECONFIG}" != "yes" ]]; then
                setusupthekubeconfig
            fi
            recho "Applying your cluster yaml command to redeploy agents."
            if ! hash curl 2>/dev/null; then
                grecho "Unable to run command because curl is not natively installed.  Attempting alternative method of applying yaml."
                grecho "Original command below in case alternative method fails."
                echo "${INSECURECOMMAND}"
                echo
                NEW_INSECURECMD=$(sed -r 's, \| kubectl apply -f -,,g' <<< ${INSECURECOMMAND})
                NEW_INSECURECMD=$(sed -r 's,curl --insecure -sfL ,,g' <<< ${NEW_INSECURECMD})
                NEW_INSECURECMD=$(sed -r 's,curl --insecure -sfL ,,g' <<< ${NEW_INSECURECMD})
                
                INSECURECMD_FILE=$(sed -r 's,.*import/(.*),\1,g' <<< ${NEW_INSECURECMD})
                export INSECURECMD_FILE
                
                docker run -it --rm alpine wget -q --no-check-certificate -O - "${NEW_INSECURECMD} > ${TMPDIR}/${INSECURECMD_FILE}"
                dos2unix "${TMPDIR}/${INSECURECMD_FILE}"
                kubectl apply -f "${TMPDIR}/${INSECURECMD_FILE}"
            else
                eval "${INSECURECOMMAND}"
            fi
            checkpipecmd "Cluster yaml apply command failed, aborting script!"
            echo
        else
            grecho "Skipping YAML apply step."
        fi
    fi
    if [[ "${RUN_AGENT}" == "yes" ]]; then
        grecho "Below is your cluster's agent command.  If you didn't specify any roles with -r then you should not run the command below until you've added roles to it."
        echo "${AGENTCMD}"
        echo
        grecho "Should I proceed with applying the above docker run command?"
        yesno
        if [[ "${response}" == 'y' ]]; then
            recho "Running node agent command."
            eval "${AGENTCMD}"
            checkpipecmd "Node agent command failed, aborting script!"
            echo
        else
            grecho "Skipping node agent run step."
        fi
    fi
    grecho "Script has finished without error."
    exit 0
fi
