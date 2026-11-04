# harvester-overcommit-update-script
A simple Bash script for updating all the VMs in a Harvester cluster with the current overcommit settings.

## Setup
1. Make the script executable
```
chmod +x ./update_overcommit.sh
```
2. Run the `update_overcommit.sh` file and designate the path to your _kube config_ file with the `--kubeconfig` flag
```
./update_overcommit.sh --kubeconfig <path_to_kubeconfig>
```

## Additional Options
You can use the following flags
* `-h` for a list of the flags
* `--kubeconfig` (`-k`) to specify the path of the kubeconfig file`
* `--wait` (`-w`) to modify the wait time in seconds before checking if the changes have been applied. The default is 10 seconds.
