# rancher-resource-enumerator

Rancher Custom Resource enumeration script

## Dependencies

* `kubectl`
* Linux, MacOS or WSL2

## How to use

* Download the script and save as: `rancher-resource-enumerator.sh`
* Make sure the script is executable: `chmod u+x ./rancher-resource-enumerator.sh`
* Run the script: `./rancher-resource-enumerator.sh`

The script will output all Rancher custom resource data in the `/tmp/enum-cattle-resources-<timestamp>` directory by default. The `totals` file will give the total count for all resources.

## Flags

```
Rancher Resource Enumerator
Usage: ./rancher-resource-enumerator.sh [ -d <directory> ]
 -h                               Display this help message.
 -p <directory>                   Path to output directory (default: /tmp/enum-cattle-resources-<timestamp>).
```
