## Use

The dev container gets the Podman remote client `podman-remote`, and `podman` is a link to it. `CONTAINER_HOST=unix:///run/podman/podman.sock` makes each `podman` command a client of the Podman engine of the host. No engine runs in the container.

```jsonc
"features": {
    "ghcr.io/devcontainers/features/common-utils:2": {},
    "ghcr.io/dan-petty/devcontainer-features/podman-outside-podman:1": {}
},
// Starts the rootless Podman socket of the host before the container.
"initializeCommand": "sh -c 'XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-/run/user/$(id -u)} systemctl --user start podman.socket'",
"remoteEnv": {
    "LOCAL_WORKSPACE_FOLDER": "${localWorkspaceFolder}"
}
```

With the default `compose=podman-compose`, `podman compose` and `podman-compose` run podman-compose. With `dockerCompat`, `docker compose` also runs it. podman-compose runs the `podman` command, so the services run on the host engine.

The Feature cannot be in one container with `podman-in-podman`: `CONTAINER_HOST` would send each `podman` command to the host. The install of the second Feature stops with `(!) podman-in-podman and podman-outside-podman cannot be in one container.`

## Security

Access to the socket gives the full power of the host engine. With a rootful Podman socket of the host, the container can get root on the host. With a rootless socket, it gets the rights of the host user. Use the Feature only for code that you trust.

The Feature sets `securityOpt: ["label=disable"]`, as `docker-outside-of-docker` does. This turns off the SELinux separation of the container. Without it, SELinux on the host refuses the access to the socket. The Dev Containers CLI also sets `label=disable` when it starts a container with Podman on Linux.

When the entrypoint starts the socat proxy, the group `docker` can use the client socket. The Feature adds the remote user to this group.

## Start of the container

The entrypoint `/usr/local/share/podman-init.sh` runs at each start. When the container starts as a non-root user, the entrypoint uses `sudo -n`. A second run changes nothing. The entrypoint:

1. Tests whether the remote user can write to the host socket `/run/podman-host/podman.sock`, with `runuser -u <user> -- test -w`. A connect to a Unix socket needs write permission, so the test makes no API call.
2. When the user can write to it, links `/run/podman/podman.sock` to the host socket. No proxy runs. This is the case of rootless Podman on the host with `--userns=keep-id`, when the remote user has the uid of the host user.
3. When the user cannot write to it, starts the proxy `socat UNIX-LISTEN:/run/podman/podman.sock,fork,user=root,group=docker,mode=660 UNIX-CONNECT:/run/podman-host/podman.sock` when it does not run. Before the start, it removes the old socket or link and the old PID file, because socat does not listen on a path that exists. This is the case of a rootful socket, of a socket of a different uid and of a socket that is not there yet.
4. With `dockerCompat`, links `/var/run/docker.sock` to `/run/podman/podman.sock`.
5. Writes the start time of PID 1 (field 22 of `/proc/1/stat`) to the file `/run/podman-outside-podman/ready` at the end. This value is new at each start of the container.

All runtime files are in `/run/podman-outside-podman/`: `ready`, the PID file `socat.pid` and the log of the proxy `socat.log`. Under Docker, `/run` is not a tmpfs, so the files stay after a stop and a start of the container. The proxy runs only when the PID file names a live process whose command line is `socat`. After a restart, the old PID can belong to a different process.

The Feature sets `postStartCommand` to `/usr/local/share/podman-check.sh`. The Dev Containers CLI does not wait for the entrypoint, so the script waits up to 60 seconds until the `ready` file holds the start time of the current PID 1. It runs as the remote user and runs `podman info` through `CONTAINER_HOST`. With `dockerCompat`, it also runs `podman --url unix:///var/run/docker.sock info`. It prints one line that starts with `podman-outside-podman:` and tells whether the host engine is rootless or rootful Podman. When a check fails, it prints a line that starts with `(!) podman-outside-podman:` and the fix on the host, and it exits 1. The Dev Containers CLI then does not run the later `postStartCommand` and `postAttachCommand` of the user. The `initializeCommand` of [Use](#use) starts the socket before the container and helps to prevent this failure.

## Docker compatibility

The Feature installs no Docker CLI, no Docker engine and no BuildKit. `dockerCompat` installs the package `podman-docker` of the distribution. Its `docker` command runs `/usr/bin/podman`, and `CONTAINER_HOST` makes that binary a client of the host engine. `docker version` shows the client and the Podman server of the host. `docker build` and `docker buildx build` run `podman build` (Buildah) on the host engine. The file `/etc/containers/nodocker` stops the message "Emulate Docker CLI using podman". All tools use one store: the store of the host engine.

`podman-docker` depends on the package `podman`. No engine process runs, but the package makes the image larger. A check on 2026-11-19 measured: with the default `compose=podman-compose`, `podman-docker` adds 32 to 41 packages and 105 to 184 MiB. With `compose=none`, it adds 37 to 48 packages and 105 to 187 MiB.

`sudo` removes `CONTAINER_HOST` from the environment. Thus `sudo docker` runs `/usr/bin/podman` as a local engine, and it fails with "cannot clone: Operation not permitted". `sudo podman` can also fail: on `debian:sid`, the `secure_path` of sudo has no `/usr/local/bin`, so `sudo podman` does not find the link to `podman-remote`. Run `docker` as the remote user, or run `sudo podman-remote`. As root, `podman-remote` uses `unix:///run/podman/podman.sock`, the client socket. The Feature does not change the sudo policy.

The Feature skips `dockerCompat` when `/usr/local/share/docker-init.sh` of `docker-in-docker` or `docker-outside-of-docker` exists, or when a `docker` command on the `PATH` does not come from `podman-docker`. Then it installs no package and makes no link, and it prints one line that ends with `dockerCompat is skipped`. The reason: `podman-docker` conflicts with `docker-cli`, `docker.io` and `docker-ce-cli`, and its install removes them. `compose=podman-compose` still works, because it uses the `podman` command.

With `dockerCompat`, `/var/run/docker.sock` is a link to `/run/podman/podman.sock`, the client socket. Docker API clients, for example Docker SDKs and Testcontainers, use `/var/run/docker.sock` by default. Without `dockerCompat`, the link does not exist, and only clients that read `CONTAINER_HOST` reach the host engine. When the entrypoint starts the proxy, the client socket is `root:docker` with mode `0660`. The Feature makes the system group `docker` when it is missing and adds the remote user, also without `dockerCompat`. The tmpfiles.d rule of `podman-docker` names the same link, but the images have no `systemd-tmpfiles`, so the entrypoint makes the link.

`compose=podman-compose` writes `/etc/containers/containers.conf.d/50-podman-outside-podman-compose.conf`. The file makes podman-compose the only compose provider of `podman compose` and stops the line ">>>> Executing external compose provider". Without the file, `podman compose` selects Docker Compose first when it is installed. On `ubuntu:noble`, Podman 4.9 then gives Docker Compose a local socket, not the `CONTAINER_HOST` value, and Docker Compose fails. A Docker Compose that you install yourself uses `/var/run/docker.sock`, which exists only with `dockerCompat`.

The Debian package `podman-docker` has the files `/etc/profile.d/podman-docker.sh` and `/etc/profile.d/podman-docker.csh`. A login shell that reads them sets `DOCKER_HOST` when it is not set. For root, the value is `unix:///run/podman/podman.sock`, the client socket of this Feature. For another user with `XDG_RUNTIME_DIR`, the value is `unix://$XDG_RUNTIME_DIR/podman/podman.sock`, and no socket is there. Such a user sets `"DOCKER_HOST": "unix:///var/run/docker.sock"` in `remoteEnv`. The VS Code server gives `XDG_RUNTIME_DIR` to its extension host and to the processes under it. The package of `ubuntu:noble` has no such files.

The Feature sets only `CONTAINER_HOST` in `containerEnv`. It sets no `DOCKER_HOST` and no `DOCKER_BUILDKIT`. The Dev Containers CLI writes `containerEnv` as `ENV` lines of the image, so a `DOCKER_BUILDKIT` value would also apply to the `dockerd` of `docker-in-docker`.

## Host socket

The Feature mounts the directory of the host socket at `/run/podman-host`, not the socket file. The default source is `${localEnv:XDG_RUNTIME_DIR:/run/user/1000}/podman`. The systemd unit `podman.socket` listens on `%t/podman/podman.sock`: for the rootless socket of a user, this is `$XDG_RUNTIME_DIR/podman/podman.sock`. When the host makes the socket again, a directory bind shows the new socket, and a file bind keeps the old one.

- The Dev Containers CLI replaces `${localEnv:...}` in the mounts of a Feature, also from the label of a prebuilt image. When `XDG_RUNTIME_DIR` is not set, for example in the VS Code WSL server, the source is `/run/user/1000/podman`. When `XDG_RUNTIME_DIR` is set but empty, the source is `/podman`.
- When the source directory is missing, the container does not start, as with `docker-outside-of-docker`. The error comes before the Feature can do a check. The `initializeCommand` of [Use](#use) starts the socket, and systemd makes the directory.
- A mount in `devcontainer.json` with the same target replaces the mount of the Feature. For a host user with a different uid, use the source `/run/user/<uid>/podman`. For rootful Podman on the host, use `/run/podman`. Its socket is `root:root` with mode `0660`, so the entrypoint starts the proxy:

```jsonc
"mounts": [
    {
        "source": "/run/podman",
        "target": "/run/podman-host",
        "type": "bind"
    }
]
```

When the check fails, start the Podman API service on the host:

- With systemd: on WSL, set `[boot] systemd=true` in `/etc/wsl.conf`. Then run `systemctl --user enable --now podman.socket` and `sudo loginctl enable-linger $USER`. Linger keeps the socket of the user when no session is open.
- Without systemd: run `podman system service --time=0 &`.

With rootless Podman on the host, the Dev Containers CLI starts the container with `--userns=keep-id` when the remote user is not root. When the remote user has the uid of the host user, the user owns the socket, and the entrypoint makes a link with no proxy.

## Bind mounts from the workspace folder

The host engine resolves the source of a bind mount (`-v <path>:<target>`) on the host, not in the dev container. A path of the dev container, for example `/workspaces/<repository>`, is not a path of the host. `remoteEnv` in [Use](#use) gives the host path of the workspace folder to the container as `LOCAL_WORKSPACE_FOLDER`. `containerEnv` of a Feature holds only constants, so this value goes in `devcontainer.json`.

Use the value in a compose file, with `./` as the fallback for a run on the host:

```yaml
services:
  app:
    volumes:
      - ${LOCAL_WORKSPACE_FOLDER:-./}:/src
```

On the command line, use `podman run -v "$LOCAL_WORKSPACE_FOLDER:/src" ...`. A named volume needs no host path: `podman volume create <name>` and `podman run -v <name>:/data` use the volume of the host engine.

## Limits

- A container of the host engine publishes its ports on the host, not in the dev container.
- `buildah` and `skopeo` use local storage, not the API of the host engine, so the Feature does not install them.
- The Dev Containers specification names only `${devcontainerId}` for the metadata of a Feature. The `${localEnv:...}` source is behavior of the Dev Containers CLI. Other tools, for example Codespaces or DevPod, can use the text without the substitution.
- The tests run on a runner with AppArmor. They do not test SELinux, a WSL host, Codespaces, DevPod or arm64.

## OS support

The Feature supports Debian and Ubuntu images. It installs `podman-remote`, `socat` and the optional tools from the archive of the distribution, with no version pins. The versions change with the base image. The tests run on `debian:sid`, `debian:trixie` and `ubuntu:noble`, on linux/amd64 only, with the Podman of the runner as the host engine.
