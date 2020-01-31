#!/bin/bash
red=$(tput setaf 1)
green=$(tput setaf 2)
reset=$(tput sgr0)
ETCD_BACKUP_TIME=$(date +%Y-%m-%d--%H%M%S)
if [[ $? -ne 0 ]]; then
        echo "${green}Setting timestamp failed, does the \"date\" command exist\?${reset}"
        exit 1
fi

rootcmd() {
        if [[ $EUID -ne 0 ]]; then
                echo "${green}Running as non root user, issuing command with sudo.${reset}"
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

if [ -d "/opt/rke/etcd" ]; then
        echo ${green}/opt/rke/etcd exists, moving it to /opt/rke/etcd--${ETCD_BACKUP_TIME}.${reset}
        rootcmd "mv /opt/rke/etcd /opt/rke/etcd--${ETCD_BACKUP_TIME}"
fi
if [ ! "$(docker ps -a --filter "name=^/etcd$" --format '{{.Names}}')" == "etcd" ]; then
        echo "${green}etcd container does not exist, script cannot proceed${reset}"
        exit 1
fi
if [ "$(docker ps -a --filter "name=^/etcd-restore$" --format '{{.Names}}')" == "etcd-restore" ]; then
        echo "${green}etcd-restore container exists, please remove this container before running the script${reset}"
        exit 1
fi
if [ "$(docker ps -a --filter "name=^/etcd-reinit$" --format '{{.Names}}')" == "etcd-reinit" ]; then
        echo "${green}etcd-reinit container exists, please remove this container before running the script${reset}"
        exit 1
fi
#Help menu
USAGE='To restore a snapshot: ./restore-etcd-single.sh </path/to/snapshot>
To restore lost quorum to a single node and remove other members without a snapshot: ./restore-etcd-single.sh FORCE_NEW_CLUSTER'
if [[ $1 == '' ]] || [[ $@ =~ " -h" ]] || [[ $1 == "-h" ]] || [[ $@ =~ " --help" ]] || [[ $1 =~ "--help" ]]; then
        echo "${green}${USAGE}${reset}"
        exit 1
fi

if [[ $1 == 'FORCE_NEW_CLUSTER' ]]; then
        FORCE_NEW_CLUSTER=yes
else
        RESTORE_SNAPSHOT=$1
        #check if image exists
        ls -lash $RESTORE_SNAPSHOT
        if [[ $? -ne 0 ]]; then
                echo "${green}Image $RESTORE_SNAPSHOT does not exist, aborting script!${reset}"
                exit 1
        fi
        #move stale snapshot out of way if it exists
        if [ -f "/etc/kubernetes/snapshot.db" ]; then
                echo "${red}Found stale snapshot at /etc/kubernetes/snapshot.db, moving it out of the way to /etc/kubernetes/snapshot.db--${ETCD_BACKUP_TIME}${reset}"
                rootcmd "mv /etc/kubernetes/snapshot.db /etc/kubernetes/snapshot.db--${ETCD_BACKUP_TIME}"
        fi
        #copy snapshot into place
        echo "${red}Copying $RESTORE_SNAPSHOT to /etc/kubernetes/snapshot.db ${reset}"
        rootcmd "cp $RESTORE_SNAPSHOT /etc/kubernetes/snapshot.db"
        checkpipecmd "${green}Failed to copy $RESTORE_SNAPSHOT to /etc/kubernetes/snapshot.db, aborting script!${reset}"
fi

#check for runlike container
RUNLIKE=$(docker run --rm -v /var/run/docker.sock:/var/run/docker.sock patrick0057/runlike etcd)
checkpipecmd "${green}runlike container failed to run, aborting script!${reset}"

echo "${red}Setting etcd restart policy to never restart \"no\"${reset}"
docker update --restart=no etcd
echo "${red}Renaming original etcd container to etcd-old--${ETCD_BACKUP_TIME}${reset}"
docker rename etcd etcd-old--${ETCD_BACKUP_TIME}
checkpipecmd "Failed to rename etcd to etcd-old--${ETCD_BACKUP_TIME}, aborting script!"

echo "${red}Stopping original etcd container${reset}"
docker stop etcd-old--${ETCD_BACKUP_TIME}
checkpipecmd "Failed to stop etcd-old--${ETCD_BACKUP_TIME}"

if [[ "$FORCE_NEW_CLUSTER" == "yes" ]]; then
        echo "${red}Copying old etcd data directory /opt/rke/var/lib/etcd to /opt/rke/var/lib/etcd-old--${ETCD_BACKUP_TIME}${reset}"
        rootcmd "cp -arfv /opt/rke/var/lib/etcd /opt/rke/var/lib/etcd-old--${ETCD_BACKUP_TIME}"
        checkpipecmd "Failed to copy /opt/rke/var/lib/etcd to /opt/rke/var/lib/etcd-old--${ETCD_BACKUP_TIME}, aborting script!"
else
        echo "${red}Moving old etcd data directory /opt/rke/var/lib/etcd to /opt/rke/var/lib/etcd-old--${ETCD_BACKUP_TIME}${reset}"
        rootcmd "mv /opt/rke/var/lib/etcd /opt/rke/var/lib/etcd-old--${ETCD_BACKUP_TIME}"
fi

ETCD_HOSTNAME=$(sed 's,^.*--hostname=\([^ ]*\).*,\1,g' <<<$RUNLIKE)
ETCDCTL_ENDPOINT="https://0.0.0.0:2379"
ETCDCTL_CACERT=$(sed 's,^.*ETCDCTL_CACERT=\([^ ]*\).*,\1,g' <<<$RUNLIKE)
ETCDCTL_CERT=$(sed 's,^.*ETCDCTL_CERT=\([^ ]*\).*,\1,g' <<<$RUNLIKE)
ETCDCTL_KEY=$(sed 's,^.*ETCDCTL_KEY=\([^ ]*\).*,\1,g' <<<$RUNLIKE)
ETCD_VERSION=$(sed 's,^.*rancher/coreos-etcd:\([^ ]*\).*,\1,g' <<<$RUNLIKE)
INITIAL_ADVERTISE_PEER_URL=$(sed 's,^.*initial-advertise-peer-urls=\([^ ]*\).*,\1,g' <<<$RUNLIKE)
ETCD_NAME=$(sed 's,^.*name=\([^ ]*\).*,\1,g' <<<$RUNLIKE)
INITIAL_CLUSTER=$(sed 's,^.*--initial-cluster=.*\('"$ETCD_NAME"'\)=\([^,^ ]*\).*,\1=\2,g' <<<$RUNLIKE)
ETCD_SNAPSHOT_LOCATION='/etc/kubernetes/snapshot.db'
INITIAL_CLUSTER_TOKEN=$(sed 's,^.*initial-cluster-token=\([^ ]*\).*,\1,g' <<<$RUNLIKE)

if [[ "$FORCE_NEW_CLUSTER" != "yes" ]]; then
        RESTORE_RUNLIKE='docker run
--name=etcd-restore
--hostname='$ETCD_HOSTNAME'
--env="ETCDCTL_API=3"
--env="ETCDCTL_ENDPOINT='$ETCDCTL_ENDPOINT'"
--env="ETCDCTL_CACERT='$ETCDCTL_CACERT'"
--env="ETCDCTL_CERT='$ETCDCTL_CERT'"
--env="ETCDCTL_KEY='$ETCDCTL_KEY'"
--env="PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
--volume="/opt/rke/var/lib/etcd:/var/lib/rancher/etcd/:z"
--volume="/opt/rke/etc/kubernetes:/etc/kubernetes:z"
--volume="/opt/rke:/opt/rke:z"
--network=host
--label io.rancher.rke.container.name="etcd"
-ti rancher/coreos-etcd:'$ETCD_VERSION' /usr/local/bin/etcdctl snapshot restore '$ETCD_SNAPSHOT_LOCATION'
--initial-advertise-peer-urls='$INITIAL_ADVERTISE_PEER_URL'
--initial-cluster='$INITIAL_CLUSTER'
--initial-cluster-token='$INITIAL_CLUSTER_TOKEN'
--data-dir=/opt/rke/etcd
--name='$ETCD_NAME''

        #RESTORE ETCD
        echo "${red}Restoring etcd snapshot${reset}"
        echo $RESTORE_RUNLIKE
        eval $RESTORE_RUNLIKE
        checkpipecmd "Failed to restore etcd snapshot!"
        #echo ${green}Sleeping for 10 seconds so etcd can do its restore${reset}
        #sleep 10

        echo "${red}Stopping etcd-restore container${reset}"
        docker stop etcd-restore

        echo ${red}Moving restored etcd directory in place${reset}
        rootcmd "mv /opt/rke/etcd /var/lib/"

        echo ${red}Deleting etcd-restore container${reset}
        docker rm -f etcd-restore
fi

#INITIALIZE NEW RUNLIKE
NEW_RUNLIKE=$RUNLIKE

#ADD --force-new-cluster
NEW_RUNLIKE=$(sed 's,^\(.*'$ETCD_VERSION' \)\([^ ]*\)\(.*\),\1\2 --force-new-cluster\3,g' <<<$NEW_RUNLIKE)

#REMOVE OTHER ETCD NODES FROM --initial-cluster
ORIG_INITIAL_CLUSTER=$(sed 's,^.*initial-cluster=\([^ ]*\).*,\1,g' <<<$RUNLIKE)
NEW_RUNLIKE=$(sed 's`'"$ORIG_INITIAL_CLUSTER"'`'"$INITIAL_CLUSTER"'`g' <<<$NEW_RUNLIKE)

#CHANGE NAME TO etcd-reinit
NEW_RUNLIKE=$(sed 's`'--name=etcd'`'--name=etcd-reinit'`g' <<<$NEW_RUNLIKE)

#REINIT ETCD
echo "${red}Running etcd-reinit${reset}"
echo $NEW_RUNLIKE
eval $NEW_RUNLIKE
checkpipecmd "Failed to run etcd-reinit!"
echo "${green}Sleeping for 10 seconds so etcd can do reinit things${reset}"
sleep 10

#echo ${green}Tailing last 40 lines of etcd-reinit${reset}
#docker logs etcd-reinit --tail 40

#STOP AND REMOVE etcd-reinit
echo "${red}Stopping and removing etcd-reinit${reset}"
docker stop etcd-reinit
docker rm -f etcd-reinit

#CHANGE NAME BACK TO etcd
NEW_RUNLIKE=$(sed 's`'--name=etcd-reinit'`'--name=etcd'`g' <<<$NEW_RUNLIKE)

#REMOVE --force-new-cluster
NEW_RUNLIKE=$(sed 's`--force-new-cluster ``g' <<<$NEW_RUNLIKE)

#FINALLY RUN NEW SHINY RESTORED ETCD
echo "${red}Launching shiny new etcd${reset}"
echo $NEW_RUNLIKE
eval $NEW_RUNLIKE
checkpipecmd "Failed to launch shiny new etcd!"
echo "${green}Script sleeping for 5 seconds${reset}"
sleep 5
echo

echo "${red}Restarting kubelet and kube-apiserver if they exist${reset}"
docker restart kubelet kube-apiserver

if [[ "$FORCE_NEW_CLUSTER" != "yes" ]]; then
        echo "${red}Removing /etc/kubernetes/snapshot.db${reset}"
        #rootcmd "mv /etc/kubernetes/snapshot.db /etc/kubernetes/snapshot.db--${ETCD_BACKUP_TIME}"
        rootcmd "rm -f /etc/kubernetes/snapshot.db"
fi

echo "${red}Setting etcd restart policy to always restart${reset}"
docker update --restart=always etcd

#PRINT OUT MEMBER LIST
#CHECK IF WE NEED TO ADD --endpoints TO THE COMMAND
echo "${green}Running an 'etcdctl member list' as a final test.${reset}"
REQUIRE_ENDPOINT=$(docker exec etcd netstat -lpna | grep \:2379 | grep tcp | grep LISTEN | tr -s ' ' | cut -d' ' -f4)
if [[ $REQUIRE_ENDPOINT =~ ":::" ]]; then
        echo "${green}etcd is listening on ${REQUIRE_ENDPOINT}, no need to pass --endpoints${reset}"
        docker exec etcd etcdctl member list
else
        echo "${green}etcd is only listening on ${REQUIRE_ENDPOINT}, we need to pass --endpoints${reset}"
        docker exec etcd etcdctl --endpoints ${REQUIRE_ENDPOINT} member list
fi

echo "${green}Single restore has completed, please be sure to restart kubelet and kube-apiserver on other nodes.${reset}"
echo "${green}If you are planning to rejoin another node to this etcd cluster you'll want to use etcd-join.sh on that node${reset}"
