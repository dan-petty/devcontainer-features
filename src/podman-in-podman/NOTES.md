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
4. Writes the ranges of the remote user in `/etc/subuid` and `/etc/subgid` again when they are not in the ID map of the container. Each range stays inside one line of the ID map, because the kernel refuses a range across two lines. Under rootless Podman with `--userns=keep-id` and a remote user with uid 1000, the ranges are `1:999` and `1001:64535`.
5. Starts `podman system service` for the remote user when `dockerCompat` is true or `compose` is `docker-compose`. With `dockerCompat`, `/var/run/docker.sock` is a link to its socket.

## Storage

Two volumes hold the images and containers: `/var/lib/containers` for rootful Podman and `/var/lib/containers-rootless/<user>` for rootless Podman. On the volume, rootless Podman uses native overlay and needs no `/dev/fuse`. The images stay when you rebuild the dev container.

The Feature sets `rootless_storage_path` in `/etc/containers/storage.conf`. When the image has no such file, the Feature makes it from `/usr/share/containers/storage.conf`. A drop-in file is not sufficient: containers/storage on `debian:trixie` and `ubuntu:noble` reads no `storage.rootless.conf.d` directory.

When the ID map of the container changes, for example when you start it under Docker and then under rootless Podman, the entrypoint writes new subordinate ranges. The rootless storage made with the old ranges can then fail. Run `podman system reset` to remove it.

## Docker compatibility

`dockerCompat` installs `podman-docker`. Its `docker` command runs `podman`. When a different package has `/usr/bin/docker`, for example when `docker-in-docker` is installed, the Feature skips `dockerCompat` and prints `(!) A docker CLI is present; dockerCompat is skipped`.

`podman-compose` needs no API socket. `docker-compose` uses the API socket, so with `compose` set to `docker-compose`, the entrypoint starts the socket service. On Ubuntu, the `docker-compose` package is Compose version 1. It imports `distutils`, which Python 3.12 removed. There, the Feature installs `docker-compose-v2`.

## Limits

- Next to `docker-in-docker`, rootful Podman on a bridge network has no network access to the outside: `dockerd` sets the policy of the iptables `FORWARD` chain to `DROP`. Rootless Podman and `sudo podman run --network host` work.
- Rootless Podman ignores `--memory`: the nested container gets no memory limit.
- WSL2 gives only the `cpu`, `memory` and `pids` controllers to a container. Podman in the container then cannot set `io` or `cpuset` limits.
- AppArmor of the host also applies its profiles to `podman` and `pasta` in the container. Ubuntu 26.04 has a `podman` profile, and its `pasta` profile refuses signals from that profile ([Debian bug 1100135](https://bugs.debian.org/1100135)). On such a host, rootless Podman cannot stop `pasta` when it removes the last container of a network. `docker compose down` then fails with `rootless netns: kill network process: permission denied`. `podman-compose down` prints the same error and exits 0.
- Podman 4 on `ubuntu:noble` uses `slirp4netns` for rootless networks by default. The Feature sets `pasta`, the default of Podman 5, for each version.
