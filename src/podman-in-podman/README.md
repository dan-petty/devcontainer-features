
# Podman in Podman (podman-in-podman)

Runs a Podman engine in the dev container. The remote user runs rootless Podman, and sudo runs rootful Podman.

## Example Usage

```json
"features": {
    "ghcr.io/dan-petty/devcontainer-features/podman-in-podman:1": {}
}
```

## Options

| Options Id | Description | Type | Default Value |
|-----|-----|-----|-----|
| buildah | Install buildah from the distribution archive. | boolean | true |
| skopeo | Install skopeo from the distribution archive. | boolean | true |
| compose | Compose tool. podman-compose runs the podman command and needs no API service. It is the compose provider of 'podman compose' and, with dockerCompat, of 'docker compose'. | string | podman-compose |
| dockerCompat | Install podman-docker (a docker command that runs podman), start a rootful Podman API service at container start, and link /var/run/docker.sock to its socket (root:docker 0660). No Docker CLI is installed. When docker-in-docker, docker-outside-of-docker or a different docker command is present, the install skips this option. | boolean | false |

## Use

The remote user runs rootless Podman with `podman`. Rootful Podman runs with `sudo podman`.

```jsonc
"features": {
    "ghcr.io/devcontainers/features/common-utils:2": {},
    "ghcr.io/dan-petty/devcontainer-features/podman-in-podman:1": {
        "dockerCompat": true
    }
}
```

With the default `compose=podman-compose`, `podman compose` and `podman-compose` run podman-compose. With `dockerCompat`, `docker compose` also runs it. podman-compose runs the `podman` command and needs no API service.

The Feature cannot be in one container with `podman-outside-podman`. The install of the second Feature stops with `(!) podman-in-podman and podman-outside-podman cannot be in one container.`

## Security

The Feature sets `privileged: true`, as `docker-in-docker` does. The container then runs with no seccomp filter and with all capabilities. Use the Feature only for code that you trust.

With `dockerCompat`, the remote user is in the group `docker`, and this group can use the socket of the rootful Podman API service. Access to the socket gives root in the container, as the group `docker` of `docker-in-docker` does.

## Start of the container

The entrypoint `/usr/local/share/podman-init.sh` runs at each start. When the container starts as a non-root user, the entrypoint uses `sudo -n`. A second run changes nothing. The entrypoint:

1. Makes the root mount shared.
2. Moves each process to the cgroup `/init` and gives the controllers to the child cgroups, as `docker-in-docker` does. Rootful limits such as `--memory` need this step.
3. Makes `/run/user/<uid>` for the remote user.
4. Writes the ranges of the remote user in `/etc/subuid` and `/etc/subgid` again when they are not in the ID map of the container. Each range stays inside one line of the ID map, because the kernel refuses a range across two lines. Under rootless Podman with `--userns=keep-id` and a remote user with uid 1000, the ranges are `1:999` and `1001:64535`.
5. With `dockerCompat`, starts the rootful Podman API service `podman system service --time=0 unix:///run/podman/podman.sock` when it does not run. Before the start, it removes the old socket and the old PID file. It sets the new socket to `root:docker` with mode `0660` and links `/var/run/docker.sock` to it.
6. Writes the file `/run/podman-in-podman/ready` at the end.

All runtime files are in `/run/podman-in-podman/`: `ready`, the PID file `podman-service.pid` and the log of the API service `podman-service.log`. Under Docker, `/run` is not a tmpfs, so the files stay after a stop and a start of the container. The service runs only when the PID file names a live process whose command line is `podman system service`. After a restart, the old PID can belong to a different process.

The Feature sets `postStartCommand` to `/usr/local/share/podman-check.sh`. The Dev Containers CLI does not wait for the entrypoint, so the script waits up to 60 seconds for the `ready` file. It runs as the remote user and runs `podman info`. With `dockerCompat`, it also runs `podman --url unix:///var/run/docker.sock info`. It prints one line that starts with `podman-in-podman:`. When a check fails, it prints a line that starts with `(!) podman-in-podman:` and names the log, and it exits 1. The Dev Containers CLI then does not run the later `postStartCommand` and `postAttachCommand` of the user.

## Docker compatibility

The Feature installs no Docker CLI, no Docker engine and no BuildKit. `dockerCompat` installs the package `podman-docker` of the distribution. Its `docker` command runs `podman`. For the remote user, `docker` runs rootless Podman. `sudo docker` runs rootful Podman. `docker build` and `docker buildx build` run `podman build` (Buildah). The file `/etc/containers/nodocker` stops the message "Emulate Docker CLI using podman".

The Feature skips `dockerCompat` when `/usr/local/share/docker-init.sh` of `docker-in-docker` or `docker-outside-of-docker` exists, or when a `docker` command on the `PATH` does not come from `podman-docker`. Then it installs no package, starts no API service and makes no link, and it prints one line that ends with `dockerCompat is skipped`. The reason: `podman-docker` conflicts with `docker-cli`, `docker.io` and `docker-ce-cli`, and its install removes them. `compose=podman-compose` still works, because it uses the `podman` command.

With `dockerCompat`, `/var/run/docker.sock` is a link to `/run/podman/podman.sock`, the socket of the rootful Podman API service. The socket is `root:docker` with mode `0660`. The Feature makes the system group `docker` when it is missing and adds the remote user. Docker API clients, for example Docker SDKs and Testcontainers, use `/var/run/docker.sock` by default. The tmpfiles.d rule of `podman-docker` names the same link, but the images have no `systemd-tmpfiles`, so the entrypoint makes the link.

`compose=podman-compose` writes `/etc/containers/containers.conf.d/50-podman-in-podman-compose.conf`. The file makes podman-compose the only compose provider of `podman compose` and stops the line ">>>> Executing external compose provider". Without the file, `podman compose` selects Docker Compose first when it is installed, and gives it the rootless socket in `/run/user/<uid>/podman/`, where no service runs. A Docker Compose that you install yourself uses `/var/run/docker.sock`, so it uses the rootful store.

There are two stores:

- The `podman`, `docker`, `docker compose` and `podman-compose` commands of the remote user use the rootless store `/var/lib/containers-rootless/<user>`.
- `sudo podman`, `sudo docker` and each client of `/var/run/docker.sock` use the rootful store `/var/lib/containers/storage`.

To copy an image from the rootless store to the rootful store, run `podman save <image> | sudo podman load`.

The Debian package `podman-docker` has the files `/etc/profile.d/podman-docker.sh` and `/etc/profile.d/podman-docker.csh`. A login shell that reads them sets `DOCKER_HOST` when it is not set. For root, the value is `unix:///run/podman/podman.sock`, the socket of this Feature. For another user with `XDG_RUNTIME_DIR`, the value is `unix://$XDG_RUNTIME_DIR/podman/podman.sock`, and no service runs there. Such a user sets `"DOCKER_HOST": "unix:///var/run/docker.sock"` in `remoteEnv`. The VS Code server gives `XDG_RUNTIME_DIR` to its extension host and to the processes under it. The package of `ubuntu:noble` has no such files.

The Feature sets no `containerEnv`. `CONTAINER_HOST` makes each `podman` command remote. Docker API clients use `/var/run/docker.sock` with no `DOCKER_HOST`.

## Storage

Two volumes hold the images and containers: `/var/lib/containers` for rootful Podman and `/var/lib/containers-rootless/<user>` for rootless Podman. On the volume, rootless Podman uses native overlay and needs no `/dev/fuse`. The images stay when you rebuild the dev container.

The Feature sets `rootless_storage_path` in `/etc/containers/storage.conf`. When the image has no such file, the Feature makes it from `/usr/share/containers/storage.conf`. A drop-in file is not sufficient: containers/storage on `debian:trixie` and `ubuntu:noble` reads no `storage.rootless.conf.d` directory.

When the ID map of the container changes, for example when you start it under Docker and then under rootless Podman, the entrypoint writes new subordinate ranges. The rootless storage made with the old ranges can then fail. Run `podman system reset` to remove it.

## Limits

- Next to `docker-in-docker`, rootful Podman on a bridge network has no network access to the outside: `dockerd` sets the policy of the iptables `FORWARD` chain to `DROP`. Rootless Podman and `sudo podman run --network host` work.
- Rootless Podman ignores `--memory`: the nested container gets no memory limit.
- WSL2 gives only the `cpu`, `memory` and `pids` controllers to a container. Podman in the container then cannot set `io` or `cpuset` limits.
- AppArmor of the host also applies its profiles to `podman` and `pasta` in the container. Ubuntu 26.04 has a `podman` profile, and its `pasta` profile refuses signals from that profile ([Debian bug 1100135](https://bugs.debian.org/1100135)). On such a host, rootless Podman cannot stop `pasta` when it removes the last container of a network. `podman-compose down` then prints `rootless netns: kill network process: permission denied` and exits 0. The rootful API service of `dockerCompat` uses no `pasta`.
- On `debian:sid`, aardvark-dns 1.17 puts an inotify watch on `/etc/resolv.conf`, and it stops when it cannot add the watch. When the host user has no free inotify watches, containers on a Podman network cannot find each other by name. Each nested user namespace counts against the same host user. The fix is on the host: raise `fs.inotify.max_user_watches`, or make other programs use fewer watches.
- Podman 4 on `ubuntu:noble` uses `slirp4netns` for rootless networks by default. The Feature sets `pasta`, the default of Podman 5, for the containers of each version. Podman 4 still starts the rootless network namespace of a user network with `slirp4netns`, so the Feature also installs `slirp4netns`. The `podman` package of `ubuntu:noble` also has the CNI file `/etc/cni/net.d/87-podman-bridge.conflist`, and the Feature installs no CNI plugins. The Feature sets the `netavark` network backend, so Podman does not read that file.

## OS support

The Feature supports Debian and Ubuntu images. It installs Podman and its tools from the archive of the distribution, with no version pins. The versions change with the base image. The tests run on `debian:sid`, `debian:trixie` and `ubuntu:noble`, on linux/amd64 only.


---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/dan-petty/devcontainer-features/blob/main/src/podman-in-podman/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
