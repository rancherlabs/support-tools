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
ETCD_BACKUP_TIME=$(date +%Y-%m-%d--%H%M%S)
if [[ $? -ne 0 ]]; then
        grecho "Setting timestamp failed, does the \"date\" command exist\?"
        exit 1
fi

rootcmd() {
        if [[ $EUID -ne 0 ]]; then
                grecho "Running as non root user, issuing command with sudo."
                sudo $1
        else
                $1
        fi
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

if [[ -d "/opt/rke/var/lib/etcd" ]]; then
    ETCD_DIR="/opt/rke/var/lib/etcd"
    elif [[ -d "/var/lib/etcd" ]]; then
        ETCD_DIR="/var/lib/etcd"
        else
            grecho "Unable to locate an etcd directory, exiting script!"
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

if [ -d "/opt/rke/etcd" ]; then
        grecho "/opt/rke/etcd exists, moving it to /opt/rke/etcd--${ETCD_BACKUP_TIME}."
        rootcmd "mv /opt/rke/etcd /opt/rke/etcd--${ETCD_BACKUP_TIME}"
fi
if [ ! "$(docker ps -a --filter "name=^/etcd$" --format '{{.Names}}')" == "etcd" ]; then
        grecho "etcd container does not exist, script cannot proceed.  Check docker ps -a for old containers and rename one of them back to etcd."
        exit 1
fi
if [ "$(docker ps -a --filter "name=^/etcd-restore$" --format '{{.Names}}')" == "etcd-restore" ]; then
        grecho "etcd-restore container exists, deleting container"
        docker rm -f etcd-restore
        checkpipecmd "Unable to delete etcd-restore, exiting script!"
fi
if [ "$(docker ps -a --filter "name=^/etcd-reinit$" --format '{{.Names}}')" == "etcd-reinit" ]; then
        grecho "etcd-reinit container exists, deleting container"
        docker rm -f etcd-reinit
        checkpipecmd "Unable to delete etcd-reinit, exiting script!"
fi
#Help menu
USAGE='To restore a snapshot: ./restore-etcd-single.sh </path/to/snapshot>
To restore lost quorum to a single node and remove other members without a snapshot: ./restore-etcd-single.sh FORCE_NEW_CLUSTER'
if [[ $1 == '' ]] || [[ $@ =~ " -h" ]] || [[ $1 == "-h" ]] || [[ $@ =~ " --help" ]] || [[ $1 =~ "--help" ]]; then
        grecho "${USAGE}"
        exit 1
fi

if [[ $1 == 'FORCE_NEW_CLUSTER' ]]; then
        FORCE_NEW_CLUSTER=yes
else
        RESTORE_SNAPSHOT=$1
        #check if image exists
        ls -lash "${RESTORE_SNAPSHOT}"
        if [[ $? -ne 0 ]]; then
                grecho "Image ${RESTORE_SNAPSHOT} does not exist, aborting script!"
                exit 1
        fi
        #check if zip file and extract if it is
        if [[ "${RESTORE_SNAPSHOT/${RESTORE_SNAPSHOT/\.zip/}/}" == ".zip" ]]; then
                if ! hash unzip 2>/dev/null; then
                        grecho '!!!unzip was not found!!!'
                        exit 1
                fi
                grecho "Zipped snapshot detected, unzipping ${RESTORE_SNAPSHOT}..."
                unzip -o "${RESTORE_SNAPSHOT}"
                RESULT="$?"
                if [[ "$RESULT" -gt "1" ]]; then
                        grecho "Unzip returned exit code higher than 1 which indicates a failure.  Exiting script!"
                        exit 1
                        else
                                grecho "${RESTORE_SNAPSHOT} unzipped successfully!"
                fi
                mv ./backup/"${RESTORE_SNAPSHOT/\.zip/}" .
                checkpipecmd "Failed to move snapshot to current directory!"
                RESTORE_SNAPSHOT="${RESTORE_SNAPSHOT/\.zip/}"
        fi
        #move stale snapshot out of way if it exists
        if [ -f "${CERT_DIR}/snapshot.db" ]; then
                recho "Found stale snapshot at ${CERT_DIR}/snapshot.db, moving it out of the way to ${CERT_DIR}/snapshot.db--${ETCD_BACKUP_TIME}"
                rootcmd "mv ${CERT_DIR}/snapshot.db ${CERT_DIR}/snapshot.db--${ETCD_BACKUP_TIME}"
        fi
        #copy snapshot into place
        recho "Copying ${RESTORE_SNAPSHOT} to ${CERT_DIR}/snapshot.db"
        rootcmd "cp ${RESTORE_SNAPSHOT} ${CERT_DIR}/snapshot.db"
        checkpipecmd "Failed to copy ${RESTORE_SNAPSHOT} to ${CERT_DIR}/snapshot.db, aborting script!"
fi




#check for runlike container
RUNLIKE=$(docker run --rm -v /var/run/docker.sock:/var/run/docker.sock patrick0057/runlike etcd)
checkpipecmd "runlike container failed to run, aborting script!"

recho "Setting etcd restart policy to never restart \"no\""
docker update --restart=no etcd
recho "Renaming original etcd container to etcd-old--${ETCD_BACKUP_TIME}"
docker rename etcd etcd-old--"${ETCD_BACKUP_TIME}"
checkpipecmd "Failed to rename etcd to etcd-old--${ETCD_BACKUP_TIME}, aborting script!"

recho "Stopping original etcd container"
docker stop etcd-old--${ETCD_BACKUP_TIME}
checkpipecmd "Failed to stop etcd-old--${ETCD_BACKUP_TIME}"



if [[ "${FORCE_NEW_CLUSTER}" == "yes" ]]; then
        recho "Copying old etcd data directory ${ETCD_DIR} to ${ETCD_DIR}-old--${ETCD_BACKUP_TIME}"
        rootcmd "cp -arfv ${ETCD_DIR} ${ETCD_DIR}-old--${ETCD_BACKUP_TIME}"
        checkpipecmd "Failed to copy ${ETCD_DIR} to ${ETCD_DIR}-old--${ETCD_BACKUP_TIME}, aborting script!"
else
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
                
        
fi

ETCD_HOSTNAME=$(sed 's,^.*--hostname=\([^ ]*\).*,\1,g' <<<${RUNLIKE})
ETCDCTL_ENDPOINT="https://0.0.0.0:2379"
ETCDCTL_CACERT=$(sed 's,^.*ETCDCTL_CACERT=\([^ ]*\).*,\1,g' <<<${RUNLIKE})
ETCDCTL_CERT=$(sed 's,^.*ETCDCTL_CERT=\([^ ]*\).*,\1,g' <<<${RUNLIKE})
ETCDCTL_KEY=$(sed 's,^.*ETCDCTL_KEY=\([^ ]*\).*,\1,g' <<<${RUNLIKE})
ETCD_VERSION=$(sed 's,^.*rancher/coreos-etcd:\([^ ]*\).*,\1,g' <<<${RUNLIKE})
INITIAL_ADVERTISE_PEER_URL=$(sed 's,^.*initial-advertise-peer-urls=\([^ ]*\).*,\1,g' <<<${RUNLIKE})
ETCD_NAME=$(sed 's,^.*name=\([^ ]*\).*,\1,g' <<<${RUNLIKE})
INITIAL_CLUSTER=$(sed 's,^.*--initial-cluster=.*\('"${ETCD_NAME}"'\)=\([^,^ ]*\).*,\1=\2,g' <<<${RUNLIKE})
#ETCD_SNAPSHOT_LOCATION="snapshot.db"
INITIAL_CLUSTER_TOKEN=$(sed 's,^.*initial-cluster-token=\([^ ]*\).*,\1,g' <<<${RUNLIKE})
ETCD_IMAGE="$(docker inspect etcd-old--${ETCD_BACKUP_TIME} --format='{{.Config.Image}}')"
grecho "ETCD_IMAGE set to ${ETCD_IMAGE}"
if [[ "${FORCE_NEW_CLUSTER}" != "yes" ]]; then
        RESTORE_RUNLIKE='docker run
--name=etcd-restore
--hostname='${ETCD_HOSTNAME}'
--env="ETCDCTL_API=3"
--env="ETCDCTL_ENDPOINT='${ETCDCTL_ENDPOINT}'"
--env="ETCDCTL_CACERT='${ETCDCTL_CACERT}'"
--env="ETCDCTL_CERT='${ETCDCTL_CERT}'"
--env="ETCDCTL_KEY='${ETCDCTL_KEY}'"
--env="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
--volume="'${ETCD_DIR}':/var/lib/rancher/etcd/:z"
--volume="'${CERT_DIR}':/etc/kubernetes:z"
--volume="/opt/rke:/opt/rke:z"
--network=host
--label io.rancher.rke.container.name="etcd"
-ti '${ETCD_IMAGE}' /usr/local/bin/etcdctl snapshot restore /etc/kubernetes/snapshot.db
--initial-advertise-peer-urls='${INITIAL_ADVERTISE_PEER_URL}'
--initial-cluster='${INITIAL_CLUSTER}'
--initial-cluster-token='${INITIAL_CLUSTER_TOKEN}'
--data-dir=/opt/rke/etcd
--name='${ETCD_NAME}''

        #RESTORE ETCD
        recho "Restoring etcd snapshot with the following command:"
        echo ${RESTORE_RUNLIKE}
        eval ${RESTORE_RUNLIKE}
        checkpipecmd "Failed to restore etcd snapshot!"
        #grecho "Sleeping for 10 seconds so etcd can do its restore"
        #sleep 10

        recho "Stopping etcd-restore container"
        docker stop etcd-restore

        recho "Moving restored etcd directory in place"
        rootcmd "mv /opt/rke/etcd/* ${ETCD_DIR}/"
        rootcmd "rm -fr /opt/rke/etcd/"

        recho "Deleting etcd-restore container"
        docker rm -f etcd-restore
fi

#INITIALIZE NEW RUNLIKE
NEW_RUNLIKE=${RUNLIKE}

#ADD --force-new-cluster
NEW_RUNLIKE=$(sed 's,^\(.*'${ETCD_VERSION}' \)\([^ ]*\)\(.*\),\1\2 --force-new-cluster\3,g' <<<${NEW_RUNLIKE})

#REMOVE OTHER ETCD NODES FROM --initial-cluster
ORIG_INITIAL_CLUSTER=$(sed 's,^.*initial-cluster=\([^ ]*\).*,\1,g' <<<${RUNLIKE})
NEW_RUNLIKE=$(sed 's`'"${ORIG_INITIAL_CLUSTER}"'`'"${INITIAL_CLUSTER}"'`g' <<<${NEW_RUNLIKE})

#CHANGE NAME TO etcd-reinit
NEW_RUNLIKE=$(sed 's`'--name=etcd'`'--name=etcd-reinit'`g' <<<${NEW_RUNLIKE})

#REINIT ETCD
recho "Running etcd-reinit with the following command:"
echo ${NEW_RUNLIKE}
eval ${NEW_RUNLIKE}
checkpipecmd "Failed to run etcd-reinit!"
grecho "Sleeping for 10 seconds so etcd can do reinit things"
sleep 10

#echo ${green}Tailing last 40 lines of etcd-reinit${reset}
#docker logs etcd-reinit --tail 40

#STOP AND REMOVE etcd-reinit
recho "Stopping and removing etcd-reinit"
docker stop etcd-reinit
docker rm -f etcd-reinit

#CHANGE NAME BACK TO etcd
NEW_RUNLIKE=$(sed 's`'--name=etcd-reinit'`'--name=etcd'`g' <<<${NEW_RUNLIKE})

#REMOVE --force-new-cluster
NEW_RUNLIKE=$(sed 's`--force-new-cluster ``g' <<<${NEW_RUNLIKE})

#FINALLY RUN NEW SHINY RESTORED ETCD
recho "Launching shiny new etcd"
echo ${NEW_RUNLIKE}
eval ${NEW_RUNLIKE}
checkpipecmd "Failed to launch shiny new etcd!"
grecho "Script sleeping for 5 seconds"
sleep 5
echo

recho "Restarting kubelet and kube-apiserver if they exist"
docker restart kubelet kube-apiserver

if [[ "$FORCE_NEW_CLUSTER" != "yes" ]]; then
        echo "${red}Removing ${CERT_DIR}/snapshot.db${reset}"
        #rootcmd "mv ${CERT_DIR}/snapshot.db ${CERT_DIR}/snapshot.db--${ETCD_BACKUP_TIME}"
        rootcmd "rm -f ${CERT_DIR}/snapshot.db"
fi

recho "Setting etcd restart policy to always restart"
docker update --restart=always etcd

#PRINT OUT MEMBER LIST
#CHECK IF WE NEED TO ADD --endpoints TO THE COMMAND
grecho "Running an 'etcdctl member list' as a final test."
REQUIRE_ENDPOINT=$(docker exec etcd netstat -lpna | grep \:2379 | grep tcp | grep LISTEN | tr -s ' ' | cut -d' ' -f4)
if [[ $REQUIRE_ENDPOINT =~ ":::" ]]; then
        echo "${green}etcd is listening on ${REQUIRE_ENDPOINT}, no need to pass --endpoints${reset}"
        docker exec etcd etcdctl member list
else
        echo "${green}etcd is only listening on ${REQUIRE_ENDPOINT}, we need to pass --endpoints${reset}"
        docker exec etcd etcdctl --endpoints ${REQUIRE_ENDPOINT} member list
fi

grecho "Single restore has completed, please be sure to restart kubelet and kube-apiserver on other nodes."
grecho "If you are planning to rejoin another node to this etcd cluster you'll want to use etcd-join.sh on that node"
