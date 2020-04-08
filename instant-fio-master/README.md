# instant-fio-master.sh
Simple script to install fio from source.  It does the following:

- Installs dependencies automatically on RedHat and Debian based operating systems.
- clones fio master branch
- compiles fio from source then performs a make install
- updates ~/.bash_profile to add /usr/local/bin/ to your PATH if it isn't already there

Usage:
```
curl -LO https://github.com/patrick0057/instant-fio-master/raw/master/instant-fio-master.sh
bash instant-fio-master.sh
```
