#!/bin/bash
newowner=''
clusterid=''
red=$(tput setaf 1)
green=$(tput setaf 2)
reset=$(tput sgr0)
function helpmenu () {
        echo "Change the owner of all node templates in a cluster:
    ${green}change-nodetemplate-owner.sh -c <cluster-id> -n <new-owner-id>${reset}

Assign a nodetemplate to a cluster's nodepool.  This is useful 
for situations where the original owner of a cluster has been deleted 
which also deletes their nodetemplates.  To use this task successfully 
it is recommended that you create a new nodetemplate in the UI before 
using it.  Make sure the node template matches the original ones as 
closely as possible.  You will be shown options to choose from and
prompted for confirmation.
    ${green}change-nodetemplate-owner.sh -t changenodetemplate -c <cluster-id>${reset}
"
        exit 1
}
while getopts "hc:n:t:" opt; do
    case ${opt} in
    h) # process option h
        helpmenu
        ;;
    c) # process option c
        clusterid=$OPTARG
        ;;
    n) # process option n
        newowner=$OPTARG
        ;;
    t) # process option t
        task=$OPTARG
        ;;
    \?)
        helpmenu
        exit 1
        ;;
    esac
done
#shift $((OPTIND -1))
if [[ -z "$task" ]] && [ -z "$clusterid" ]; then
    helpmenu
    exit 1
fi
if ! hash kubectl 2>/dev/null; then
    echo "!!!kubectl was not found!!!"
    echo "!!!download and install with:"
    echo "Linux users:"
    echo "curl -LO https://storage.googleapis.com/kubernetes-release/release/$(curl -s https://storage.googleapis.com/kubernetes-release/release/stable.txt)/bin/linux/amd64/kubectl"
    echo "chmod +x ./kubectl"
    echo "mv ./kubectl /bin/kubectl"
    echo "!!!"
    echo "Mac users:"
    echo "brew install kubernetes-cli"
    exit 1
fi
if ! hash jq 2>/dev/null; then
    echo '!!!jq was not found!!!'
    echo "!!!download and install with:"
    echo "Linux users:"
    echo "curl -L -O https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64"
    echo "chmod +x jq-linux64"
    echo "mv jq-linux64 /bin/jq"
    echo "!!!"
    echo "Mac users:"
    echo "brew install jq"
    echo "brew link jq"
    exit 1
fi
if ! hash sed 2>/dev/null; then
    echo '!!!sed was not found!!!'
    exit 1
fi
if [ ! -f ~/.kube/config ] && [ -z "$KUBECONFIG" ]; then
    echo "${red}~/.kube/config does not exist and \$KUBECONFIG is not set!${reset} "
    exit 1
fi
function yesno () {
    shopt -s nocasematch
    response=''
    i=0
    while [[ ${response} != 'y' ]] && [[ ${response} != 'n' ]]
    do
        i=$((i+1))
        if [ $i -gt 10 ]; then
            echo "Script is destined to loop forever, aborting!  Make sure your docker run command has -ti then try again."
            exit 1
        fi
        printf '(y/n): '
        read -n1 response
        echo
    done
    shopt -u nocasematch
}
echo
kubectl get node
echo

if [ "$task" = '' ]; then
    if [[ -z "$clusterid" ]] || [[ -z "$newowner" ]];
    then
            helpmenu
            exit 1
    fi
    echo -e "${green}Cluster: $clusterid${reset}"
    echo -e "${green}New Owner: $newowner${reset}"
    for nodepoolid in $(kubectl -n $clusterid get nodepool --no-headers -o=custom-columns=NAME:.metadata.name); do
        nodetemplateid=$(kubectl -n $clusterid get nodepool $nodepoolid -o json | jq -r .spec.nodeTemplateName | cut -d : -f 2)
        oldowner=$(kubectl -n $clusterid get nodepool $nodepoolid -o json | jq -r .spec.nodeTemplateName | cut -d : -f 1)
        echo -e "${red}creating new nodetemplate under $newowner's namespace${reset}"
        kubectl -n $oldowner get nodetemplate $nodetemplateid -o yaml | sed 's/'$oldowner'/'$newowner'/g' | kubectl apply --namespace=$newowner -f -
        echo -e "${red}patching $nodepoolid old owner: $oldowner new owner: $newowner${reset}"
        kubectl -n $clusterid patch nodepool $nodepoolid -p '{"spec":{"nodeTemplateName": "'$newowner:$nodetemplateid'"}}' --type=merge
    done
    echo
    echo
    echo -e "${green}We're all done!  If see you kubectl complaining about duplicate nodetemplates, this is safe to ignore.${reset}"
fi

if [ "$task" = 'changenodetemplate' ]; then
    if [ -z "$clusterid" ]
    then
            helpmenu
            exit 1
    fi
    for nodepoolid in $(kubectl -n $clusterid get nodepool --no-headers -o=custom-columns=NAME:.metadata.name); do
        nodetemplateid=$(kubectl -n $clusterid get nodepool $nodepoolid -o json | jq -r .spec.nodeTemplateName | cut -d : -f 2)
        hostnameprefix=$(kubectl -n $clusterid get nodepool $nodepoolid -o json | jq -r .spec.hostnamePrefix | cut -d : -f 2)
        oldowner=$(kubectl -n $clusterid get nodepool $nodepoolid -o json | jq -r .spec.nodeTemplateName | cut -d : -f 1)
        echo "${green}-----------------------------------------------------------------------${reset}"
        echo "${green}Name prefix: ${hostnameprefix}${reset}"
        echo "${green}Nodepool ID: ${nodepoolid}${reset}"
        echo "${green}Owner ID: ${oldowner}${reset}"
        echo "${green}Nodetemplate ID: ${nodetemplateid}${reset}"
        echo "Would you like to change the node template for nodepool called ${hostnameprefix}?"
        
        yesno
        if [ ${response} == 'y' ]
        then
            echo "nodetemplate ID's available for selection: "
            echo "${green}-${reset}"
            IFS=$'\n'
            echo "${green}name: ID${reset}"
            for nt_namespace_name in $(kubectl get nodetemplate --all-namespaces -o=custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name --no-headers); do
                nodetemplateid1=$(echo ${nt_namespace_name} | sed -e's/  */ /g' | cut -d" " -f 2)
                oldowner1=$(echo ${nt_namespace_name} | sed -e's/  */ /g' | cut -d" " -f 1)
                nodetemplateid_displayname1=$(kubectl -n $oldowner1 get nodetemplate $nodetemplateid1 -o json | jq -r .spec.displayName | cut -d : -f 2)
                echo "${green}${nodetemplateid_displayname1}: ${nodetemplateid1}${reset}"
            done
            IFS=$' '
            echo "${green}-${reset}"
            echo "What should the new nodetemplate ID be?"
            read new_nodetemplateid
            echo "I have ${new_nodetemplateid}, should I proceed?"
            yesno
            if [ ${response} == 'y' ]
            then
                echo "${green}OK making changes${reset}"
                echo -e "${red}patching $nodepoolid old template ID: $nodetemplateid new template ID: ${new_nodetemplateid}${reset}"
                kubectl -n $clusterid patch nodepool $nodepoolid -p '{"spec":{"nodeTemplateName": "'$oldowner:${new_nodetemplateid}'"}}' --type=merge
            else
                echo "${green}No changes made, moving on.${reset}"
            fi
        fi

    done
        echo "${green}-----------------------------------------------------------------------${reset}"
fi
