# nimbusapp
Script to make starting demo containers easier.

This script is based on the images in https://hub.docker.com/u/admpresales

## Installation

Download the latest .tar.gz release from https://github.com/admpresales/nimbusapp/releases by executing the following command from a terminal window:

```
wget -nv https://github.com/admpresales/nimbusapp/releases/latest/download/nimbusapp.tar.gz
```

Extract the downloaded file to /usr/local/bin

```
sudo tar -xzf nimbusapp.tar.gz -C /usr/local/bin
```

### Verify

To verify your installation, run the `nimbusapp version` command and compare the reported version to the release you intended to install.

```
demo@nimbusserver Downloads]$ nimbusapp version
nimbusapp version N.N.N
Released on YYYY-MM-DD
```

### Troubleshooting

If `nimbusapp version` does not return the correct version, another copy may be installed on your system. Use the `which` command to check where your copy of nimbusapp is located.

```
[demo@nimbusserver ~]$ which nimbusapp
~/bin/nimbusapp
```

You may need to remove or rename extra copies of the script until the correct script is detected:

```
[demo@nimbusserver ~]$ rm ~/bin/nimbusapp 
[demo@nimbusserver ~]$ which nimbusapp
/usr/local/bin/nimbusapp
```

## Running

Please refer to the individual images on [ADM Presales Docker Hub](https://hub.docker.com/u/admpresales)
for instructions and sample commands for running nimbusapp.
