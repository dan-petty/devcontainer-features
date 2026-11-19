
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
| compose | Compose tool. podman-compose needs no API service. docker-compose needs the API socket, so this value also starts the socket service of the remote user at container start. | string | podman-compose |
| dockerCompat | Install podman-docker (a docker command that runs podman), start the API socket service of the remote user at container start, and link /var/run/docker.sock to it. When a different package has /usr/bin/docker, the install skips this option. | boolean | false |

## Use

The remote user runs rootless Podman with `podman`. Rootful Podman runs with `sudo podman`. Podman has no daemon, so the Feature adds no group.

```jsonc
"features": {
    "ghcr.io/devcontainers/features/common-utils:2": {},
    "ghcr.io/dan-petty/devcontainer-features/podman-in-podman:1": {
        "dockerCompat": true,
        "compose": "docker-compose"
    }
}
```

The Feature installs Podman and its tools from the archive of the distribution, with no version pins. The versions change with the base image. The Feature supports Debian and Ubuntu images. The tests run on `debian:sid`, `debian:trixie` and `ubuntu:noble`, on linux/amd64 only.

## Security

The Feature sets `privileged: true`, as `docker-in-docker` does. The container then runs with no seccomp filter and with all capabilities. Use the Feature only for code that you trust.

## Start of the container

The entrypoint `/usr/local/share/podman-init.sh` runs at each start. When the container starts as a non-root user, the entrypoint uses `sudo`. A second run changes nothing. The entrypoint:

1. Makes the root mount shared.
2. Moves each process to the cgroup `/init` and gives the controllers to the child cgroups, as `docker-in-docker` does. Rootful limits such as `--memory` need this step.
3. Makes `/run/user/<uid>` for the remote user.
4. Writes the ranges of the remote user in `/etc/subuid` and `/etc/subgid` again when they are not in the ID map of the container. Under rootless Podman with `--userns=keep-id`, the ranges are `1:999` and `1001:64535`.
5. Starts `podman system service` for the remote user when `dockerCompat` is true or `compose` is `docker-compose`. With `dockerCompat`, `/var/run/docker.sock` is a link to its socket.

## Storage

Two volumes hold the images and containers: `/var/lib/containers` for rootful Podman and `/var/lib/containers-rootless/<user>` for rootless Podman. On the volume, rootless Podman uses native overlay and needs no `/dev/fuse`. The images stay when you rebuild the dev container.

When the ID map of the container changes, for example when you start it under Docker and then under rootless Podman, the entrypoint writes new subordinate ranges. The rootless storage made with the old ranges can then fail. Run `podman system reset` to remove it.

## Docker compatibility

`dockerCompat` installs `podman-docker`. Its `docker` command runs `podman`. When a different package has `/usr/bin/docker`, for example when `docker-in-docker` is installed, the Feature skips `dockerCompat` and prints `(!) A docker CLI is present; dockerCompat is skipped`.

`podman-compose` needs no API socket. `docker-compose` uses the API socket, so with `compose` set to `docker-compose`, the entrypoint starts the socket service. On `ubuntu:noble`, the `docker-compose` package is Compose version 1.

## Limits

- Next to `docker-in-docker`, rootful Podman on a bridge network has no network access to the outside: `dockerd` sets the policy of the iptables `FORWARD` chain to `DROP`. Rootless Podman and `sudo podman run --network host` work.
- Rootless Podman ignores `--memory`: the nested container gets no memory limit.
- WSL2 gives only the `cpu`, `memory` and `pids` controllers to a container. Podman in the container then cannot set `io` or `cpuset` limits.
- Podman 4 on `ubuntu:noble` uses `slirp4netns` for rootless networks by default. The Feature sets `pasta`, the default of Podman 5, for each version.


---

_Note: This file was auto-generated from the [devcontainer-feature.json](https://github.com/dan-petty/devcontainer-features/blob/main/src/podman-in-podman/devcontainer-feature.json).  Add additional notes to a `NOTES.md`._
