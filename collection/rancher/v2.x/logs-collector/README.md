# logs-collector

The script needs to be downloaded and run directly on the node using the `root` user or using `sudo`.

## How to use

* Download the script and save as: `rancher_logs_collector.sh`
* Make sure the script is executable: `chmod +x rancher_logs_collector.sh`
* Run the script: `./rancher_logs_collector.sh`

The script will create a .tar.gz log collection in /tmp by default, all flags are optional.

## Flags

```
Rancher 2.x logs-collector
  Usage: rancher2_logs_collector.sh [ -d <directory> -s <days> -r <k8s distribution> -p -f ]

  All flags are optional

  -c    Custom data-dir for RKE2 (ex: -c /opt/rke2)
  -d    Output directory for temporary storage and .tar.gz archive (ex: -d /var/tmp)
  -s    Start day of journald and docker log collection. Specify the number of days before the current time (ex: -s 7)
  -e    End day of journald and docker log collection. Specify the number of days before the current time (ex: -e 5)
  -r    Override k8s distribution if not automatically detected (rke|k3s|rke2)
  -p    When supplied runs with the default nice/ionice priorities, otherwise use the lowest priorities
  -f    Force log collection if the minimum space isn't available
```
