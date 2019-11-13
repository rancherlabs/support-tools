# logs-collector

The script needs to be downloaded and run directly on the host using the `root` user or using `sudo`.

## How to use

* Download the script and save as: `rancher_logs_collector.sh`
* Make sure the script is executable: `chmod +x rancher_logs_collector.sh`
* Run the script: `./rancher_logs_collector.sh`

## Options

* `-d directory`: Change output directory (`-d /var/tmp`)
* `-s time`: Specify Docker logs since parameter (`-s 2h`)
