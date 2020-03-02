# nimbusapp
Script to make starting demo containers easier.

This script is based on the images in https://hub.docker.com/u/admpresales

## Installation

Download the latest .tar.gz release from https://github.com/admpresales/nimbusapp/releases by executing the following commands from a terminal window:

```
[demo@nimbusserver ~]$ cd ~/Downloads
[demo@nimbusserver Downloads]$ wget -nv https://github.com/admpresales/nimbusapp/releases/latest/download/nimbusapp.tar.gz

```

Extract the downloaded file to /usr/local/bin:

```
[demo@nimbusserver Downloads]$ sudo tar -xzf nimbusapp.tar.gz -C /usr/local/bin
```

### Verify

To verify your installation, run the `nimbusapp version` command and compare the reported version to the release you intended to install:

```
[demo@nimbusserver Downloads]$ nimbusapp version
nimbusapp version N.N.N
Released on YYYY-MM-DD
```

### Troubleshooting

If `nimbusapp version` does not return the correct version, another copy may be installed on your system. Use the `which` command to check where your copy of nimbusapp is located:

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

## Using Nimbusapp

This section provides basic usage instructions.
Please refer to the individual dockerapp entries on [ADM Presales Docker Hub](https://hub.docker.com/u/admpresales)
for image specific instructions.

Examples use the [Nimbusapp Test Image](./tests/nimbusapp-test.dockerapp), which starts a single container with a lightweight web server.

See the [Usage Text](./USAGE.txt) or `nimbusapp help` for more information.

Please refer to the individual images on [ADM Presales Docker Hub](https://hub.docker.com/u/admpresales) for image-specific instructions and examples.

### Gerneral Format

Where possible commands mirror the `docker-compose` features which are used under the covers.

```
nimbusapp <image> <command>
```

### Create Containeres

Using the `up` command will pull images, create containers and start the containers all in one operation.

Version numbers are only required the first time an image is pulled, and will be remembered for future commands.

```
[demo@nimbusserver nimbusapp]$ nimbusapp nimbusapp-test:0.1.0 up
Authenticating with existing credentials...
Login Succeeded
Creating nimbusapp-test-web ... done
```

To create containers from an image without starting the containers immediately, use the `--no-start` option:

```
[demo@nimbusserver nimbusapp]$ nimbusapp nimbusapp-test:0.1.0 up --no-start
```

### Check Container Status

To verify the state of a container, use the `ps` command.

```
[demo@nimbusserver nimbusapp]$ nimbusapp nimbusapp-test ps
       Name              Command        State           Ports
---------------------------------------------------------------------
nimbusapp-test-web   httpd-foreground   Up      0.0.0.0:12345->80/tcp

```

### Starting Containers

To start existing containers, use the `start` command.

```
[demo@nimbusserver nimbusapp]$ nimbusapp nimbusapp-test start
Starting web ... done
```


### Stopping Containers

To stop running containers, use the `stop` command.

```
[demo@nimbusserver nimbusapp]$ nimbusapp nimbusapp-test stop
Stopping nimbusapp-test-web ... done
```

### Delete Containers

```
[demo@nimbusserver nimbusapp]$ nimbusapp nimbusapp-test down

This action will DELETE your containers and is IRREVERSIBLE!

You may wish to use `nimbusapp ... stop' to shut down your containers without deleting them

The following containers will be deleted:
- /nimbusapp-test-web

Do you wish to DELETE these containers? [y/n] y
Stopping nimbusapp-test-web ... done
Removing nimbusapp-test-web ... done
```
