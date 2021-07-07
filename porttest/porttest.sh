#!/bin/bash
if hash tput 2>/dev/null; then
    red=$(tput setaf 1)
    green=$(tput setaf 2)
    reset=$(tput sgr0)
fi
grecho () {
    echo "${green}$1${reset}"
}
recho () {
    echo "${red}$1${reset}"
}
TCP_PORTS="80 443 22 2379 6443 2376 2380 3389 9099 10250 10254 30000"
UDP_PORTS="8472 30000"
#dependencies
if ! hash nc 2>/dev/null; then
    recho '!!!nc (netcat) was not found!!!'
    recho "Please install nc (netcat) with your package manager"
    exit 1
fi
if ! hash pgrep 2>/dev/null; then
    recho '!!!pgrep was not found!!!'
    recho "Please install pgrep with your package manager"
    exit 1
fi

spawn_netcat() {
    grecho "Spawning netcat processes, you may see errors about ports in use.  If so, you'll need to figure out what processes are using those ports, stop them then start over."
    
    if [ -f "TCP_working_ports.txt" ]; then
        grecho "Deleting stale TCP_working_ports.txt"
        rm -f TCP_working_ports.txt
    fi
    if [ -f "UDP_working_ports.txt" ]; then
        grecho "Deleting stale UDP_working_ports.txt"
        rm -f UDP_working_ports.txt
    fi
    grecho "TCP:"
    for i in ${TCP_PORTS}; do
        nc -kl "${i}" >>"TCP_working_ports.txt" 2> /dev/null &
        if ! ps -p $! > /dev/null; then
            recho "Could not bind TCP port ${i}"
        fi
    done

    echo
    grecho "Please be aware that if an incomming connection hits your UDP port before the test script, you will get a false negative."
    grecho "UDP:"
    for i in ${UDP_PORTS}; do
        nc -lu "${i}" >>"UDP_working_ports.txt" 2> /dev/null &
            if ! ps -p $! > /dev/null; then
                recho "Could not bind UDP port ${i}"
            fi
    done

}

cleanup() {
    recho "Deleting TCP_working_ports.txt and UDP_working_ports.txt"
    rm -f rm -f TCP_working_ports.txt UDP_working_ports.txt
}
kill_netcat() {
    recho "Killing all nc processes"
    pgrep -x nc
    OLDIFS="${IFS}"
    IFS=$'\n'
    PIDS="$(pgrep -x nc)"
    for i in ${PIDS}; do
        kill -9 "${i}"
    done
    IFS=${OLDIFS}
    echo
    grecho "Displaying output of pgrep -x nc:"
    pgrep -x nc
}

send_packets() {
    grecho "Sending test packets to ${REMOTE_HOST}"
    grecho "Sending TCP."
    for i in ${TCP_PORTS}; do
        echo "${i}"| nc -q0 "${REMOTE_HOST}" "${i}" &> /dev/null
    done
    echo
    grecho "Please be aware that if an incomming connection hit your UDP port before the test script, you will see a false negative."
    grecho "Sending UDP."
    for i in ${UDP_PORTS}; do
        echo "${i}" > /dev/udp/"${REMOTE_HOST}"/"${i}"
    done
}

results() {
    grecho "The following TCP ports are not working:"
    for i in ${TCP_PORTS}; do
        if ! grep -w "${i}" TCP_working_ports.txt &>/dev/null; then
            echo "${i}"
        fi
    done

    grecho "The following UDP ports are not working:"
    for i in ${UDP_PORTS}; do
        if ! grep -w "${i}" UDP_working_ports.txt &>/dev/null; then
            echo "${i}"
        fi
    done
    echo
    grecho "Please keep in mind that if any ports failed to bind in the -l step, you will see them as failed here."
}


helpmenu() {
    grecho "This script will assist you in testing open ports for your Rancher environments.


Usage: bash ${SCRIPT_NAME}
    -h              Shows this help menu

    -l              Spawn netcat processes to listen on test ports.

    -t <PORTS>      Set custom TCP ports (list separated by spaces).

    -u <PORTS>      Set custom UDP ports (list separated by spaces).

    -c              Cleanup porttest directories.

    -k              Kill all spawned netcat processes.

    -s <IP>         Send packets to listening server.

    -r              Print results.
"
    exit 1
}

while getopts "hcks:rlt:u:" opt; do
    case ${opt} in
    h) # process option h
        helpmenu
        ;;
    c) # process option c: cleanup directories
        cleanup
        ;;

    k) # process option k: kill netcat processes
        kill_netcat
        ;;
    t) # process option t: kill netcat processes
        TCP_PORTS="${OPTARG}"
        ;;
    u) # process option u: kill netcat processes
        UDP_PORTS="${OPTARG}"
        ;;
    l) # process option l: spawn netcat processes
        spawn_netcat
        ;;
    r) # process option r: results
        results
        ;;
    s) # process option s: results
        REMOTE_HOST="${OPTARG}"
        send_packets
        ;;
    \?)
        helpmenu
        exit 1
        ;;
    esac
done
