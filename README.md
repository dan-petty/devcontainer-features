# Dev Container Features for debian:sid

This repository holds [Dev Container Features](https://containers.dev/implementors/features/) that make `debian:sid` usable as a dev container image. It uses the format of [devcontainers/features](https://github.com/devcontainers/features).

## Purpose

A check on 2026-11-19 tried 12 of the 28 Features of `devcontainers/features` on `debian:sid`, and also the `claude-code` Feature of `anthropics/devcontainer-features`. 10 of the 12 Features install. The check did not include the other 16 Features. [Upstream Features that work on debian:sid](#upstream-features-that-work-on-debiansid) gives the result. The two Docker Features do not install: `docker-in-docker` and `docker-outside-of-docker` stop on the codename `forky`, and the Docker apt repository has no suite for `forky` or `sid`. This collection gives two Podman Features in their place:

- `podman-in-podman` runs a Podman engine in the dev container.
- `podman-outside-podman` gives the dev container a client for the Podman engine of the host.

Each Feature comes in its own pull request.

## Features

Each Feature pull request adds its row to this table.

| Feature | Reference | Description |
| --- | --- | --- |
| [podman-in-podman](src/podman-in-podman) | `ghcr.io/dan-petty/devcontainer-features/podman-in-podman:1` | Runs a Podman engine in the dev container: rootless Podman for the remote user, rootful Podman through sudo. |
| [podman-outside-podman](src/podman-outside-podman) | `ghcr.io/dan-petty/devcontainer-features/podman-outside-podman:1` | Gives the dev container a client for the Podman engine of the host, through the bind-mounted directory of the host socket. No engine runs in the container. |

## Upstream Features that work on debian:sid

A check on 2026-11-19 installed these Features on `debian:sid`. They need no Feature from this collection.

| Feature | Note |
| --- | --- |
| `ghcr.io/devcontainers/features/common-utils:2` | Installs as is. |
| `ghcr.io/devcontainers/features/copilot-cli:1` | Installs as is. |
| `ghcr.io/devcontainers/features/desktop-lite:1` | Installs as is. |
| `ghcr.io/devcontainers/features/git:1` | Installs as is, with `os-provided` and with `latest`. |
| `ghcr.io/devcontainers/features/git-lfs:1` | Installs the GitHub release, because its apt list has no `sid`. |
| `ghcr.io/devcontainers/features/github-cli:1` | Installs as is. |
| `ghcr.io/devcontainers/features/kubectl-helm-minikube:1` | Installs as is. |
| `ghcr.io/devcontainers/features/node:2` | Installs as is. |
| `ghcr.io/devcontainers/features/python:1` | Installs as is with `os-provided`. The check did not build Python from source. |
| `ghcr.io/devcontainers/features/sshd:1` | Installs as is. |
| `ghcr.io/anthropics/devcontainer-features/claude-code:1` | Installs only after `node:2`. Alone, it fails on `debian:sid`. |

The `sid_usable` scenario in `test/_global` installs `common-utils`, `git`, `node`, `github-cli`, `copilot-cli` and `claude-code` together with `podman-in-podman` on `debian:sid`. It checks each tool and runs a rootless Podman container as `vscode`. The weekly run of `test-all.yaml` runs the scenario, so the run fails when a change in `debian:sid` breaks one of these Features.

`ghcr.io/devcontainers/features/docker-in-docker` and `ghcr.io/devcontainers/features/docker-outside-of-docker` do not install on `debian:sid`. Use the Podman Features of this collection.

## Usage

Add a Feature to the `features` of your `devcontainer.json`, with its major version as the tag:

```jsonc
{
  "image": "debian:sid",
  "features": {
    "ghcr.io/dan-petty/devcontainer-features/<id>:1": {}
  }
}
```

The release publishes each Feature to `ghcr.io/dan-petty/devcontainer-features/<id>` with the tags `1`, `1.0`, `1.0.0` and `latest`. The collection metadata goes to `ghcr.io/dan-petty/devcontainer-features:latest`.

## Layout

```text
src/<id>/devcontainer-feature.json   metadata and options of the Feature
src/<id>/install.sh                  runs as root when the image is built
src/<id>/NOTES.md                    optional text for the README of the Feature
src/<id>/README.md                   written by `npm run docs`, do not edit
test/<id>/test.sh                    test of the default options
test/<id>/scenarios.json             optional scenarios, with one <scenario>.sh for each
test/_global/                        scenarios that combine Features
```

The folder name `<id>` must be the same as the `id` in `devcontainer-feature.json`. [CONTRIBUTING.md](CONTRIBUTING.md) gives the rules and the test commands.

## Specification

- [Dev Container Features reference](https://containers.dev/implementors/features/)
- [Distribution of Features](https://containers.dev/implementors/features-distribution/)
- [Best practices for Feature authors](https://containers.dev/guide/feature-authoring-best-practices)
- [Test command of the Dev Containers CLI](https://github.com/devcontainers/cli/blob/main/docs/features/test.md)
- [devcontainers/action](https://github.com/devcontainers/action), which validates and publishes the Features

## License

MIT. See [LICENSE](LICENSE). This repository started as a fork of `devcontainers/features`, so the license keeps the copyright line of Microsoft Corporation.
