# cluster-agent-tool.sh
This script will help you retrieve redeployment commands for rancher agents as well as docker run commands to start new agent containers.  Depending on the options specified below you can also have the script automatically run these commands for you.

Download and help instructions:

```bash
curl -LO https://github.com/patrick0057/cluster-agent-tool/raw/master/cluster-agent-tool.sh
bash cluster-agent-tool.sh -h

#RancherOS
wget https://github.com/patrick0057/cluster-agent-tool/raw/master/cluster-agent-tool.sh
bash cluster-agent-tool.sh -h
```

The most basic way to use this script is to let it do everything except running the commands automatically for you and prompt you for your Rancher server password as shown below.  Please see the help menu for all available options.

```bash
curl -LO https://github.com/patrick0057/cluster-agent-tool/raw/master/cluster-agent-tool.sh
bash cluster-agent-tool.sh -y
```
