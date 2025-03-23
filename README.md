# thorcon
Thor Container Runtime (**thorcon**) is a simple container runtime written in Zig

`NOTE:` project is in early phase of development and feel free to contribute.  
check available [commands](#commands) and [features](#features) (feel free to contribute)

## Development Environment

* Fedora latest
* Zig version >= 0.14

## Build

```cconsole
$ make build
```

## Tutorial

Lets try to run a container that executes `sleep 30` with thorcon. You may need root permission.

```console
$ mkdir -p /tmp/busybox01/rootfs
$ cd /tmp/busybox01
$ podman export $(podman create busybox) | tar -C rootfs -xvf -
$ cd $OLDPWD
```

At this stage lets generate and update container runetime configuration (for rootless use `--rootless` command flag).

```console
$ ./bin/thorcon spec --bundle=/tmp/busybox01
```

Edit `config.json` and modify `process` section to run `sleep 30`.

```json
  "process": {
    ...
    "args": [
      "sleep", "30"
    ],

  ...
  }
```

Create, list and start a container:

```console
$ ./bin/thorcon create --bundle=/tmp/busybox01 --no-pivot busybox01
$ ./bin/thorcon list
$ ./bin/thorcon start busybox01
```

## Commands

| Command    | Description                                   | State |
| ---------- | --------------------------------------------- | ----- |
| checkpoint | checkpoint a container                        |       |
| create     | create a container                            | ✅    |
| delete     | remove definition for a container             | ✅    |
| exec       | exec a command in a running container         |       |
| list       | list known containers                         | ✅    |
| mounts     | add or remove mounts from a running container |       |
| kill       | send a signal to the container init process   |       |
| ps         | show the processes in the container           |       |
| restore    | restore a container                           |       |
| run        | run a container                               | 🔶    |
| spec       | generate a configuration file                 |       |
| start      | start a container                             | 🔶    |
| state      | output the state of a container               |       |
| pause      | pause all the processes in the container      |       |
| resume     | unpause the processes in the container        |       |
| update     | update container resource constraints         |       |

## Features

| Feature               | Description                                     | State |
| --------------------- | ----------------------------------------------- | ------|
| docker                | running via docker                              |       |
| podman                | running via podman                              |       |
| pivot_root            | change the root directory                       |       |
| mounts                | mount files and directories to container        |       |
| namespaces            | isolation of various resources                  |       |
| capabilities          | limiting root privileges                        |       |
| cgroups v1            | resource limitation                             |       |
| cgroups v2            | improved version of v1                          |       |
| systemd cgroup driver | setting up a cgroup using systemd               |       |
| seccomp               | filtering system calls                          |       |
| hooks                 | add custom processing during container creation |       |
| rootless              | running a container without root privileges     | 🔶    |
| oci compliance        | compliance with OCI Runtime Spec                |       |

## License
Licensed under the [Apache License](https://github.com/navidys/thorcon/blob/main/LICENSE)
