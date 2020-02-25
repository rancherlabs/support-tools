#!/bin/bash
red=$(tput setaf 1)
green=$(tput setaf 2)
reset=$(tput sgr0)
START_TIME=$(date +%Y-%m-%d--%H%M%S)
SCRIPT_NAME="instant-fio-master.sh"
function helpmenu() {
    echo "Usage: ${SCRIPT_NAME}
"
    exit 1
}
while getopts "h" opt; do
    case ${opt} in
    h) # process option h
        helpmenu
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
#set os and install dependencies
if [[ -f /etc/lsb_release ]]; then
    OS=ubuntu
    echo You are using Ubuntu
    apt install -y gcc zlib1g-dev make git
fi
if [[ -f /etc/redhat-release ]]; then
    OS=redhat
    echo You are using Red Hat
    yum -y install zlib-devel gcc make git
fi

if ! hash fio 2>/dev/null; then
    git clone git://git.kernel.dk/fio.git
    cd fio
    ./configure
    make
    make install
    if [[ '/usr/local/bin' != *"$PATH"* ]]; then
        export PATH=/usr/local/bin:$PATH
        echo "Run the following command or logout and log back in again so that your .bash_profile can add it for you."
        echo 'export PATH=/usr/local/bin:$PATH'
        echo 'export PATH=/usr/local/bin:$PATH' >>~/.bash_profile
    fi
else
    echo "fio is already installed."
fi
