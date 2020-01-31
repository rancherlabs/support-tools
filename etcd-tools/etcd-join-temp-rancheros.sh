#!/bin/bash
red=$(tput setaf 1)
green=$(tput setaf 2)
reset=$(tput sgr0)
USAGE='Automatic mode usage: ./etcd-join.sh <ssh user> <remote etcd IP> [path to ssh key for remote box]
Manual mode usage: ./etcd-join.sh MANUAL_MODE'
rootcmd() {
    if [[ $EUID -ne 0 ]]; then
        echo "${green}Running as non root user, issuing command with sudo.${reset}"
        sudo $1
    else
        $1
    fi
}
sshcmd() {
    if [[ ${#REMOTE_SSH_KEY} == 0 ]]; then
        ssh -o StrictHostKeyChecking=no -l ${REMOTE_SSH_USER} $REMOTE_SSH_IP $1
    else
        ssh -o StrictHostKeyChecking=no -i ${REMOTE_SSH_KEY} -l ${REMOTE_SSH_USER} $REMOTE_SSH_IP $1
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
            echo "${green}Script has detected a response other than 'continue' more than ten times, aborting${reset}"
            exit 1
        fi
        printf 'Result?: '
        read "$1"
        declare tmp="$1"
        echo "${green}Is this correct?:${reset} ${!tmp}
${green}Type yes and press enter to continue: ${reset}"
        read response
    done
    shopt -u nocasematch
    echo "${red}$1 has been set to${green} ${!tmp}${reset}"
}

function setendpoint() {
    if [[ "$REQUIRE_ENDPOINT" =~ ":::" ]]; then
        echo "${green}etcd is listening on ${REQUIRE_ENDPOINT}, no need to pass --endpoints${reset}"
        ETCD_ADD_MEMBER_CMD="etcdctl --cacert $ETCDCTL_CACERT --cert $ETCDCTL_CERT --key ${ETCDCTL_KEY} member add ${ETCD_NAME} --peer-urls=${INITIAL_ADVERTISE_PEER_URL}"
    else
        echo "${green}etcd is only listening on ${REQUIRE_ENDPOINT}, we need to pass --endpoints${reset}"
        ETCD_ADD_MEMBER_CMD="etcdctl --cacert $ETCDCTL_CACERT --cert $ETCDCTL_CERT --key ${ETCDCTL_KEY} member --endpoints ${REQUIRE_ENDPOINT} add ${ETCD_NAME} --peer-urls=${INITIAL_ADVERTISE_PEER_URL}"
    fi
}
#Help menu
if [[ $1 == '' ]] || [[ $@ =~ " -h" ]] || [[ $1 == "-h" ]] || [[ $@ =~ " --help" ]] || [[ $1 =~ "--help" ]]; then
    echo "${green}${USAGE}${reset}"
    exit 1
fi
if [[ $1 != 'MANUAL_MODE' ]] && [[ $2 == '' ]]; then
    echo "${green}${USAGE}${reset}"
    exit 1
fi
if [[ $1 == 'MANUAL_MODE' ]]; then
    MANUAL_MODE=yes
fi
if [ "$(docker ps -a --filter "name=^/etcd-join$" --format '{{.Names}}')" == "etcd-join" ]; then
    docker rm -f etcd-join
fi
#check for runlike container
echo "${green}Gathering information about your etcd container with runlike${reset}"
RUNLIKE=$(docker run --rm -v /var/run/docker.sock:/var/run/docker.sock patrick0057/runlike etcd)
if [[ $? -ne 0 ]]; then
    echo ${green}runlike container failed to run, aborting script!${reset}
    exit 1
fi
if [[ "${MANUAL_MODE}" != "yes" ]]; then
    REMOTE_SSH_USER=$1
    REMOTE_SSH_IP=$2
    REMOTE_SSH_KEY=$3
    echo ${green}Verifying SSH connections...${reset}
    echo ssh user: ${REMOTE_SSH_USER}
    echo ssh ip: ${REMOTE_SSH_IP}
    echo ssh key: ${REMOTE_SSH_KEY}
    #echo length ${#REMOTE_SSH_KEY}
    if [[ ${#REMOTE_SSH_KEY} == 0 ]]; then
        ssh -o StrictHostKeyChecking=no -l ${REMOTE_SSH_USER} $REMOTE_SSH_IP exit
        if [[ $? -ne 0 ]]; then
            echo "${green}Unable to connect to remote SSH host, aborting script! Did you set your ssh key\?${reset}"
            echo
            echo "${green}${USAGE}${reset}"
            exit 1

        fi
    else
        ssh -o StrictHostKeyChecking=no -i ${REMOTE_SSH_KEY} -l ${REMOTE_SSH_USER} $REMOTE_SSH_IP exit
        if [[ $? -ne 0 ]]; then
            echo ${green}Unable to connect to remote SSH host, aborting script!${reset}
            echo
            echo "${green}${USAGE}${reset}"
            exit 1
        fi
    fi
    echo "${green}SSH test succesful.${reset}"
    echo
fi
if [[ "${MANUAL_MODE}" != "yes" ]]; then
    #Check if etcd is actually running on the remote server
    echo ${green}Checking to see if etcd is actually running on the remote host ${reset}
    REMOTE_ETCD_RUNNING=$(sshcmd "docker ps --filter 'name=^/etcd$' --format '{{.Names}}'")
    if [[ ! ${REMOTE_ETCD_RUNNING} == 'etcd' ]]; then
        echo ${green}etcd is not running on the remote host! Check that you have the correct host then try again.${reset}
        exit 1
    fi
    echo "${green}etcd is running on the remote host, excellent!${reset}"
    echo
else
    echo ${green}MANUAL_MODE ENABLED: Please verify that etcd is running the host that you want to join before proceeding!${reset}
    echo "${red}Run:${reset} docker ps | grep etcd | grep -v etcd-rolling-snapshots"
    askcontinue
fi

export $(docker inspect etcd -f '{{.Config.Env}}' | sed 's/[][]//g')
docker inspect etcd &>/dev/null
if [[ $? -ne 0 ]]; then
    echo "${green}Uable to inspect the etcd container, does it still exist? Aborting script!${reset}"
    echo
    echo "${green}${USAGE}${reset}"
    exit 1
fi
echo "${green}I was able to inspect the local etcd container! Script will proceed...${reset}"
echo

echo "${red}Setting etcd restart policy to never restart \"no\"${reset}"
docker update --restart=no etcd

ETCD_BACKUP_TIME=$(date +%Y-%m-%d--%H%M%S)

echo ${red}Stopping etcd container${reset}
docker stop etcd

echo ${red}Moving old etcd data directory /var/lib/etcd to /var/lib/etcd-old--${ETCD_BACKUP_TIME}${reset}
rootcmd "mv /var/lib/etcd /var/lib/etcd-old--${ETCD_BACKUP_TIME}"

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

if [[ "${MANUAL_MODE}" != "yes" ]]; then
    #CHECK IF WE NEED TO ADD --endpoints TO THE COMMAND
    REQUIRE_ENDPOINT=$(sshcmd "docker exec etcd netstat -lpna | grep \:2379 | grep tcp | grep LISTEN | tr -s ' ' | cut -d' ' -f4")
    setendpoint
else
    echo "${green}MANUAL_MODE ENABLED: Please run the following command on the etcd host you want to join then paste the results below.${reset}"
    echo "docker exec etcd netstat -lpna | grep \:2379 | grep tcp | grep LISTEN | tr -s ' ' | cut -d' ' -f4"
    asksetvar REQUIRE_ENDPOINT
    setendpoint
fi

if [[ "${MANUAL_MODE}" != "yes" ]]; then
    echo ${red}Connecting to remote etcd and issuing add member command${reset}
    export $(sshcmd "docker exec etcd ${ETCD_ADD_MEMBER_CMD} | grep ETCD_INITIAL_CLUSTER=")
    echo "${red}ETCD_INITIAL_CLUSTER has been set to ${ETCD_INITIAL_CLUSTER} ${green}<-If this is blank etcd-join will fail${reset}"
else
    echo "${green}MANUAL_MODE ENABLED: Please run the following command on the etcd host you want to join then paste the results below.${reset}"
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
--volume="/var/lib/etcd:/var/lib/rancher/etcd/:z"
--volume="/etc/kubernetes:/etc/kubernetes:z"
--volume="/opt/rke:/opt/rke:z"
--network=host
--label io.rancher.rke.container.name="etcd"
--detach=true rancher/coreos-etcd:'$ETCD_VERSION' /usr/local/bin/etcd
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
echo "${green}Running the following command:${reset}"
echo $RESTORE_RUNLIKE

echo "${green}Launching etcd-join${reset}"
eval $RESTORE_RUNLIKE
echo

echo "${green}Script sleeping for 10 seconds${reset}"
sleep 10

if [ ! "$(docker ps --filter "name=^/etcd-join$" --format '{{.Names}}')" == "etcd-join" ]; then
    echo "${green} etcd-join is not running, something went wrong.  Make sure the etcd cluster only has healthy and online members then try again.${reset}"
    exit 1
fi

echo "${green}etcd-join appears to be running still, this is a good sign. Proceeding with cleanup.${reset}"
echo "${red}Stopping etcd-join${reset}"
docker stop etcd-join
echo "${red}Deleting etcd-join${reset}"
docker rm etcd-join
echo "${red}Starting etcd${reset}"
docker start etcd

if [ ! "$(docker ps --filter "name=^/etcd$" --format '{{.Names}}')" == "etcd" ]; then
    echo "${green}etcd is not running, something went wrong.${reset}"
    exit 1
fi
echo "${green}etcd is running on local host${reset}"

if [[ "${MANUAL_MODE}" != "yes" ]]; then
    echo "${green}checking members list on remote etcd host.${reset}"
    if [[ $REQUIRE_ENDPOINT =~ ":::" ]]; then
        echo "${green}etcd is listening on ${REQUIRE_ENDPOINT}, no need to pass --endpoints${reset}"
        sshcmd "docker exec etcd etcdctl member list"
    else
        echo "${green}etcd is only listening on ${REQUIRE_ENDPOINT}, we need to pass --endpoints${reset}"
        sshcmd "docker exec etcd etcdctl --endpoints ${REQUIRE_ENDPOINT} member list"
    fi
else
    echo "${green}MANUAL_MODE ENABLED: Script has completed, please run the following command on the remote etcd host to verify members list.${reset}"
    if [[ $REQUIRE_ENDPOINT =~ ":::" ]]; then
        echo "${green}etcd is listening on ${REQUIRE_ENDPOINT}, no need to pass --endpoints${reset}"
        echo "docker exec etcd etcdctl member list"
    else
        echo "${green}etcd is only listening on ${REQUIRE_ENDPOINT}, we need to pass --endpoints${reset}"
        echo "docker exec etcd etcdctl --endpoints ${REQUIRE_ENDPOINT} member list"
    fi
    askcontinue
fi

echo "${red}Setting etcd restart policy to always restart${reset}"
docker update --restart=always etcd

echo "${red}Restarting kubelet and kube-apiserver if they exist${reset}"
docker restart kubelet kube-apiserver

echo
echo "${green}Script has completed!${reset}"
