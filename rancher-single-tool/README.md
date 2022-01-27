# rancher-single-tool
This script simplifies the process for upgrading, backing up, restoring and installing single server rancher installations.  This script also has a recovery option (-i/-I) for creating rancher backup images from docker volumes.  Please see the script's help menu (option -h) for a full list of options.  You are able to pass enough options to make the script fully automatic or you can pass no options and the script will prompt you for everything.

Usage:
```bash
curl -LOs https://raw.githubusercontent.com/rancherlabs/support-tools/master/rancher-single-tool/rancher-single-tool.sh
bash rancher-single-tool.sh -h
```

### Troubleshooting
I tried to make the script handle most situations gracefully however if you find that the script has crashed or you had to abort for some reason, the most you will usually need to do in order to recover is to restart your Rancher container manually.  Every task in the script that involves doing something to a Rancher container will perform a backup before it begins (automatically).  This means that if you specified option -x to have the script delete your old rancher container after a restore or upgrade and something goes wrong, you will still have a backup to restore from if the old Rancher container was deleted.
