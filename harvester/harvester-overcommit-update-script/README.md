# Harvester Overcommit Update Script
A simple Bash script for updating all the VMs in a Harvester cluster with the current overcommit settings. This script obtains the current overcommit settings and iterates over all the VMs to get the CPU & Memory Limits and sets the CPU & Memory requests & limits.

## Setup
1. Edit the `update_overcommit.sh` file and replace the following line with the path to your KUBECONFIG file.
```
export KUBECONFIG=<path_to_kubeconfig>
```

2. Make the script executable
```
chmod +x ./update_overcommit.sh
```

3. Run the script
```
sh ./update_overcommit.sh
```
