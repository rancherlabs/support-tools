#!/bin/bash
if hash tput 2>/dev/null; then
    red=$(tput setaf 1)
    green=$(tput setaf 2)
    reset=$(tput sgr0)
fi
USAGE='Automatic mode usage: ./etcd-join.sh <ssh user> <remote etcd IP> [path to ssh key for remote box]
Manual mode usage: ./etcd-join.sh MANUAL_MODE'
function grecho() {
    echo "${green}$1${reset}"
}
function recho() {
    echo "${red}$1${reset}"
}
rootcmd() {
    if [[ $EUID -ne 0 ]]; then
        grecho "Running as non root user, issuing command with sudo."
        sudo $1
    else
        $1
    fi
}
sshcmd() {
    if [[ ${#REMOTE_SSH_KEY} == 0 ]]; then
        ssh -o StrictHostKeyChecking=no -l "${REMOTE_SSH_USER}" "${REMOTE_SSH_IP}" "$1"
    else
        ssh -o StrictHostKeyChecking=no -i "${REMOTE_SSH_KEY}" -l "${REMOTE_SSH_USER}" "${REMOTE_SSH_IP}" "$1"
    fi
}
function askcontinue() {
    shopt -s nocasematch
    response=''
    i=0
    while [[ ${response} != 'yes' ]]; do
        i=$((i + 1))
        if [ $i -gt 10 ]; then
            echo "${green}Script has detected a response other than 'yes' more than ten times, aborting script!${reset}"
            exit 1
        fi
        printf "${green}Is it OK to proceed to the next step?  Type 'yes' to proceed: ${reset}"
        read response
        echo
    done
    shopt -u nocasematch
}
function asksetvar() {
    shopt -s nocasematch
    response=''
    i=0
    while [[ ${response} != 'yes' ]]; do
        i=$((i + 1))
        if [ $i -gt 10 ]; then
            grecho "Script has detected a response other than 'continue' more than ten times, aborting!"
            exit 1
        fi
        printf 'Result?: '
        read "$1"
        declare tmp="$1"
        grecho "Is this correct?:${reset} ${!tmp}
${green}Type yes and press enter to continue: "
        read response
    done
    shopt -u nocasematch
    recho "$1 has been set to${green} ${!tmp}"
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

function setendpoint() {
    if [[ "$REQUIRE_ENDPOINT" =~ ":::" ]]; then
        grecho "etcd is listening on ${REQUIRE_ENDPOINT}, no need to pass --endpoints"
        ETCD_ADD_MEMBER_CMD="etcdctl --cacert $ETCDCTL_CACERT --cert ${ETCDCTL_CERT} --key ${ETCDCTL_KEY} member add ${ETCD_NAME} --peer-urls=${INITIAL_ADVERTISE_PEER_URL}"
    else
        grecho "etcd is only listening on ${REQUIRE_ENDPOINT}, we need to pass --endpoints"
        ETCD_ADD_MEMBER_CMD="etcdctl --cacert $ETCDCTL_CACERT --cert ${ETCDCTL_CERT} --key ${ETCDCTL_KEY} member --endpoints ${REQUIRE_ENDPOINT} add ${ETCD_NAME} --peer-urls=${INITIAL_ADVERTISE_PEER_URL}"
    fi
}

#Help menu
if [[ "$1" == '' ]] || [[ $@ =~ " -h" ]] || [[ $1 == "-h" ]] || [[ $@ =~ " --help" ]] || [[ $1 =~ "--help" ]]; then
    grecho "${USAGE}"
    exit 1
fi
if [[ $1 != 'MANUAL_MODE' ]] && [[ $2 == '' ]]; then
    grecho "${USAGE}"
    exit 1
fi
if [[ $1 == 'MANUAL_MODE' ]]; then
    MANUAL_MODE=yes
fi
if [ "$(docker ps -a --filter "name=^/etcd-join$" --format '{{.Names}}')" == "etcd-join" ]; then
    docker rm -f etcd-join
fi

if [[ -d "/opt/rke/var/lib/etcd" ]]; then
    ETCD_DIR="/opt/rke/var/lib/etcd"
    elif [[ -d "/var/lib/etcd" ]]; then
        ETCD_DIR="/var/lib/etcd"
        else
            grecho "Unable to locate an etcd directory, either move an old backup back into the normal place for your operating system or create an empty directory.  RancherOS/CoreOS is usually /opt/rke/var/lib/etcd/ and everything else uses /varr/lib/etcd/ by default."
            exit 1
fi
grecho "Found ${ETCD_DIR}, setting ETCD_DIR to this value"

if [[ -d "/opt/rke/etc/kubernetes" ]]; then
    CERT_DIR="/opt/rke/etc/kubernetes"
    elif [[ -d "/etc/kubernetes" ]]; then
        CERT_DIR="/etc/kubernetes"
        else
            grecho "Unable to locate the kubernetes certificate directory, exiting script!"
            exit 1        
fi
grecho "Found ${CERT_DIR}, setting CERT_DIR to this value"
#check for runlike container
grecho "Gathering information about your etcd container with runlike"
RUNLIKE=$(docker run --rm -v /var/run/docker.sock:/var/run/docker.sock patrick0057/runlike etcd)
if [[ $? -ne 0 ]]; then
    grecho "runlike container failed to run, aborting script!"
    exit 1
fi
if [[ "${MANUAL_MODE}" != "yes" ]]; then
    REMOTE_SSH_USER=$1
    REMOTE_SSH_IP=$2
    REMOTE_SSH_KEY=$3
    grecho "Verifying SSH connections..."
    echo ssh user: ${REMOTE_SSH_USER}
    echo ssh ip: ${REMOTE_SSH_IP}
    echo ssh key: ${REMOTE_SSH_KEY}
    #echo length ${#REMOTE_SSH_KEY}
    if [[ ${#REMOTE_SSH_KEY} == 0 ]]; then
        ssh -o StrictHostKeyChecking=no -l "${REMOTE_SSH_USER} ${REMOTE_SSH_IP}" exit
        if [[ $? -ne 0 ]]; then
            grecho "Unable to connect to remote SSH host, aborting script! Did you set your ssh key\?"
            echo
            grecho "${USAGE}"
            exit 1

        fi
    else
        ssh -o StrictHostKeyChecking=no -i "${REMOTE_SSH_KEY}" -l "${REMOTE_SSH_USER}" "${REMOTE_SSH_IP}" exit
        if [[ $? -ne 0 ]]; then
            grecho "Unable to connect to remote SSH host, aborting script!"
            echo
            grecho "${USAGE}"
            exit 1
        fi
    fi
    grecho "SSH test succesful."
    echo
fi
if [[ "${MANUAL_MODE}" != "yes" ]]; then
    #Check if etcd is actually running on the remote server
    grecho "Checking to see if etcd is actually running on the remote host"
    REMOTE_ETCD_RUNNING=$(sshcmd "docker ps --filter 'name=^/etcd$' --format '{{.Names}}'")
    if [[ ! ${REMOTE_ETCD_RUNNING} == "etcd" ]]; then
        grecho "etcd is not running on the remote host! Check that you have the correct host then try again."
        exit 1
    fi
    grecho "etcd is running on the remote host, excellent!"
    echo
else
    grecho "MANUAL_MODE ENABLED: Please verify that etcd is running the host that you want to join before proceeding!"
    recho "Run:${reset} docker ps | grep etcd | grep -v etcd-rolling-snapshots"
    askcontinue
fi

export $(docker inspect etcd -f '{{.Config.Env}}' | sed 's/[][]//g')
docker inspect etcd &>/dev/null
if [[ $? -ne 0 ]]; then
    grecho "Uable to inspect the etcd container, does it still exist? Aborting script!"
    echo
    grecho "${USAGE}"
    exit 1
fi
grecho "I was able to inspect the local etcd container! Script will proceed..."
echo

recho "Setting etcd restart policy to never restart \"no\""
docker update --restart=no etcd

ETCD_BACKUP_TIME="$(date +%Y-%m-%d--%H%M%S)"

recho "Stopping etcd container"
docker stop etcd


recho "Moving old etcd data from ${ETCD_DIR} to ${ETCD_DIR}-old--${ETCD_BACKUP_TIME}"
rootcmd "mkdir ${ETCD_DIR}-old--${ETCD_BACKUP_TIME}"
checkpipecmd "Failed to created backup etcd directory, exiting script!"
if [[ "$(ls -A ${ETCD_DIR})" ]]; then
        recho "${ETCD_DIR} is not empty, moving files out into ${ETCD_DIR}-old--${ETCD_BACKUP_TIME}"
        rootcmd "mv ${ETCD_DIR}/* ${ETCD_DIR}-old--${ETCD_BACKUP_TIME}/"
        checkpipecmd "Failed to move etcd data files to backup directory ${ETCD_DIR}/* -> ${ETCD_DIR}-old--${ETCD_BACKUP_TIME}/, exiting script!"
        else
        grecho "${ETCD_DIR} is empty, no need to move any files out."
fi

ETCD_NAME=$(sed 's,^.*name=\([^ ]*\).*,\1,g' <<<$RUNLIKE)
ETCD_HOSTNAME=$(sed 's,^.*--hostname=\([^ ]*\).*,\1,g' <<<$RUNLIKE)
ETCDCTL_ENDPOINT="https://0.0.0.0:2379"
ETCDCTL_CACERT=$(sed 's,^.*ETCDCTL_CACERT=\([^ ]*\).*,\1,g' <<<$RUNLIKE)
ETCDCTL_CERT=$(sed 's,^.*ETCDCTL_CERT=\([^ ]*\).*,\1,g' <<<$RUNLIKE)
ETCDCTL_KEY=$(sed 's,^.*ETCDCTL_KEY=\([^ ]*\).*,\1,g' <<<$RUNLIKE)
ETCD_VERSION=$(sed 's,^.*rancher/coreos-etcd:\([^ ]*\).*,\1,g' <<<$RUNLIKE)
INITIAL_ADVERTISE_PEER_URL=$(sed 's,^.*initial-advertise-peer-urls=\([^ ]*\).*,\1,g' <<<$RUNLIKE)
ETCD_NAME=$(sed 's,^.*name=\([^ ]*\).*,\1,g' <<<$RUNLIKE)
INITIAL_CLUSTER=$(sed 's,^.*--initial-cluster=.*\('"$ETCD_NAME"'\)=\([^,^ ]*\).*,\1=\2,g' <<<$RUNLIKE)
INITIAL_CLUSTER_TOKEN=$(sed 's,^.*initial-cluster-token=\([^ ]*\).*,\1,g' <<<$RUNLIKE)
ADVERTISE_CLIENT_URLS=$(sed 's,^.*advertise-client-urls=\([^ ]*\).*,\1,g' <<<$RUNLIKE)
ETCD_IMAGE=$(docker inspect etcd --format='{{.Config.Image}}')
if [[ "${MANUAL_MODE}" != "yes" ]]; then
    #CHECK IF WE NEED TO ADD --endpoints TO THE COMMAND
    REQUIRE_ENDPOINT=$(sshcmd "docker exec etcd netstat -lpna | grep \:2379 | grep tcp | grep LISTEN | tr -s ' ' | cut -d' ' -f4")
    setendpoint
else
    grecho "MANUAL_MODE ENABLED: Please run the following command on the etcd host you want to join then paste the results below."
    echo "docker exec etcd netstat -lpna | grep \:2379 | grep tcp | grep LISTEN | tr -s ' ' | cut -d' ' -f4"
    asksetvar REQUIRE_ENDPOINT
    setendpoint
fi

if [[ "${MANUAL_MODE}" != "yes" ]]; then
    recho "Connecting to remote etcd and issuing add member command"
    export $(sshcmd "docker exec etcd ${ETCD_ADD_MEMBER_CMD} | grep ETCD_INITIAL_CLUSTER=")
    recho "ETCD_INITIAL_CLUSTER has been set to ${ETCD_INITIAL_CLUSTER} ${green}<-If this is blank etcd-join will fail"
else
    grecho "MANUAL_MODE ENABLED: Please run the following command on the etcd host you want to join then paste the last line of the output below."
    grecho "it should look something like this:"
    echo "etcd-ip-172-31-11-26=https://172.31.11.26:2380,etcd-ip-172-31-14-134=https://172.31.14.134:2380"
    grecho "command below:"
    echo "docker exec etcd ${ETCD_ADD_MEMBER_CMD} | grep ETCD_INITIAL_CLUSTER= | sed -r 's,ETCD_INITIAL_CLUSTER=\"(.*)\",\1,g'"
    asksetvar ETCD_INITIAL_CLUSTER
    askcontinue
fi

RESTORE_RUNLIKE='docker run
--name=etcd-join
--hostname='$ETCD_HOSTNAME'
--env="ETCDCTL_API=3"
--env="ETCDCTL_ENDPOINT='$ETCDCTL_ENDPOINT'"
--env="ETCDCTL_CACERT='$ETCDCTL_CACERT'"
--env="ETCDCTL_CERT='$ETCDCTL_CERT'"
--env="ETCDCTL_KEY='$ETCDCTL_KEY'"
--env="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
--volume="'${ETCD_DIR}':/var/lib/rancher/etcd/:z"
--volume="'${CERT_DIR}':/etc/kubernetes:z"
--volume="/opt/rke:/opt/rke:z"
--network=host
--label io.rancher.rke.container.name="etcd"
--detach=true '${ETCD_IMAGE}' /usr/local/bin/etcd
--peer-client-cert-auth
--client-cert-auth
--initial-cluster='${ETCD_INITIAL_CLUSTER}'
--initial-cluster-state=existing
--trusted-ca-file='${ETCDCTL_CACERT}'
--listen-client-urls=https://0.0.0.0:2379
--initial-advertise-peer-urls='${INITIAL_ADVERTISE_PEER_URL}'
--listen-peer-urls=https://0.0.0.0:2380
--heartbeat-interval=500
--election-timeout=5000
--data-dir=/var/lib/rancher/etcd/
--initial-cluster-token='${INITIAL_CLUSTER_TOKEN}'
--peer-cert-file='${ETCDCTL_CERT}'
--peer-key-file='${ETCDCTL_KEY}'
--name='${ETCD_NAME}'
--advertise-client-urls='${ADVERTISE_CLIENT_URLS}'
--peer-trusted-ca-file='${ETCDCTL_CACERT}'
--cert-file='${ETCDCTL_CERT}'
--key-file='${ETCDCTL_KEY}''

grecho "Launching etcd-join with the following command:"
echo "${RESTORE_RUNLIKE}"
eval ${RESTORE_RUNLIKE}
echo

grecho "Script sleeping for 10 seconds."
sleep 10

if [ ! "$(docker ps --filter "name=^/etcd-join$" --format '{{.Names}}')" == "etcd-join" ]; then
    grecho " etcd-join is not running, something went wrong.  Make sure the etcd cluster only has healthy and online members then try again."
    exit 1
fi

grecho "etcd-join appears to be running still, this is a good sign. Proceeding with cleanup."
recho "Stopping etcd-join"
docker stop etcd-join
recho "Deleting etcd-join"
docker rm etcd-join
recho "Starting etcd"
docker start etcd

if [ ! "$(docker ps --filter "name=^/etcd$" --format '{{.Names}}')" == "etcd" ]; then
    grecho "etcd is not running, something went wrong."
    exit 1
fi
grecho "etcd is running on local host."

if [[ "${MANUAL_MODE}" != "yes" ]]; then
    grecho "checking members list on remote etcd host."
    if [[ $REQUIRE_ENDPOINT =~ ":::" ]]; then
        grecho "etcd is listening on ${REQUIRE_ENDPOINT}, no need to pass --endpoints"
        sshcmd "docker exec etcd etcdctl member list"
    else
        grecho "etcd is only listening on ${REQUIRE_ENDPOINT}, we need to pass --endpoints"
        sshcmd "docker exec etcd etcdctl --endpoints ${REQUIRE_ENDPOINT} member list"
    fi
else
    grecho "MANUAL_MODE ENABLED: Script has completed, please run the following command on the remote etcd host to verify members list."
    if [[ ${REQUIRE_ENDPOINT} =~ ":::" ]]; then
        grecho "etcd is listening on ${REQUIRE_ENDPOINT}, no need to pass --endpoints"
        echo "docker exec etcd etcdctl member list"
    else
        grecho "etcd is only listening on ${REQUIRE_ENDPOINT}, we need to pass --endpoints"
        echo "docker exec etcd etcdctl --endpoints ${REQUIRE_ENDPOINT} member list"
    fi
    askcontinue
fi

recho "Setting etcd restart policy to always restart"
docker update --restart=always etcd

recho "Restarting kubelet and kube-apiserver if they exist"
docker restart kubelet kube-apiserver

echo
grecho "Script has completed!"
