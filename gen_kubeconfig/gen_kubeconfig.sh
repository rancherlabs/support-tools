#!/bin/bash

#------------------------------------------------------------------------------#
# This script will generate kubeconfig file using certificates instead of token#
#------------------------------------------------------------------------------#
#
#         Script will try to use openssl first. If openssl not present then,
# cfssl & cfssljon binaries will be downloaded to the system. If script cannot
# download the binaries; instructions will be printed on the screen to download
# them manually.
#
#------------------------------------------------------------------------------#
# Author: Ansil H
#------------------------------------------------------------------------------#

# We expect the tools in local directory
export PATH="${PATH}:."

# Variables to store Kubernetes API Server IP:Port
API_SERVER_IP_PORT="127.0.0.1:6443"
TMP_DIR=""

# Path where RKE stores certificates
SSL_PATH="/etc/kubernetes/ssl"
LOG_PATH=${0}.log
# Function to print message to STDOUT
msg(){
        DATE=$(date "+%Y/%m/%d %T")
	case $1 in
            "INFO")
		echo -e "${DATE} [INFO] $2"
                ;;
            "WARN")
                echo -e "${DATE} [WARNING] $2"
                ;;
            "ERRO")
                echo -e "${DATE} [ERROR] $2"
                ;;
            *)
                echo -e "${DATE} [EXCEPTION] $2"
                ;;
        esac
}

# Tools will work only on Linux , but below varible will help to add more arch/OS support in future
OS=$(uname |tr '[:upper:]' '[:lower:]')
if [ "${OS}" != "linux" ]
then
        msg ERRO "This script runs only on Linux platform"
fi
case $(uname -m) in
        "x86_64")
                BIN_TYPE="amd64"
                ;;
esac

# cfssl URLs
CFSSL_BIN_BASE="https://pkg.cfssl.org"
CFSSL_LINUX_URL=${CFSSL_BIN_BASE}"/R1.2/cfssl_${OS}-${BIN_TYPE}"
CFSSL_LINUX_JSON_URL=${CFSSL_BIN_BASE}"/R1.2/cfssljson_${OS}-${BIN_TYPE}"

# Kubernetes binary URLs
K8S_VERSION=$(docker ps |grep kube-apiserver |grep "rancher/hyperkube" |awk '{print $2}' |awk -F ":" '{print $2}' |awk -F "-" '{print $1}')
if [ -z "${K8S_VERSION}" ]
then
        msg ERRO "Unable to determine kubernetes version"
        exit 255
fi

K8S_BIN_BASE="https://storage.googleapis.com/kubernetes-release/release/${K8S_VERSION}"
K8S_CTL_URL="${K8S_BIN_BASE}/bin/${OS}/${BIN_TYPE}/kubectl"

# List of binaries needed to execute this script
# binaryname|URL|Permission
BIN_LIST="
kubectl|${K8S_CTL_URL}|755
cfssl|${CFSSL_LINUX_URL}|755
cfssljson|${CFSSL_LINUX_JSON_URL}|755
"

# Create 'downloads' directory
createTemDir(){
        TMP_DIR="downloads"
        if [ ! -d ${TMP_DIR} ]
        then
                mkdir ${TMP_DIR}
        fi
        pushd ${TMP_DIR} 1>/dev/null 2>&1
}

# Delete 'downloads' directory
deleteTempDir(){
        read -p "Do you want to cleanup the unwanted files?[no]" ANS
        ANSW=${ANS=n}
        case $ANSW in
                y|Y|Yes|yes|YES) rm -fr ${TMP_DIR}
                        ;;
                *) return 1
                        ;;
        esac
}

checkDockerAccess(){
        docker info >/dev/null 2>&1
        if [ $? -eq 0 ]
        then
                msg INFO "Verfied docker access"
                return 0
        else
                msg ERRO "Either Docker is not running or the user have no docker access"
                return 1
        fi
}

checkControllerNode(){
        if checkDockerAccess
        then
                docker inspect kube-apiserver >/dev/null 2>&1
                if [ $? -eq 0 ]
                then
                        msg INFO "API server is running"
                        return 0
                else
                        msg ERRO "API server is not running; make sure to run this script on a working controller node"
                        return 1
                fi

        fi
}

# Check the existance of a given binary in PWD
checkBinary(){
        if [ -x ${1} ]
        then
                msg INFO "Binary ${1} present"
                return 0
        else
                msg WARN "Binary ${1} not present or not executable"
                return 1
        fi
}

downloadBinary(){
        curl --progress-bar ${1} -o ${2}
        if [ $? -eq 0 ]
        then
                chmod ${3} ${2}
                return 0
        else
                msg ERRO "Unable to download ${2}"
                return 1
        fi
}

downloadFromURL(){
        if ! checkBinary ${2}
        then
                CONTENT_LEN=$(curl -sLIXGET ${1} | awk 'BEGIN {IGNORECASE=1};/^content-length:/{print $2}'| tail -1 |tr -d '\r')
                if [ -z ${CONTENT_LEN} ]
                then
                        msg WARN "Unable to access ${1}"
                        return 1
                else
                        msg INFO "Downloading ${CONTENT_LEN} Bytes file from ${1}"
                        if downloadBinary ${1} ${2} ${3}
                        then
                                msg INFO "Downloaded ${2}"
                                return 0
                        else
                                msg WARN "Unable to download ${2}"
                                return 1
                        fi
                fi
        else
                return 0
        fi
}

setupCACerts(){
        if [ ! -f kube-ca.pem ] || [ ! -f kube-ca-key.pem ]
        then
                if [ -f  ${SSL_PATH}/kube-ca.pem ] && [ -f  ${SSL_PATH}/kube-ca.pem ]
                then
                        msg INFO "Copying CA certs from ${SSL_PATH} (need root)"
                        sudo cp -p ${SSL_PATH}/kube-ca.pem .
                        sudo cp -p ${SSL_PATH}/kube-ca-key.pem .
                        sudo chown ${USER}:${USER} kube-ca.pem kube-ca-key.pem
                        return 0
                else
                        msg ERRO "Unable to locate Kubertes CA certificates from ${SSL_PATH}"
                        return 1
                fi
        fi
}

setupCA(){
        if setupCACerts
        then
                setupCAConfigs
        fi
}

openSSL(){
        OPENSSL_PATH=$(which openssl)
        if [ $? -eq 0 ]
        then
            return 0
        else
            return 1
        fi
}

#############################

setupOpenSSL(){
        if [ ! -f admin-key.pem ]
        then
                msg INFO "OpenSSL:creating client key"
                openssl genrsa -out admin-key.pem 2048 >/dev/null 2>&1
        else
                msg INFO "OpenSSL:Using exisiting client key"
        fi
        if [ ! -f csr.conf ]
        then
        cat >csr.conf <<EOF
[ req ]
default_bits = 2048
prompt = no
default_md = sha256
req_extensions = req_ext
distinguished_name = dn

[ dn ]
C = US
ST = California
L = Sanjose
O = "system:masters"
OU = Support
CN = 127.0.0.1

[ req_ext ]
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = kubernetes
DNS.2 = kubernetes.default
DNS.3 = kubernetes.default.svc
DNS.4 = kubernetes.default.svc.cluster
DNS.5 = kubernetes.default.svc.cluster.local
IP.1 = 127.0.0.1

[ v3_ext ]
authorityKeyIdentifier=keyid,issuer:always
basicConstraints=CA:FALSE
keyUsage=keyEncipherment,dataEncipherment
extendedKeyUsage=serverAuth,clientAuth
subjectAltName=@alt_names
EOF
        else
                msg INFO "OpenSSL:Using existing CSR config"
        fi
        if [ ! -f admin.csr ]
        then
                msg INFO "OpenSSL:Creating CSR for client"
                openssl req -new -key admin-key.pem -out admin.csr -config csr.conf >/dev/null 2>&1
        else
                msg INFO "OpenSSL:Using existing CSR file"
        fi

        if [ ! -f admin.pem ]
        then
                msg INFO "OpenSSL:Generating client certificate"
                openssl x509 -req -in admin.csr -CA kube-ca.pem -CAkey kube-ca-key.pem \
                -CAcreateserial -out admin.pem -days 10000 \
                -extensions v3_ext -extfile csr.conf >/dev/null 2>&1
        else
                msg INFO "OpenSSL:Using existing client certificate"
        fi
}

#############################

setupCAConfigs(){
        if openSSL
        then
            msg INFO "Generating certificates"
            setupOpenSSL
        else
		if ! downloadTool "cfssl"
		then
			printDownload
			exit 255
		fi

		if ! downloadTool "cfssljson"
		then
			printDownload
			exit 255
		fi

            if [ ! -f ca-config.json ]
            then
                    msg INFO "CFSSL:Creating CA config file"
                    cat <<EOF >ca-config.json
{
    "signing": {
        "default": {
            "expiry": "8760h"
        },
        "profiles": {
            "kubernetes": {
                "expiry": "8760h",
                "usages": [
                    "signing",
                    "key encipherment",
                    "server auth",
                    "client auth"
                ]
            }
        }
    }
}
EOF
            else
                    msg INFO "CFSSL:Using existing CA config file"
            fi
            if [ ! -f admin-csr.json ]
            then
                    msg INFO "CFSSL:Creating new CSR"
                    cat > admin-csr.json <<EOF
{
  "CN": "admin",
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "IN",
      "L": "Bangalore",
      "O": "system:masters",
      "OU": "Kubernetes from Rancher",
      "ST": "Karnataka"
    }
  ]
}
EOF
            else
                    msg INFO "CFSSL:Using existing CSR"
            fi
            if [ ! -f admin.pem ]
            then

                 msg INFO "CFSSL:Generating certificates"
                    cfssl gencert \
                    -ca=kube-ca.pem \
                    -ca-key=kube-ca-key.pem \
                    -config=ca-config.json \
                    -profile=kubernetes -hostname=127.0.0.1\
                    admin-csr.json | cfssljson -bare admin
                    if [ $? -ne 0 ]
                    then
                        msg ERRO "Unable to generate certificate"
                        exit 255
                    fi
            else
                    msg INFO "Using existing client certs"
            fi
        fi
}

#Get API server IP (func UNUSED)
getAPI(){
        API_PORT=$(docker inspect kube-apiserver |grep \\-secure-port |head -1 |awk -F "=" '{print $2}' |sed 's/",//')
        API_ADDRESS=$(docker inspect kube-apiserver |grep advertise-address |head -1 |awk -F "=" '{print $2}' |sed 's/",//')
        API_SERVER_IP_PORT="${API_ADDRESS}:${API_PORT}"
}

generateKubeConfig(){
        if copyKubectl
        then
            if [ ! -f admin.kubeconfig ]
            then
                    CLUSTER_NAME="rancher"
                    MSG=$(kubectl config set-cluster ${CLUSTER_NAME} \
                    --certificate-authority=kube-ca.pem \
                    --embed-certs=true \
                    --server=https://${API_SERVER_IP_PORT}\
                    --kubeconfig=admin.kubeconfig)
                    msg INFO "${MSG}"

                    MSG=$(kubectl config set-credentials admin \
                    --client-certificate=admin.pem \
                    --client-key=admin-key.pem \
                    --embed-certs=true \
                    --kubeconfig=admin.kubeconfig)
                    msg INFO "${MSG}"

                    MSG=$(kubectl config set-context default \
                    --cluster=${CLUSTER_NAME} \
                    --user=admin \
                    --kubeconfig=admin.kubeconfig)
                    msg INFO "${MSG}"

                    MSG=$(kubectl config use-context default --kubeconfig=admin.kubeconfig)
                    msg INFO "${MSG}"
            fi
        else
            msg ERRO "Unable to generate kubeconfig, make sure kubectl binary is present"
            exit 255
        fi
}

copyGenFiles(){
        if [ -f ../admin.kubeconfig ] || [ -f ../kubectl ]
        then
                msg WARN "admin.kubeconfig and kubectl were preset , copy new ones from downloads directory if needed"
                return 1
        else
                cp -p admin.kubeconfig ../
                cp -p kubectl ../
        fi
        popd 1>/dev/null 2>&1
        return 0
}

printDownload(){
        msg WARN "Please follow below pre-requisites to execute the script"
        cat <<EOF

1) Download cfssl, cfssljson, kubectl from a system which have access to internet

Eg:-
$ curl -L https://pkg.cfssl.org/R1.2/cfssl_linux-amd64 -o cfssl
$ curl -L https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64 -o cfssljson
$ curl -LO https://storage.googleapis.com/kubernetes-release/release/v1.15.11/bin/linux/amd64/kubectl

3) Copy the downloaded files to 'downloads' directory and give execution permission

$ cd downloads
$ chmod 755 cfssl cfssljson kubectl

3) Execute the script once all these steps are completed

EOF
}
copyKubectl(){
        msg INFO "Fetching kubectl"
        if [ ! -x kubectl ]
        then
        docker cp kube-apiserver:/hyperkube kubectl
        if [ $? -eq 0 ]
        then
            chmod +x kubectl
            return 0

        else
            msg ERRO "Unable to copy kubectl from local system"
            downloadTool "kubectl"
        fi
        else
                msg INFO "Using existing kubectl"
        fi
}

downloadTool(){
        msg INFO "Trying to download ${1}"
        FOUND=0
        for BIN in ${BIN_LIST}
        do
                BIN_NAME=$(echo $BIN|awk -F "|" '{print $1}')
                BIN_URL=$(echo $BIN|awk -F "|" '{print $2}')
                BIN_PERM=$(echo $BIN|awk -F "|" '{print $3}')
                if [ "${1}" == "${BIN_NAME}" ]
                then
                    FOUND=1
                    break
                fi
        done
        if [ ${FOUND} -eq 1  ]
        then
            if ! downloadFromURL "${BIN_URL}" "${BIN_NAME}" "${BIN_PERM}"
            then
                msg WARN "Download ${BIN_NAME} from ${BIN_URL}"
                return 1
            fi
        else
            msg EXCEPTION "Unable to find tool in BIN_LIST"
            exit 255
        fi
}
##########
# Main ()
##########
NO_INTERNET="0"
if checkControllerNode
then
        createTemDir
        setupCA
        generateKubeConfig
        copyGenFiles
        msg INFO "Execute :\n\t# export KUBECONFIG=admin.kubeconfig\n\t#./kubectl get nodes"

fi
